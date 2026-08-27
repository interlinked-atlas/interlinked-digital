import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Supporting types

enum RecoveryKitExportState: Equatable {
    case idle
    case exporting
    case complete(exportedAt: Date)
    case failed(String)
}

enum RecoveryKitImportState: Equatable {
    case idle
    case importing
    case loaded
    case hashMismatch        // hard rejection — no preview shown
    case failed(String)
}

// MARK: - Cloud recovery result

enum CloudKitRecoveryResult: Equatable {
    case success(kitId: UUID)
    case withIssues(kitId: UUID)

    var kitId: UUID {
        switch self {
        case .success(let id), .withIssues(let id): return id
        }
    }
}

// MARK: - RecoveryKitEngine

@MainActor
final class RecoveryKitEngine: ObservableObject {

    @Published private(set) var exportState:  RecoveryKitExportState = .idle
    @Published private(set) var importState:  RecoveryKitImportState = .idle
    @Published private(set) var importedKit:  AtlasKit? = nil
    @Published private(set) var isCrossMacKit: Bool = false
    @Published private(set) var cloudState:   CloudKitState = .idle
    @Published private(set) var cloudMeta:    [CloudKitMeta] = []

    // The UUID of the cloud kit most recently downloaded this session.
    // Set in downloadFromCloud() and used by markRecovered() — never references cloudMeta.first.
    private(set) var downloadedKitId: UUID? = nil

    // Persisted recovery result for the most recently recovered backup.
    @Published private(set) var lastRecoveryResult: CloudKitRecoveryResult? = nil

    // Set after a successful export — uploadToCloud() reads actual files from here.
    private(set) var lastGeneratedKitFolderURL: URL? = nil

    // Set after a successful cloud upload — prevents re-uploading the same kit.
    private var lastUploadedKitFolderURL: URL? = nil

    init() {
        // Restore persisted recovery result across relaunches
        if let idStr = UserDefaults.standard.string(forKey: "atlas.lastRecoveredKitId"),
           let kitId = UUID(uuidString: idStr) {
            let outcome = UserDefaults.standard.string(forKey: "atlas.lastRecoveredKitResult")
            lastRecoveryResult = outcome == "withIssues" ? .withIssues(kitId: kitId) : .success(kitId: kitId)
        }
    }

    // Called by ContentView when RecoveryModeEngine.isComplete becomes true.
    // successCount comes from RecoveryModeEngine.successCount at that moment.
    // Always uses downloadedKitId — never cloudMeta.first — so it stamps the correct backup.
    func markRecovered(successCount: Int) {
        guard let kitId = downloadedKitId else { return }
        let result: CloudKitRecoveryResult = successCount > 0 ? .success(kitId: kitId) : .withIssues(kitId: kitId)
        lastRecoveryResult = result
        UserDefaults.standard.set(kitId.uuidString, forKey: "atlas.lastRecoveredKitId")
        UserDefaults.standard.set(successCount > 0 ? "success" : "withIssues", forKey: "atlas.lastRecoveredKitResult")
    }

    // Test injection: set true in DEBUG to make .txt write throw
    #if DEBUG
    var injectTxtFailure: Bool = false
    #endif

    // MARK: - Export (folder-based)

