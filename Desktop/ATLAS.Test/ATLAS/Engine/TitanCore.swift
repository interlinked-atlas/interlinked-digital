import Foundation
import AppKit
import SwiftUI

// MARK: - TITAN CORE™ v2
//
// Hidden intelligence engine. Never shows popups or requires user action.
// Works silently in three phases:
//   1. Pre-flight  — checks conditions before install starts
//   2. Recovery    — auto-fixes failures and retries (replaces manual "Diagnose")
//   3. Verification — confirms the install is healthy after success
//
// Active on all plans when isEnabled is true.

@MainActor
final class TitanCore: ObservableObject {
    static let shared = TitanCore()
    private init() {}

    // TITAN CORE™ is always active — no user toggle.
    let isEnabled: Bool = true
    var isAvailable: Bool { true }

    // MARK: - Published state (drives inline UI only — no popups)

    @Published var isActive     = false
    @Published var currentAction = ""        // brief status shown in title bar badge
    @Published var lastRecovery: TitanRecovery? = nil

    enum TitanRecovery: Equatable {
        case recovered(action: String)         // auto-fix succeeded, shown green in result card
        case guidance(message: String)         // can't auto-fix, show specific advice inline
    }

    // MARK: - Storage decision (kept from v1 for Smart Storage integration)

    struct StorageDecisionLog {
        let storageType: String
        let mountPath: String
        let packageType: String
        let installSizeFormatted: String
    }

    func recordStorageDecision(
        storageType: String,
        mountPath: String,
        packageType: String,
        estimatedBytes: Int64
    ) {
        let log = StorageDecisionLog(
            storageType: storageType,
            mountPath: mountPath,
            packageType: packageType,
            installSizeFormatted: StorageVolume.format(estimatedBytes)
        )
        _ = log // retained for future logging/analytics
    }

    // MARK: - Pre-flight analysis

    struct PreflightResult {
        enum Status { case clear, warning, blocked }
        let status: Status
        let warnings: [String]
        let blockReason: String?
    }

    func preflight(url: URL, installerType: InstallerType) async -> PreflightResult {
        guard isAvailable else {
            return PreflightResult(status: .clear, warnings: [], blockReason: nil)
        }

        isActive = true
        currentAction = "Pre-flight check…"
        defer { isActive = false; currentAction = "" }

        var warnings: [String] = []

        // Check if a DAW is running when installing audio plugins
        if isAudioPlugin(installerType) {
            let daws = runningDAWs()
            if !daws.isEmpty {
                let list = daws.joined(separator: " and ")
                warnings.append("\(list) is open — quit it before installing audio plugins to avoid conflicts.")
            }
        }

        // Check if an app with the same name is currently running
        let baseName = url.deletingPathExtension().lastPathComponent
        if isProcessRunning(baseName) {
            warnings.append("\(baseName) appears to be running — quit it before reinstalling.")
        }

        // Check available disk space against a minimum threshold (500 MB)
        let freeBytes = availableDiskBytes()
        if freeBytes > 0 && freeBytes < 500 * 1024 * 1024 {
            let gb = String(format: "%.1f", Double(freeBytes) / (1024 * 1024 * 1024))
            return PreflightResult(
                status: .blocked,
                warnings: [],
                blockReason: "Only \(gb) GB free — not enough space to safely install. Free up disk space and try again."
            )
        }

        return PreflightResult(
            status: warnings.isEmpty ? .clear : .warning,
            warnings: warnings,
            blockReason: nil
        )
    }

    // MARK: - Smart recovery

    struct RecoveryResult {
        let canRetry: Bool
        let actionTaken: String
        let guidance: String?
    }

    func recover(
        url: URL,
        failureReason: String,
        attempt: Int,
        logger: Logger
    ) async -> RecoveryResult {
        guard isAvailable else {
            return RecoveryResult(canRetry: false, actionTaken: "titan inactive", guidance: nil)
        }
        guard attempt <= 2 else {
            let msg = "Maximum auto-recovery attempts reached. Check the install log for details."
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "max retries", guidance: msg)
        }

        isActive = true
        defer { isActive = false }

