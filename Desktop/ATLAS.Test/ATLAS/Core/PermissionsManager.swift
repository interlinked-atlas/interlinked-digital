import AppKit
import Foundation
import ApplicationServices

struct PermissionsManager {

    // MARK: - Onboarding flag

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: "atlas.onboardingDone") }
        set { UserDefaults.standard.set(newValue, forKey: "atlas.onboardingDone") }
    }

    // MARK: - Manual confirmation flags
    //
    // These are written by the real checks (not by the user) and used ONLY as:
    //   • A synchronous initial value for UI state before the async check completes
    //   • A last-resort fallback when every probe returns ENOENT (file absent — rare)
    //
    // They are NEVER allowed to override a definitive result from the real API.
    // When the real check says NO with a hard error (EACCES / AXIsProcessTrusted=false),
    // the stored flag is immediately cleared so it cannot cause a false positive next launch.

    static var accessibilityManuallyConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: "atlas.perm.acc.confirmed") }
        set { UserDefaults.standard.set(newValue, forKey: "atlas.perm.acc.confirmed") }
    }

    static var fullDiskManuallyConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: "atlas.perm.fda.confirmed") }
        set { UserDefaults.standard.set(newValue, forKey: "atlas.perm.fda.confirmed") }
    }

    static var automationManuallyConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: "atlas.perm.auto.confirmed") }
        set { UserDefaults.standard.set(newValue, forKey: "atlas.perm.auto.confirmed") }
    }

    // MARK: - Running from DMG?

    static var isRunningFromDMG: Bool {
        Bundle.main.bundlePath.hasPrefix("/Volumes/")
    }

    // MARK: - Accessibility

    static var hasAccessibility: Bool {
        // AXIsProcessTrustedWithOptions is the definitive macOS TCC API for Accessibility.
        // It is the ONLY signal we trust. If it returns false the permission is not granted —
        // no manual flag can override this.
        let trusted = AXIsProcessTrustedWithOptions(nil)

        // Keep the stored flag in sync so next launch has accurate initial state.
        if accessibilityManuallyConfirmed != trusted {
            accessibilityManuallyConfirmed = trusted
        }

        return trusted
    }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    // MARK: - Full Disk Access
    //
    // Strategy: probe files that are definitively gated by macOS TCC on all macOS 12+ systems.
    // errno distinguishes between "denied" (EACCES/EPERM) and "absent" (ENOENT).
    // Real probe results always win — the stored flag is only used when every probe
    // returns ENOENT (genuinely absent file, not a TCC block).

    static var hasFullDiskAccess: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // These files exist on all macOS 12+ systems and are always TCC-protected.
        // /private/var/db/TCC/TCC.db is the most reliable — present and gated on every build.
        let paths: [String] = [
            "/private/var/db/TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
        ]

        for path in paths {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                // File opened — FDA is definitively granted.
                close(fd)
                fullDiskManuallyConfirmed = true
                return true
            }
            switch errno {
            case EPERM, EACCES:
                // TCC blocked access — FDA is definitively NOT granted.
                // Clear any stale stored flag so it can't cause a false positive next launch.
                fullDiskManuallyConfirmed = false
                return false
            default:
                // ENOENT or other — file absent on this machine, try next probe.
                break
            }
        }

        // Every probe returned ENOENT — unusual but possible on a stripped-down system.
        // Fall back to the stored flag (defaults to false on a fresh install).
        return fullDiskManuallyConfirmed
    }

    static func openFullDiskAccessSettings() {
        openPrivacyPane("Privacy_AllFiles")
    }

    // MARK: - Automation / Apple Events
    //
    // Always runs the real osascript check — never short-circuits with the stored flag.
    // The stored flag is updated from the result so it stays accurate for the next launch.

    static func checkAutomationPermission(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments     = ["-e", "tell application \"System Events\" to return name of first process"]
            p.standardOutput = Pipe()
            p.standardError  = Pipe()
            try? p.run()
            p.waitUntilExit()
            let granted = p.terminationStatus == 0
            // Keep stored flag in sync with actual result.
            DispatchQueue.main.async {
                automationManuallyConfirmed = granted
                completion(granted)
            }
        }
    }

    static func requestAutomationPermission() {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments     = ["-e", "tell application \"System Events\" to return name of first process"]
            p.standardOutput = Pipe()
            p.standardError  = Pipe()
            try? p.run()
            p.waitUntilExit()
        }
        openAutomationSettings()
    }

    static func openAutomationSettings() {
        openPrivacyPane("Privacy_Automation")
    }

    // MARK: - System Settings deep-link

    static func openPrivacyPane(_ pane: String) {
        if #available(macOS 13, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(pane)")!
            if NSWorkspace.shared.open(url) { return }
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }

    static func openPrivacyAndSecurity() {
        if #available(macOS 13, *) {
            let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity")!
            if NSWorkspace.shared.open(url) { return }
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Restart

    static func restartATLAS() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