    func export(store: HistoryStore) async {
        exportState = .exporting

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let activeRecords   = store.records
        let archivedRecords = store.archivedRecords

        // Folder name: "ATLAS RECOVERY KIT - Month Day Year"
        let df = DateFormatter()
        df.dateFormat = "MMMM d yyyy"
        let folderName = "ATLAS RECOVERY KIT - \(df.string(from: Date()))"

        // Ask user to choose a DESTINATION DIRECTORY (not a file save path)
        guard let destParent = await showExportDestinationPanel() else {
            exportState = .idle
            return
        }

        let destFolderURL = destParent.appendingPathComponent(folderName)

        // Reject if destination already exists (do not silently overwrite)
        if FileManager.default.fileExists(atPath: destFolderURL.path) {
            exportState = .failed("A Recovery Kit folder for today already exists at that location. Move or rename it before exporting a new one.")
            return
        }

        do {
            try await Task.detached(priority: .userInitiated) { [weak self] in
                let sanitized   = activeRecords.map { SanitizedRecord(from: $0) }
                let sanitizedAr = archivedRecords.map { SanitizedRecord(from: $0) }

                // Phase 1: build kit with empty hash, compute hash
                var kit = AtlasKit(
                    kitVersion: 1,
                    atlasVersion: appVersion,
                    exportedAt: Date(),
                    payloadHash: "",
                    records: sanitized,
                    archivedRecords: sanitizedAr
                )
                let hash = try AtlasKit.computeHash(for: kit)
                kit.payloadHash = hash

                // Phase 2: write both files to a temp folder, then atomically move to dest
                let fm = FileManager.default
                let tmpFolder = fm.temporaryDirectory
                    .appendingPathComponent("atlas_rk_\(UUID().uuidString)")
                try fm.createDirectory(at: tmpFolder, withIntermediateDirectories: true)

                let atlaskitURL = tmpFolder.appendingPathComponent("kit.atlaskit")
                let txtURL      = tmpFolder.appendingPathComponent("kit.txt")

                let kitData = try AtlasKit.makeEncoder().encode(kit)
                try kitData.write(to: atlaskitURL, options: [.atomic])

                let txtContent = RecoveryKitEngine.generateTxtReport(kit: kit)

                #if DEBUG
                if await self?.injectTxtFailure == true {
                    try? fm.removeItem(at: tmpFolder)
                    throw RecoveryKitError.txtWriteFailed("injected failure")
                }
                #endif

                do {
                    try Data(txtContent.utf8).write(to: txtURL, options: [.atomic])
                } catch {
                    try? fm.removeItem(at: tmpFolder)
                    throw RecoveryKitError.txtWriteFailed(error.localizedDescription)
                }

                // Atomic move: temp folder → final destination
                do {
                    try fm.moveItem(at: tmpFolder, to: destFolderURL)
                } catch {
                    try? fm.removeItem(at: tmpFolder)
                    throw RecoveryKitError.folderMoveFailed(error.localizedDescription)
                }
            }.value

            exportState = .complete(exportedAt: Date())
            lastGeneratedKitFolderURL = destFolderURL

            // Automatically sync to cloud — only if Pro and signed in.
            // uploadToCloud() is a no-op if already uploading or already synced this kit.
            if Features.cloudRecoveryKit,
               AuthManager.shared.isSignedIn,
               AuthManager.shared.isPro {
                await uploadToCloud(store: store)
            }
        } catch {
            exportState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Import

    /// Resets import state — called when Recovery Mode exits.
    func resetImportState() {
        importedKit   = nil
        isCrossMacKit = false
        importState   = .idle
    }

    // MARK: - Testable folder-resolution (extracted for unit testing)

    /// Resolves a user-selected URL to the actual .atlaskit file URL.
    /// If `url` is a regular file, returns it unchanged.
    /// If `url` is a directory, looks for `kit.atlaskit` inside and throws if absent.
    nonisolated static func resolveKitURL(_ url: URL) throws -> URL {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        guard isDir.boolValue else { return url }
        let candidate = url.appendingPathComponent("kit.atlaskit")
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            throw RecoveryKitError.kitNotFoundInFolder
        }
        return candidate
    }

    // MARK: - Testable kit-writing (extracted for unit testing)

    /// Writes kit.atlaskit and kit.txt into `destFolder` (which must not yet exist).
    /// Uses a temp directory + atomic move. Returns the folder URL on success.
    /// Throws on hash failure, txt write failure, or move failure.
    nonisolated static func writeKitFolder(kit: AtlasKit, to destFolder: URL) throws {
        if FileManager.default.fileExists(atPath: destFolder.path) {
            throw RecoveryKitError.folderMoveFailed("Destination folder already exists: \(destFolder.lastPathComponent)")
        }
        let fm = FileManager.default
        let tmpFolder = fm.temporaryDirectory.appendingPathComponent("atlas_rk_\(UUID().uuidString)")
        try fm.createDirectory(at: tmpFolder, withIntermediateDirectories: true)

        let atlaskitURL = tmpFolder.appendingPathComponent("kit.atlaskit")
        let txtURL      = tmpFolder.appendingPathComponent("kit.txt")

        let kitData = try AtlasKit.makeEncoder().encode(kit)
        try kitData.write(to: atlaskitURL, options: [.atomic])

        let txtContent = RecoveryKitEngine.generateTxtReport(kit: kit)
        do {
            try Data(txtContent.utf8).write(to: txtURL, options: [.atomic])
        } catch {
            try? fm.removeItem(at: tmpFolder)
            throw RecoveryKitError.txtWriteFailed(error.localizedDescription)
        }

        do {
            try fm.moveItem(at: tmpFolder, to: destFolder)
        } catch {
            try? fm.removeItem(at: tmpFolder)
            throw RecoveryKitError.folderMoveFailed(error.localizedDescription)
        }
    }

    /// Import is strictly read-only.
    /// No store parameter — structurally prevents any HistoryStore access.
    /// No filesystem writes. No path execution. Hash mismatch = hard rejection, no preview.
    /// Accepts both standalone .atlaskit files and Recovery Kit folders containing kit.atlaskit.
    func importKit() async {
        importState = .importing
        importedKit = nil
        isCrossMacKit = false

        guard let selectedURL = await showOpenPanel() else {
            importState = .idle
            return
        }

        let homeDir = NSHomeDirectory()

        do {
            let result: (kit: AtlasKit, isCrossMac: Bool) = try await Task.detached(priority: .userInitiated) {
                // Folder-resolution via extracted testable method
                let fileURL = try RecoveryKitEngine.resolveKitURL(selectedURL)

                let data = try Data(contentsOf: fileURL)

                // Decode
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let kit = try decoder.decode(AtlasKit.self, from: data)

                // Hash verification — hard rejection on mismatch
                let storedHash = kit.payloadHash
                let recomputed = try AtlasKit.computeHash(for: kit)
                guard storedHash == recomputed else {
                    throw RecoveryKitError.hashMismatch
                }

                // Cross-Mac detection: any installed file path not under current home
                let isCrossMac = kit.records.contains { record in
                    record.installedFiles.contains { file in
                        !file.destinationPath.hasPrefix(homeDir) &&
                        !file.destinationPath.hasPrefix("/Library") &&
                        !file.destinationPath.hasPrefix("/usr") &&
                        !file.destinationPath.hasPrefix("/Applications")
                    }
                }

                return (kit, isCrossMac)
            }.value

            importedKit = result.kit
            isCrossMacKit = result.isCrossMac
            importState = .loaded
        } catch RecoveryKitError.hashMismatch {
            // Hard rejection — importedKit remains nil, no preview
            importedKit = nil
            importState = .hashMismatch
        } catch {
            importedKit = nil
            importState = .failed(error.localizedDescription)
        }
    }

    // MARK: - .txt report generation (pure — no filesystem access)

    nonisolated static func generateTxtReport(kit: AtlasKit) -> String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime]

