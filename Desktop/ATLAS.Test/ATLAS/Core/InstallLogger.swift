import Foundation
import AppKit

// Returns a friendly device name like "User's MacBook Air" (strips .local suffix)
func deviceFriendlyName() -> String {
    let raw = Host.current().localizedName ?? "Mac"
    return raw.hasSuffix(".local") ? String(raw.dropLast(6)).replacingOccurrences(of: "-", with: " ") : raw
}

struct InstallLogger {

    // MARK: - Directories

    static var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ATLAS")
    }

    static var installedLogsDir: URL {
        logsDirectory.appendingPathComponent("Installed")
    }

    static var uninstalledLogsDir: URL {
        logsDirectory.appendingPathComponent("Uninstalled")
    }

    static var failedLogsDir: URL {
        logsDirectory.appendingPathComponent("Failed")
    }

    static var crashLogsDir: URL {
        logsDirectory.appendingPathComponent("Crashes")
    }

    // MARK: - Crash log capture

    /// Called at launch. Copies any ATLAS crash reports from the system
    /// DiagnosticReports folder into ~/Library/Logs/ATLAS/Crashes/ so the
    /// user can find them alongside install logs.
    static func captureCrashLogs() {
        let diagnosticDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports")

        guard let items = try? FileManager.default.contentsOfDirectory(
            at: diagnosticDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]) else { return }

        let atlasCrashes = items.filter {
            let name = $0.lastPathComponent.lowercased()
            let ext  = $0.pathExtension.lowercased()
            return (name.hasPrefix("atlas-") || name == "atlas") &&
                   (ext == "ips" || ext == "crash" || ext == "diag")
        }

        guard !atlasCrashes.isEmpty else { return }
        try? FileManager.default.createDirectory(
            at: crashLogsDir, withIntermediateDirectories: true)

        for src in atlasCrashes {
            let dest = crashLogsDir.appendingPathComponent(src.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: dest.path) else { continue }
            try? FileManager.default.copyItem(at: src, to: dest)
            // Upload newly captured crash log
            let uploadFilename = dest.lastPathComponent
            let uploadContent  = (try? String(contentsOf: dest, encoding: .utf8)) ?? ""
            let uploadDevice   = deviceFriendlyName()
            let uploadUUID     = atlasHardwareUUID()
            Task.detached {
                guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven") else { return }
                guard let s = KeychainManager.loadSession(), !s.isExpired else { return }
                try? await SupabaseService.shared.uploadLog(
                    accessToken: s.accessToken,
                    logType:     "crashed",
                    appName:     "ATLAS",
                    filename:    uploadFilename,
                    content:     uploadContent,
                    deviceName:  uploadDevice,
                    hardwareUUID: uploadUUID
                )
            }
        }

        print("[ATLAS] Captured \(atlasCrashes.count) crash report(s) to \(crashLogsDir.path)")
    }

    // MARK: - Install log

    @discardableResult
    static func writeLog(
        fileURL: URL,
        fileType: String,
        entries: [String],
        result: InstallResult,
        installedFiles: [InstallRecord.InstalledFile] = [],
        pkgReceiptIDs: [String] = [],
        remediationAttempted: Bool = false,
        sessionID: UUID? = nil
    ) -> InstallRecord {

        // Failed installs go to Failed/, successful installs go to Installed/
        let isFailed: Bool
        var failureReason: String? = nil
        let status: InstallRecord.InstallStatus
        switch result {
        case .success: isFailed = false; status = .success
        case .failure(let reason): isFailed = true; status = .failure; failureReason = reason
        }

        let dir = isFailed ? failedLogsDir : installedLogsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dateString = filenameDateString()
        let safeName   = sanitize(fileURL.lastPathComponent)
        let prefix     = isFailed ? "Failed" : "Install"
        let filename   = "\(prefix)_\(dateString)_\(safeName).log"
        let logURL     = dir.appendingPathComponent(filename)

        var lines: [String] = []
        if isFailed {
            lines.append("═══════════════════════════════════════════")
            lines.append("  ATLAS — INSTALLATION FAILED")
            lines.append("═══════════════════════════════════════════")
        } else {
            lines.append("═══════════════════════════════════════════")
            lines.append("  ATLAS Installation Log")
            lines.append("═══════════════════════════════════════════")
        }
        lines.append("")
        lines.append("Date:          \(fullDateString())")
        lines.append("ATLAS version: 3.0")
        lines.append("")
        lines.append("── System Information ──────────────────────")
        lines.append(contentsOf: systemInfo())
        lines.append("")
        lines.append("── File Information ────────────────────────")
        lines.append("File:          \(fileURL.lastPathComponent)")
        lines.append("Path:          \(fileURL.path)")
        lines.append("Size:          \(fileSize(fileURL))")
        lines.append("Type:          \(fileType)")
        lines.append("")

        // Failure reason block — shown prominently at the top for failed logs
        if isFailed, let reason = failureReason {
            lines.append("── Failure Reason ──────────────────────────")
            lines.append("  \(reason)")
            lines.append("")
            if remediationAttempted {
                lines.append("  NOTE: Automatic remediation was attempted before this failure.")
                lines.append("")
            }
        }

        lines.append("── Installation Log ────────────────────────")
        lines.append(contentsOf: entries)
        lines.append("")

        if !pkgReceiptIDs.isEmpty {
            lines.append("── PKG Receipts ────────────────────────────")
            for id in pkgReceiptIDs { lines.append("  \(id)") }
            lines.append("")
        }

        if !installedFiles.isEmpty {
            lines.append("── Installed Files (partial) ───────────────")
            for file in installedFiles {
                lines.append("  \(file.sourceName)")
                lines.append("    → \(file.destinationPath)")
            }
            lines.append("")
        }

        lines.append("── Result ──────────────────────────────────")
        switch result {
        case .success(let appName):
            lines.append("STATUS:  ✓ SUCCESS")
            lines.append("APP:     \(appName)")
        case .failure(let reason):
            lines.append("STATUS:  ✗ FAILURE")
            lines.append("REASON:  \(reason)")
            if !remediationAttempted {
                lines.append("")
                lines.append("  ATLAS did not attempt automatic remediation.")
            }
        }

        if remediationAttempted && !isFailed {
            lines.append("NOTE:    Automatic remediation was attempted")
        }

        lines.append("")
        lines.append("═══════════════════════════════════════════")

        let finalContent = lines.joined(separator: "\n")
        try? finalContent.write(to: logURL, atomically: true, encoding: .utf8)
        print("[ATLAS] \(isFailed ? "Failure" : "Install") log: \(logURL.path)")

        // Fire-and-forget: sync log to account dashboard
        let uploadAppName: String
        switch result {
        case .success(let name): uploadAppName = name
        case .failure:           uploadAppName = fileURL.lastPathComponent
        }
        let uploadType = isFailed ? "failed" : "install"
        let uploadFilename = filename
        let uploadContent = finalContent
        let uploadDevice = deviceFriendlyName()
        let uploadUUID = atlasHardwareUUID()
        Task.detached {
            guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven") else { return }
            guard let s = KeychainManager.loadSession(), !s.isExpired else { return }
            try? await SupabaseService.shared.uploadLog(
                accessToken: s.accessToken,
                logType: uploadType,
                appName: uploadAppName,
                filename: uploadFilename,
                content: uploadContent,
                deviceName: uploadDevice,
                hardwareUUID: uploadUUID
            )
        }

        return InstallRecord(
            id: UUID(),
            date: Date(),
            fileName: fileURL.lastPathComponent,
            fileType: fileType,
            installedFiles: installedFiles,
            pkgReceiptIDs: pkgReceiptIDs,
            status: status,
            failureReason: failureReason,
            logFileName: filename,
            sessionID: sessionID
        )
    }

    // MARK: - Uninstall log

    @discardableResult
    static func writeUninstallLog(
        record: InstallRecord,
        result: RollbackResult,
        entries: [String]
    ) -> String? {
        let dir = uninstalledLogsDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let dateString = filenameDateString()
        let safeName   = sanitize(record.fileName)
        let filename   = "Uninstall_\(dateString)_\(safeName).log"
        let logURL     = dir.appendingPathComponent(filename)

        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        let installedOn = df.string(from: record.date)

        var lines: [String] = []
        lines.append("═══════════════════════════════════════════")
        lines.append("  ATLAS Uninstall Log")
        lines.append("═══════════════════════════════════════════")
        lines.append("")
        lines.append("Date:              \(fullDateString())")
        lines.append("ATLAS version:     3.0")
        lines.append("")
        lines.append("── File Information ────────────────────────")
        lines.append("File:              \(record.fileName)")
        lines.append("Type:              \(record.fileType)")
        lines.append("Originally installed: \(installedOn)")
        lines.append("")
        lines.append("── Uninstall Log ───────────────────────────")
        lines.append(contentsOf: entries)
        lines.append("")

        if !result.removedFiles.isEmpty {
            lines.append("── Removed Files ───────────────────────────")
            for f in result.removedFiles.sorted() { lines.append("  ✓ \(f)") }
            lines.append("")
        }

        if !result.failedFiles.isEmpty {
            lines.append("── Failed ──────────────────────────────────")
            for f in result.failedFiles.sorted() { lines.append("  ✗ \(f)") }
            lines.append("")
        }

        lines.append("── Result ──────────────────────────────────")
        lines.append("STATUS:  \(result.success ? "✓ SUCCESS" : "✗ FAILURE")")
        lines.append("DETAIL:  \(result.detail)")
        lines.append("")
        lines.append("═══════════════════════════════════════════")

        let finalContent = lines.joined(separator: "\n")
        try? finalContent.write(to: logURL, atomically: true, encoding: .utf8)
        print("[ATLAS] Uninstall log: \(logURL.path)")

        let uploadFilename = filename
        let uploadContent = finalContent
        let uploadApp = record.fileName
        let uploadDevice = deviceFriendlyName()
        let uploadUUID = atlasHardwareUUID()
        Task.detached {
            guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven") else { return }
            guard let s = KeychainManager.loadSession(), !s.isExpired else { return }
            try? await SupabaseService.shared.uploadLog(
                accessToken: s.accessToken,
                logType: "uninstall",
                appName: uploadApp,
                filename: uploadFilename,
                content: uploadContent,
                deviceName: uploadDevice,
                hardwareUUID: uploadUUID
            )
        }
        return logURL.path
    }

    // MARK: - Retroactive sync

    // Uploads any local log files that haven't been synced yet.
    // Called once at app launch after the user is authenticated.
    // Uses a sentinel file to track which logs have already been uploaded.
    static func syncExistingLogs() {
        Task.detached {
            guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven") else { return }
            guard let s = KeychainManager.loadSession(), !s.isExpired else { return }

            let sentinelKey = "ATLAS.syncedLogNames"
            let alreadySynced = Set(UserDefaults.standard.stringArray(forKey: sentinelKey) ?? [])
            var newlySynced: [String] = []

            let dirs: [(URL, String)] = [
                (installedLogsDir,   "install"),
                (failedLogsDir,      "failed"),
                (uninstalledLogsDir, "uninstall"),
                (crashLogsDir,       "crashed"),
            ]

            for (dir, logType) in dirs {
                guard let items = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]) else { continue }

                for item in items where item.pathExtension == "log" || item.pathExtension == "ips" || item.pathExtension == "crash" {
                    let name = item.lastPathComponent
                    guard !alreadySynced.contains(name) else { continue }
                    guard let content = try? String(contentsOf: item, encoding: .utf8) else { continue }

                    let appName = name
                        .replacingOccurrences(of: "Install_", with: "")
                        .replacingOccurrences(of: "Failed_", with: "")
                        .replacingOccurrences(of: "Uninstall_", with: "")
                        .components(separatedBy: "_").dropFirst(2).joined(separator: " ")
                        .replacingOccurrences(of: ".log", with: "")

                    try? await SupabaseService.shared.uploadLog(
                        accessToken: s.accessToken,
                        logType: logType,
                        appName: appName.isEmpty ? name : appName,
                        filename: name,
                        content: content,
                        deviceName: deviceFriendlyName(),
                        hardwareUUID: atlasHardwareUUID()
                    )
                    newlySynced.append(name)
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s between uploads
                }
            }

            if !newlySynced.isEmpty {
                var updated = Array(alreadySynced) + newlySynced
                UserDefaults.standard.set(updated, forKey: sentinelKey)
                print("[ATLAS] Synced \(newlySynced.count) existing log(s) to account")
            }
        }
    }

    // MARK: - Finder

    static func openLogsInFinder() {
        NSWorkspace.shared.open(logsDirectory)
    }

    // MARK: - Helpers

    private static func filenameDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    private static func fullDateString() -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .long
        return f.string(from: Date())
    }

    private static func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "[/:\\s]", with: "-", options: .regularExpression)
    }

    private static func systemInfo() -> [String] {
        var info: [String] = []
        let v = ProcessInfo.processInfo.operatingSystemVersion
        info.append("macOS:         \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")
        info.append("Computer:      \(deviceFriendlyName())")
        #if arch(arm64)
        info.append("Architecture:  Apple Silicon (arm64)")
        #else
        info.append("Architecture:  Intel (x86_64)")
        #endif
        if let space = availableDiskSpace() { info.append("Free disk:     \(space)") }
        let ram = ProcessInfo.processInfo.physicalMemory
        info.append("RAM:           \(ram / (1024 * 1024 * 1024)) GB")
        return info
    }

    private static func fileSize(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size  = attrs[.size] as? Int64 else { return "Unknown" }
        if size < 1024            { return "\(size) B" }
        if size < 1024 * 1024    { return "\(size / 1024) KB" }
        if size < 1024 * 1024 * 1024 { return "\(size / (1024 * 1024)) MB" }
        return "\(size / (1024 * 1024 * 1024)) GB"
    }

    private static func availableDiskSpace() -> String? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free  = attrs[.systemFreeSize] as? Int64 else { return nil }
        return "\(free / (1024 * 1024 * 1024)) GB"
    }
}
