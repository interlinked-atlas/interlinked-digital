import Foundation

// PreInstallChecker — runs lightweight system checks before any install starts.
// Returns a list of warnings (non-blocking) and blockers (abort the install).
// Never throws — all failures produce a graceful message.

struct PreInstallWarning {
    enum Severity { case warning, blocker }
    let severity: Severity
    let message: String
    var isBlocker: Bool { severity == .blocker }
}

struct PreInstallChecker {

    // Minimum free disk space required to attempt an install (1 GB).
    static let minimumFreeBytesRequired: Int64 = 1_073_741_824

    // MARK: - Entry point

    /// Run all pre-install checks and return any warnings.
    /// Call this once before starting the install queue — not per-item.
    static func check(urls: [URL]) -> [PreInstallWarning] {
        var warnings: [PreInstallWarning] = []

        if let w = checkDiskSpace(for: urls)   { warnings.append(w) }
        if let w = checkMacOSVersion()          { warnings.append(w) }
        if let w = checkSIP()                   { warnings.append(w) }
        if let w = checkDAWsOpen(for: urls)     { warnings.append(w) }

        return warnings
    }

    // MARK: - Disk space

    private static func checkDiskSpace(for urls: [URL]) -> PreInstallWarning? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let freeBytes = attrs[.systemFreeSize] as? Int64 else { return nil }

        if freeBytes < minimumFreeBytesRequired {
            let freeGB = String(format: "%.1f", Double(freeBytes) / 1_073_741_824)
            return PreInstallWarning(
                severity: .blocker,
                message: "Not enough disk space — \(freeGB) GB free. At least 1 GB is required to install safely.")
        }

        // Warn (not block) when under 5 GB — installs with large PKGs can fill the disk
        let warnThreshold: Int64 = 5_368_709_120
        if freeBytes < warnThreshold {
            let freeGB = String(format: "%.1f", Double(freeBytes) / 1_073_741_824)
            return PreInstallWarning(
                severity: .warning,
                message: "Low disk space — \(freeGB) GB free. Large installers may fail partway through.")
        }

        return nil
    }

    // MARK: - macOS version

    private static func checkMacOSVersion() -> PreInstallWarning? {
        let version = ProcessInfo.processInfo.operatingSystemVersion

        // Require macOS 12 Monterey or later (ATLAS minimum)
        if version.majorVersion < 12 {
            return PreInstallWarning(
                severity: .blocker,
                message: "macOS \(version.majorVersion).\(version.minorVersion) is not supported. ATLAS requires macOS 12 Monterey or later.")
        }

        // Soft warning for macOS 12/13 — some PKGs target 14+
        if version.majorVersion < 14 {
            return PreInstallWarning(
                severity: .warning,
                message: "You're on macOS \(version.majorVersion).\(version.minorVersion). Some newer products may require macOS 14 Sonoma or later.")
        }

        return nil
    }

    // MARK: - DAW open during plugin install

    private static func checkDAWsOpen(for urls: [URL]) -> PreInstallWarning? {
        // Only relevant if any file being installed is a plugin format
        let pluginExts = Set(["component","vst3","vst","aaxplugin","pkg","dmg","zip","rar"])
        let isPluginInstall = urls.contains { pluginExts.contains($0.pathExtension.lowercased()) }
        guard isPluginInstall else { return nil }

        let runningDAWs = DAWRescanAdvisor.runningDAWs()
        guard !runningDAWs.isEmpty else { return nil }

        let names = runningDAWs.joined(separator: ", ")
        return PreInstallWarning(
            severity: .warning,
            message: "\(names) is open. Close it before installing plugins, then reopen and rescan to load them.")
    }

    // MARK: - SIP status

    private static func checkSIP() -> PreInstallWarning? {
        let result = runProcess(path: "/usr/bin/csrutil", arguments: ["status"])
        let output = result.lowercased()

        // "system integrity protection status: disabled." → SIP is off
        // This is unusual and fine for installs — no warning needed.
        if output.contains("disabled") { return nil }

        // "enabled" → normal — no warning
        if output.contains("enabled") { return nil }

        // Could not determine (sandboxed, older macOS, or SIP in partial mode)
        return nil
    }

    // MARK: - Helpers

    @discardableResult
    private static func runProcess(path: String, arguments: [String]) -> String {
        let p = Process()
        p.launchPath = path
        p.arguments  = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