        let displayDF: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        var lines: [String] = []

        lines.append("ATLAS RECOVERY KIT™")
        lines.append("Generated by ATLAS \(kit.atlasVersion) on \(displayDF.string(from: kit.exportedAt))")
        lines.append("Exported: \(df.string(from: kit.exportedAt))")
        lines.append("Records: \(kit.records.count) installed  \(kit.archivedRecords.count) archived")
        lines.append("")
        lines.append(String(repeating: "═", count: 64))

        func appendRecords(_ records: [SanitizedRecord], header: String) {
            lines.append("")
            lines.append("\(header) (\(records.count))")
            lines.append("")

            for record in records {
                lines.append(String(repeating: "─", count: 64))
                lines.append("Product:         \(record.fileName)")
                lines.append("Installed:       \(displayDF.string(from: record.date))")
                lines.append("Format:          \(record.fileType)")
                lines.append("Status:          \(record.status.rawValue.capitalized)")

                if let v = record.titanVerified {
                    lines.append("TITAN Verified:  \(v ? "Yes" : "No")")
                }
                if let v = record.activationRequired {
                    lines.append("Activation:      \(v ? "Required" : "Not Required")")
                }
                if let v = record.demoDetected {
                    lines.append("Demo Detected:   \(v ? "Yes" : "No")")
                }

                if !record.installedFiles.isEmpty {
                    lines.append("")
                    lines.append("Installed Files:")
                    for f in record.installedFiles {
                        lines.append("  • \(f.destinationPath)")
                    }
                }

                if let formats = record.disabledFormats, !formats.isEmpty {
                    lines.append("")
                    lines.append("Disabled Formats:")
                    for f in formats {
                        lines.append("  • \(f.format.uppercased()): \(f.originalPath)")
                    }
                }

                if let hosts = record.addedHostsEntries, !hosts.isEmpty {
                    lines.append("")
                    lines.append("Hosts Entries Added:")
                    for h in hosts { lines.append("  • \(h)") }
                }

                if let w = record.verificationWarning {
                    lines.append("")
                    lines.append("Verification Warning: \(w)")
                }

                if let r = record.archiveReason {
                    lines.append("Archive Reason:  \(r)")
                }

                lines.append("")
            }
        }