        let failure = classifyFailure(url: url, reason: failureReason)
        await logger.log("TITAN CORE™: Classified failure as \(failure)")

        switch failure {

        case .quarantine:
            currentAction = "TITAN CORE™: Clearing quarantine…"
            let ok = await clearQuarantine(url: url, logger: logger)
            currentAction = ""
            if ok {
                lastRecovery = .recovered(action: "cleared quarantine flag and retried")
                return RecoveryResult(canRetry: true, actionTaken: "cleared quarantine", guidance: nil)
            }
            let msg = "Could not clear the quarantine flag. Right-click the file in Finder → Open to bypass Gatekeeper manually."
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "quarantine clear failed", guidance: msg)

        case .unsigned:
            currentAction = "TITAN CORE™: Applying ad-hoc signature…"
            let ok = await applySignature(url: url, logger: logger)
            currentAction = ""
            if ok {
                lastRecovery = .recovered(action: "applied code signature and retried")
                return RecoveryResult(canRetry: true, actionTaken: "signed", guidance: nil)
            }
            let msg = "Could not sign the installer. Ensure ATLAS has Full Disk Access in System Settings."
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "signing failed", guidance: msg)

        case .permissions:
            currentAction = "TITAN CORE™: Diagnosing permissions…"
            let msg = await permissionGuidance()
            currentAction = ""
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "permission issue", guidance: msg)

        case .diskSpace:
            currentAction = ""
            let freeGB = String(format: "%.1f", Double(availableDiskBytes()) / (1024 * 1024 * 1024))
            let msg = "Not enough disk space — \(freeGB) GB free. Empty the Trash, remove large unused files, then retry."
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "disk space", guidance: msg)

        case .appInUse(let name):
            currentAction = ""
            let msg = "'\(name)' is running and cannot be replaced. Quit it, then retry the installation."
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "app in use", guidance: msg)

        case .mountError:
            // Mount failures are often transient — just signal a retry
            currentAction = ""
            lastRecovery = .recovered(action: "retried the disk image mount")
            return RecoveryResult(canRetry: true, actionTaken: "retry mount", guidance: nil)

        case .unknown:
            currentAction = ""
            // Still allow one retry for unknown failures — many are transient
            if attempt == 1 {
                lastRecovery = .recovered(action: "retried the installation")
                return RecoveryResult(canRetry: true, actionTaken: "generic retry", guidance: nil)
            }
            let msg = "TITAN CORE™ could not identify a specific fix. Review the install log for details."
            lastRecovery = .guidance(message: msg)
            return RecoveryResult(canRetry: false, actionTaken: "unknown", guidance: msg)
        }
    }

    // MARK: - Post-install verification

    func verify(installedFiles: [InstallRecord.InstalledFile], logger: Logger) async {
        guard isAvailable, !installedFiles.isEmpty else { return }

        isActive = true
        currentAction = "TITAN CORE™: Verifying…"
        defer { isActive = false; currentAction = "" }

        let fm = FileManager.default
        var issues: [String] = []

        for file in installedFiles.prefix(8) {
            let path = file.destinationPath
            guard fm.fileExists(atPath: path) else {
                issues.append("\(URL(fileURLWithPath: path).lastPathComponent) missing after install")
                continue
            }
            // For .app bundles: quick codesign validity check
            if path.hasSuffix(".app") {
                let r = InstallEngine.runProcess(
                    path: "/usr/bin/codesign",
                    arguments: ["-v", path])
                if r.output.contains("invalid") || r.output.contains("not signed") {
                    issues.append("\(URL(fileURLWithPath: path).lastPathComponent): code signature issue")
                }
            }
        }

        if issues.isEmpty {
            await logger.log("TITAN CORE™: ✓ Verification passed")
        } else {
            await logger.log("TITAN CORE™: ⚠ Verification found \(issues.count) issue(s):")
            for issue in issues { await logger.log("  · \(issue)") }
        }
    }

    // MARK: - State management

    func clearLastRecovery() { lastRecovery = nil }

    func deactivate() {
        isActive     = false
        currentAction = ""
    }

    // MARK: - Private: failure classification

    private enum FailureKind {
        case quarantine, unsigned, permissions, diskSpace
        case appInUse(String), mountError, unknown
    }

    private func classifyFailure(url: URL, reason: String) -> FailureKind {
        let lower = reason.lowercased()

        // Quarantine xattr present on the source file
        let xattr = InstallEngine.runProcess(
            path: "/usr/bin/xattr", arguments: ["-l", url.path])
        if xattr.output.contains("com.apple.quarantine") { return .quarantine }

        if lower.contains("no space") || lower.contains("disk space") ||
           lower.contains("not enough") { return .diskSpace }

        if lower.contains("resource busy") || lower.contains("in use") {
            return .appInUse(url.deletingPathExtension().lastPathComponent)
        }

        if lower.contains("permission") || lower.contains("denied") ||
           lower.contains("not permitted") { return .permissions }

        if lower.contains("mount") || lower.contains("hdiutil") { return .mountError }

        // Check code signature
        let cs = InstallEngine.runProcess(
            path: "/usr/bin/codesign", arguments: ["-v", url.path])
        if cs.output.contains("not signed") || cs.output.contains("no signature") {
            return .unsigned
        }

        return .unknown
    }

    // MARK: - Private: system checks

    private func isAudioPlugin(_ type: InstallerType) -> Bool {
        switch type {
        case .component, .vst3, .vst, .aax: return true
        default: return false
        }
    }

    private func runningDAWs() -> [String] {
        let knownDAWs = ["Logic Pro", "Pro Tools", "Ableton Live", "GarageBand",
                         "Studio One", "Cubase", "Nuendo", "Reaper", "FL Studio",
                         "Reason", "Digital Performer", "Bitwig Studio"]
        let ps = InstallEngine.runProcess(path: "/bin/ps", arguments: ["-ax", "-o", "comm="])
        return knownDAWs.filter { ps.output.contains($0) }
    }

    private func isProcessRunning(_ name: String) -> Bool {
        guard name.count > 3 else { return false }
        let ps = InstallEngine.runProcess(path: "/bin/ps", arguments: ["-ax", "-o", "comm="])
        return ps.output.lowercased().contains(name.lowercased())
    }

    private func availableDiskBytes() -> Int64 {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attrs?[.systemFreeSize] as? Int64) ?? 0
    }

    // MARK: - Private: recovery actions

    private func clearQuarantine(url: URL, logger: Logger) async -> Bool {
        guard let pwd = KeychainManager.loadPassword() else { return false }
        await logger.log("TITAN CORE™: Removing quarantine from \(url.lastPathComponent)")
        let r = await InstallEngine.runProcessWithPassword(
            password: pwd,
            arguments: ["/usr/bin/xattr", "-rd", "com.apple.quarantine", url.path])
        await logger.log(r.success ? "TITAN CORE™: ✓ Quarantine removed" : "TITAN CORE™: ✗ \(r.output)")
        return r.success
    }

    private func applySignature(url: URL, logger: Logger) async -> Bool {
        guard let pwd = KeychainManager.loadPassword() else { return false }
        await logger.log("TITAN CORE™: Applying ad-hoc codesign to \(url.lastPathComponent)")
        _ = await InstallEngine.runProcessWithPassword(
            password: pwd,
            arguments: ["/usr/bin/xattr", "-rd", "com.apple.quarantine", url.path])
        let r = await InstallEngine.runProcessWithPassword(
            password: pwd,
            arguments: ["/usr/bin/codesign", "--force", "--deep", "--sign", "-", url.path])
        await logger.log(r.success ? "TITAN CORE™: ✓ Signed" : "TITAN CORE™: ✗ \(r.output)")
        return r.success
    }

    private func permissionGuidance() async -> String {
        if !PermissionsManager.hasFullDiskAccess {
            return "ATLAS needs Full Disk Access. Go to System Settings → Privacy & Security → Full Disk Access and enable ATLAS."
        }
        if !PermissionsManager.hasAccessibility {
            return "ATLAS needs Accessibility access. Go to System Settings → Privacy & Security → Accessibility and enable ATLAS."
        }
        return "A permission was denied. Check System Settings → Privacy & Security and make sure ATLAS has all required permissions enabled."
    }
}
