import Foundation

struct ToggleError: Error {
    let message: String
    init(_ message: String) { self.message = message }
    var localizedDescription: String { message }
}

// PluginToggleEngine — ATLAS Library Enable/Disable for plugin formats (Pro only).
// Moves plugins between their system install location and ATLAS-managed disabled storage.
// All operations are reversible. Uses two-step move to handle cross-ownership boundaries
// (system plugin dirs require root; ATLAS disabled storage is in user home).

struct PluginToggleEngine {

    // MARK: - Known plugin directories ATLAS manages

    private static let managedDirectories: [String] = [
        "/Library/Audio/Plug-Ins/Components",
        "/Library/Audio/Plug-Ins/VST3",
        "/Library/Audio/Plug-Ins/VST",
        "/Library/Application Support/Avid/Audio/Plug-Ins",
    ]

    // MARK: - Disabled storage root

    static var disabledStorageRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/Disabled")
    }

    // MARK: - Disable

    /// Moves a plugin from its system install path to ATLAS disabled storage.
    /// Returns a DisabledFormatEntry on success, or an error string on failure.
    static func disable(
        destinationPath: String,
        formatKey: String,
        record: InstallRecord,
        allRecords: [InstallRecord]
    ) async -> Result<DisabledFormatEntry, ToggleError> {

        // Pro gate (engine level — never rely on UI alone)
        guard Features.enableDisable else {
            return .failure(ToggleError("Enable/Disable requires ATLAS Pro."))
        }

        // Ownership: the path must be tracked by this record's installedFiles
        guard record.installedFiles.contains(where: { $0.destinationPath == destinationPath }) else {
            return .failure(ToggleError("ATLAS cannot disable this plugin because it was not installed by this record."))
        }

        // Cross-record safety: no other active record may claim this path
        let otherOwners = allRecords.filter {
            $0.id != record.id && $0.status == .success &&
            $0.installedFiles.contains { $0.destinationPath == destinationPath }
        }
        guard otherOwners.isEmpty else {
            return .failure(ToggleError("Another installation record also tracks this file. ATLAS cannot safely disable it."))
        }

        // Path must be under a known ATLAS-managed plugin directory
        guard managedDirectories.contains(where: { destinationPath.hasPrefix($0) }) else {
            return .failure(ToggleError("This file is not in a known plugin directory. ATLAS only manages AU, VST, VST3, and AAX plugin folders."))
        }

        // File must exist at the install path
        guard FileManager.default.fileExists(atPath: destinationPath) else {
            return .failure(ToggleError("The plugin was not found at its tracked location:\n\(destinationPath)"))
        }

        // Prepare disabled storage path: ~/Library/Application Support/ATLAS/Disabled/<RecordID>/<filename>
        let storageDir = disabledStorageRoot.appendingPathComponent(record.id.uuidString)
        let filename   = URL(fileURLWithPath: destinationPath).lastPathComponent
        let storagePath = storageDir.appendingPathComponent(filename).path

        // Create storage directory
        do {
            try FileManager.default.createDirectory(at: storageDir, withIntermediateDirectories: true)
        } catch {
            return .failure(ToggleError("Could not create ATLAS disabled storage directory: \(error.localizedDescription)"))
        }

        // Remove stale storage if it exists (shouldn't, but be safe)
        if FileManager.default.fileExists(atPath: storagePath) {
            do { try FileManager.default.removeItem(atPath: storagePath) } catch {}
        }

        guard let password = KeychainManager.loadPassword() else {
            return .failure(ToggleError("No admin password stored. Set your Mac password in ATLAS Settings."))
        }

        // Single privileged move directly to disabled storage.
        // Two-step transit (sudo mv → temp, then FileManager.moveItem → storage) fails
        // because sudo mv preserves root:wheel ownership on the bundle; the subsequent
        // unprivileged rename(2) is rejected by macOS for root-owned directories.
        let mv = shell(password: password, command: "mv \(escapePath(destinationPath)) \(escapePath(storagePath))")
        guard mv.success else {
            return .failure(ToggleError("Could not move plugin to ATLAS disabled storage:\n\(mv.output)"))
        }

        // Verify
        guard FileManager.default.fileExists(atPath: storagePath),
              !FileManager.default.fileExists(atPath: destinationPath) else {
            return .failure(ToggleError("Disable verification failed. The plugin may be in an inconsistent state. Check both locations manually."))
        }

        let entry = DisabledFormatEntry(
            format: formatKey,
            originalPath: destinationPath,
            disabledStoragePath: storagePath,
            disabledAt: Date()
        )
        return .success(entry)
    }

    // MARK: - Enable

    /// Moves a plugin from ATLAS disabled storage back to its original system path.
    static func enable(
        entry: DisabledFormatEntry,
        allRecords: [InstallRecord]
    ) async -> Result<Void, ToggleError> {

        // Pro gate
        guard Features.enableDisable else {
            return .failure(ToggleError("Enable/Disable requires ATLAS Pro."))
        }

        // Disabled file must exist in ATLAS storage
        guard FileManager.default.fileExists(atPath: entry.disabledStoragePath) else {
            return .failure(ToggleError("The disabled plugin file could not be found in ATLAS storage:\n\(entry.disabledStoragePath)\n\nThe entry may be stale. Remove it from ATLAS Library and reinstall if needed."))
        }

        // Original path must not already have a file (would overwrite something)
        if FileManager.default.fileExists(atPath: entry.originalPath) {
            return .failure(ToggleError("A file already exists at the original plugin location:\n\(entry.originalPath)\n\nRemove or rename it before re-enabling."))
        }

        // Original path's parent directory must exist
        let parentDir = URL(fileURLWithPath: entry.originalPath).deletingLastPathComponent().path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parentDir, isDirectory: &isDir), isDir.boolValue else {
            return .failure(ToggleError("The plugin directory no longer exists:\n\(parentDir)"))
        }

        guard let password = KeychainManager.loadPassword() else {
            return .failure(ToggleError("No admin password stored. Set your Mac password in ATLAS Settings."))
        }

        // Single privileged move directly from disabled storage to the original system path.
        // Symmetric with disable: no transit, no unprivileged rename of a root-owned bundle.
        let mvIn = shell(password: password, command: "mv \(escapePath(entry.disabledStoragePath)) \(escapePath(entry.originalPath))")
        guard mvIn.success else {
            return .failure(ToggleError("Could not restore plugin to system directory:\n\(mvIn.output)"))
        }

        // Verify
        guard FileManager.default.fileExists(atPath: entry.originalPath) else {
            return .failure(ToggleError("Enable verification failed. The plugin may be in an inconsistent state."))
        }

        return .success(())
    }

    // MARK: - Consistency check (called from HistoryStore.load)
    // Detects and repairs stale DisabledFormatEntry records caused by crashes or
    // incomplete operations. Mutates records in place; caller must save if changed.
    @discardableResult
    static func repairDisabledEntries(in records: inout [InstallRecord]) -> Bool {
        var anyChanged = false
        for i in records.indices {
            guard var entries = records[i].disabledFormats else { continue }
            let before = entries.count

            entries = entries.filter { entry in
                let storageMissing  = !FileManager.default.fileExists(atPath: entry.disabledStoragePath)
                let originalPresent = FileManager.default.fileExists(atPath: entry.originalPath)
                if storageMissing && originalPresent {
                    // Enable completed but entry was never cleaned up — remove stale entry
                    return false
                }
                return true
            }

            if entries.count != before {
                records[i].disabledFormats = entries.isEmpty ? nil : entries
                anyChanged = true
            }
        }
        return anyChanged
    }

    // MARK: - Helpers

    private struct ShellResult { let success: Bool; let output: String }

    private static func shell(password: String, command: String) -> ShellResult {
        let full = "echo \(escapePath(password)) | sudo -S \(command) 2>&1"
        let p = Process()
        p.launchPath = "/bin/bash"
        p.arguments  = ["-c", full]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return ShellResult(success: false, output: error.localizedDescription) }
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ShellResult(success: p.terminationStatus == 0, output: out)
    }

    private static func escapePath(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