        appendRecords(kit.records, header: "INSTALLED PRODUCTS")
        lines.append(String(repeating: "═", count: 64))
        appendRecords(kit.archivedRecords, header: "ARCHIVED PRODUCTS")
        lines.append(String(repeating: "═", count: 64))
        lines.append("")
        lines.append("This file is a human-readable reference only.")
        lines.append("No license keys, serial numbers, or activation codes are included.")
        lines.append("Generated by ATLAS — interlinked.digital")

        return lines.joined(separator: "\n")
    }

    // MARK: - Panel helpers (MainActor)

    /// Asks the user to pick a destination DIRECTORY for the Recovery Kit folder.
    private func showExportDestinationPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Location"
        panel.message = "Choose where to save your ATLAS Recovery Kit folder"
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }

    /// Accepts both a standalone .atlaskit file and a Recovery Kit folder.
    private func showOpenPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Load ATLAS Recovery Kit"
        panel.message = "Select a .atlaskit file or an ATLAS Recovery Kit folder"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}

// MARK: - Cloud Recovery Kit state

enum CloudKitState: Equatable {
    case idle
    case loading
    case notFound
    case found
    case uploading
    case downloading
    case error(String)
}

// MARK: - Cloud operations (additive — all existing functions unchanged)

extension RecoveryKitEngine {

    func loadCloudKitMetadata() async {
        guard Features.cloudRecoveryKit,
              let token = AuthManager.shared.session?.accessToken else {
            // No valid token — exit spinner immediately rather than staying in .idle forever
            cloudState = .notFound
            cloudMeta  = []
            return
        }
        cloudState = .loading
        do {
            let kits = try await CloudRecoveryKitService.shared.list(token: token)
            cloudMeta  = kits
            cloudState = kits.isEmpty ? .notFound : .found
        } catch {
            cloudMeta  = []
            cloudState = .error(error.localizedDescription)
        }
    }

    // Uploads the ACTUAL kit.atlaskit + kit.txt bytes from the last successful local export.
    // Must call export() first — errors if lastGeneratedKitFolderURL is nil.
    func uploadToCloud(store: HistoryStore) async {
        // Prevent concurrent uploads
        guard cloudState != .uploading else { return }
        guard let token = AuthManager.shared.session?.accessToken else {
            cloudState = .error("Not signed in.")
            return
        }
        guard let folderURL = lastGeneratedKitFolderURL else {
            cloudState = .error("Export a Recovery Kit first, then sync to cloud.")
            return
        }
        // Prevent re-uploading a kit that already synced successfully
        guard folderURL != lastUploadedKitFolderURL else { return }
        let atlaskitURL = folderURL.appendingPathComponent("kit.atlaskit")
        let txtURL      = folderURL.appendingPathComponent("kit.txt")
        guard let atlaskitData = try? Data(contentsOf: atlaskitURL),
              let txtData      = try? Data(contentsOf: txtURL) else {
            cloudState = .error("Recovery Kit files not found. Export again before syncing.")
            return
        }
        // Read metadata from the kit file itself so server record matches exactly
        let kitDecoder = JSONDecoder()
        kitDecoder.dateDecodingStrategy = .iso8601
        guard let kit = try? kitDecoder.decode(AtlasKit.self, from: atlaskitData) else {
            cloudState = .error("Could not read Recovery Kit metadata.")
            return
        }
        cloudState = .uploading
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        do {
            let meta = try await CloudRecoveryKitService.shared.upload(
                kitAtlaskitData: atlaskitData,
                kitTxtData:      txtData,
                generatedAt:     kit.exportedAt,
                atlasVersion:    appVersion,
                kitVersion:      kit.kitVersion,
                recordCount:     kit.records.count,
                archivedCount:   kit.archivedRecords.count,
                token:           token
            )
            cloudMeta  = [meta] + cloudMeta
            cloudState = .found
            lastUploadedKitFolderURL = folderURL   // mark synced — prevents duplicate upload
        } catch {
            cloudState = .error(error.localizedDescription)
        }
    }

    func downloadFromCloud(kitId: UUID) async {
        guard let token = AuthManager.shared.session?.accessToken else {
            cloudState = .error("Not signed in.")
            return
        }
        cloudState = .downloading
        let homeDir = NSHomeDirectory()
        do {
            let atlaskitData = try await CloudRecoveryKitService.shared.download(kitId: kitId, token: token)
            let rkDecoder = JSONDecoder()
            rkDecoder.dateDecodingStrategy = .iso8601
            let kit = try rkDecoder.decode(AtlasKit.self, from: atlaskitData)
            // Verify hash (computeHash zeroes payloadHash on a copy internally)
            let expectedHash = kit.payloadHash
            let computedHash = try AtlasKit.computeHash(for: kit)
            guard computedHash == expectedHash else {
                importedKit = nil
                importState = .hashMismatch
                cloudState  = .error("Recovery Kit integrity check failed — it may be corrupted.")
                return
            }
            let isCrossMac = kit.records.contains { record in
                record.installedFiles.contains { file in
                    !file.destinationPath.hasPrefix(homeDir) &&
                    !file.destinationPath.hasPrefix("/Library") &&
                    !file.destinationPath.hasPrefix("/usr") &&
                    !file.destinationPath.hasPrefix("/Applications")
                }
            }
            downloadedKitId = kitId   // stamp the specific backup that was downloaded
            importedKit   = kit
            isCrossMacKit = isCrossMac
            importState   = .loaded
            cloudState    = .found
        } catch RecoveryKitError.hashMismatch {
            importedKit = nil
            importState = .hashMismatch
            cloudState  = .error("Recovery Kit integrity check failed — it may be corrupted.")
        } catch {
            cloudState = .error(error.localizedDescription)
        }
    }
}

// MARK: - Errors

enum RecoveryKitError: Error, LocalizedError {
    case hashMismatch
    case txtWriteFailed(String)
    case folderMoveFailed(String)
    case kitNotFoundInFolder

    var errorDescription: String? {
        switch self {
        case .hashMismatch:
            return "This Recovery Kit file has been modified or corrupted and cannot be loaded."
        case .txtWriteFailed(let msg):
            return "Failed to write the text report: \(msg)"
        case .folderMoveFailed(let msg):
            return "Failed to save the Recovery Kit folder: \(msg)"
        case .kitNotFoundInFolder:
            return "No kit.atlaskit file found in the selected folder."
        }
    }
}
