import Foundation
import AppKit

// Dedicated engine for Waves Audio plugin installations (V16 and later).
//
// Install order (fixed — always in this sequence):
//   1. Detect existing Waves files → uninstall completely
//   2. Install Waves Central from the DMG provided in the source folder
//   3. Close any open DAW (auto-save first)
//   4. Handle all macOS dialogs: Gatekeeper, EULA, InstallHelper password
//   5. Navigate Waves Central → Offline Installer → open .cen bundle
//   6. Select all plugins → Install (handle permission popups, NEVER restart)
//   7. Close Waves Central
//   8. Apply Waves Ultimate patch DMG
//   9. Run Waves AU Reg Utility 16 from /Applications/Waves

enum WavesInstallEngine {

    // MARK: - Detection

    // Returns true when the dropped content looks like a Waves install package.
    // Scans the directory directly so .dmg and .cen files are not missed
    // (the caller's installable-extensions filter strips those before passing files in).
    static func isWavesContent(directory: String, files: [URL]) -> Bool {
        let dirLow = URL(fileURLWithPath: directory).lastPathComponent.lowercased()

        // Collect all filenames in the directory (recursive, shallow enough)
        var allNames: [String] = files.map { $0.lastPathComponent.lowercased() }
        if let enumerator = FileManager.default.enumerator(atPath: directory) {
            for case let path as String in enumerator {
                allNames.append(URL(fileURLWithPath: path).lastPathComponent.lowercased())
            }
        }

        var signals = 0
        if allNames.contains(where: { $0.contains("waves_central") || $0.contains("waves central") || $0.contains("install_waves") }) { signals += 1 }
        if allNames.contains(where: { $0.hasSuffix(".cen") })                                                                          { signals += 1 }
        if allNames.contains(where: { $0.contains("waves-ultimate-patch") || $0.contains("wavesultimate") || $0.contains("waves ultimate") }) { signals += 1 }
        if allNames.contains(where: { $0.contains("waveshell") })                                                                      { signals += 1 }
        if dirLow.contains("waves") && dirLow != "waves"                                                                               { signals += 1 }
        return signals >= 2
    }

    // Returns true if any Waves installation already exists on this Mac.
    static func existingWavesDetected() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: "/Applications/Waves") ||
               fm.fileExists(atPath: "/Users/Shared/Waves")
    }

    // MARK: - Main entry point

    // Returns (success, failureReason)
    static func install(
        sourceDir: String,
        adminPassword: String,
        logger: Logger
    ) async -> (Bool, String?) {
        await log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", logger)
        await log("WAVES INSTALL ENGINE — starting", logger)
        await log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", logger)

        // ── Step 1: Uninstall existing Waves ─────────────────────────────────
        if existingWavesDetected() {
            await log("WAVES: Existing installation detected — cleaning up first…", logger)
            await uninstall(adminPassword: adminPassword, logger: logger)
        } else {
            await log("WAVES: No existing Waves installation found.", logger)
        }

        // ── Step 2: Find Waves Central DMG ───────────────────────────────────
        guard let centralDMG = findFile(ext: "dmg", nameHint: "waves_central", in: sourceDir)
                            ?? findFile(ext: "dmg", nameHint: "install_waves", in: sourceDir) else {
            await log("WAVES: ✗ Could not find Install_Waves_Central.dmg — aborting.", logger)
            return (false, "Install_Waves_Central.dmg not found in provided files.")
        }
        await log("WAVES: Found installer DMG: \(centralDMG.lastPathComponent)", logger)

        // ── Step 3: Close any open DAW ────────────────────────────────────────
        await closeDawsIfOpen(logger: logger)

        // ── Step 4: Install Waves Central ─────────────────────────────────────
        let ok = await installWavesCentral(dmg: centralDMG, adminPassword: adminPassword, logger: logger)
        guard ok else {
            await log("WAVES: ✗ Waves Central installation failed — aborting.", logger)
            return (false, "Waves Central installer did not complete successfully.")
        }

        // ── Step 5: Launch Waves Central app ──────────────────────────────────
        await log("WAVES: Launching Waves Central…", logger)
        let wavesCentralURL = URL(fileURLWithPath: "/Applications/Waves Central.app")
        guard (await MacUIAutomator.launch(url: wavesCentralURL, timeout: 40)) != nil else {
            await log("WAVES: ✗ Could not launch Waves Central — aborting.", logger)
            return (false, "Waves Central.app could not be launched after install.")
        }
        await log("WAVES: Waves Central is running.", logger)
        try? await Task.sleep(nanoseconds: 4_000_000_000)

        // ── Step 6: Click "Offline Installer" ─────────────────────────────────
        await log("WAVES: Navigating to Offline Installer…", logger)
        await clickOfflineInstaller(logger: logger)
        try? await Task.sleep(nanoseconds: 2_500_000_000)

        // ── Step 7: Open the .cen bundle ──────────────────────────────────────
        guard let cenFile = findFile(ext: "cen", nameHint: nil, in: sourceDir) else {
            await log("WAVES: ✗ Could not find .cen plugin bundle — aborting.", logger)
            return (false, "No .cen plugin bundle found in provided files.")
        }
        await log("WAVES: Opening plugin bundle: \(cenFile.lastPathComponent)", logger)
        NSWorkspace.shared.open(cenFile)
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        // ── Step 8: Select all plugins and install ─────────────────────────────
        await log("WAVES: Selecting all plugins and starting install…", logger)
        await selectAllAndInstall(adminPassword: adminPassword, logger: logger)

        // Poll until Waves Central exits (install complete)
        await log("WAVES: Waiting for plugin install to complete (may take 10–20 min)…", logger)
        await waitForAppToQuit(named: "Waves Central", timeout: 2400, logger: logger)

        // ── Step 9: Close Waves Central ───────────────────────────────────────
        await MacUIAutomator.quitApp(named: "Waves Central", timeout: 15)
        await log("WAVES: Waves Central closed.", logger)
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // ── Step 10: Apply patch ───────────────────────────────────────────────
        await applyPatch(sourceDir: sourceDir, adminPassword: adminPassword, logger: logger)

        // ── Step 11: AU registration ───────────────────────────────────────────
        await runAURegUtility(logger: logger)

        await log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", logger)
        await log("WAVES: ✓ Installation complete.", logger)
        await log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", logger)
        return (true, nil)
    }

    // MARK: - Uninstall

    static func uninstall(adminPassword: String, logger: Logger) async {
        await log("WAVES: Removing Waves files…", logger)
        let home = NSHomeDirectory()

        // User-level paths — trash without sudo
        let userPaths: [String] = [
            "/Applications/Waves",
            "/Users/Shared/Waves",
            "\(home)/Documents/Waves",
            "\(home)/Library/Application Support/Waves",
            "\(home)/Library/Application Support/Waves Central",
        ]
        let fm = FileManager.default
        for path in userPaths {
            guard fm.fileExists(atPath: path) else { continue }
            do {
                try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
                await log("WAVES: Trashed \(path)", logger)
            } catch {
                let r = runSudo("rm -rf \"\(path)\"", password: adminPassword)
                await log(r.success ? "WAVES: Removed \(path)" : "WAVES: Warn — \(path): \(r.output.prefix(60))", logger)
            }
        }

        // ~/Library/Preferences — remove Waves prefs files
        let prefsDir = "\(home)/Library/Preferences"
        if let prefs = try? fm.contentsOfDirectory(atPath: prefsDir) {
            for name in prefs where name.lowercased().contains("waves") {
                try? fm.trashItem(at: URL(fileURLWithPath: "\(prefsDir)/\(name)"), resultingItemURL: nil)
                await log("WAVES: Removed pref \(name)", logger)
            }
        }

        // System-level plugin paths — need sudo
        let pluginBase = "/Library/Audio/Plug-Ins"
        for sub in ["Components", "VST", "VST3"] {
            let dir = "\(pluginBase)/\(sub)"
            guard fm.fileExists(atPath: dir) else { continue }
            // Find and remove WaveShell files
            let r = runSudo("find '\(dir)' -maxdepth 1 \\( -iname '*waveshell*' -o -iname '*waves*' \\) -exec rm -rf {} + 2>/dev/null; true", password: adminPassword)
            await log(r.success ? "WAVES: Cleaned \(sub)" : "WAVES: \(sub): \(r.output.prefix(60))", logger)
        }

        // WPAPI folder
        let wpapi = "\(pluginBase)/WPAPI"
        if fm.fileExists(atPath: wpapi) {
            let r = runSudo("rm -rf '\(wpapi)'", password: adminPassword)
            await log(r.success ? "WAVES: Removed WPAPI" : "WAVES: WPAPI: \(r.output.prefix(60))", logger)
        }

        await log("WAVES: Uninstall complete.", logger)
    }

    // MARK: - Install Waves Central

    private static func installWavesCentral(dmg: URL, adminPassword: String, logger: Logger) async -> Bool {
        // Mount DMG
        await log("WAVES: Mounting Waves Central DMG…", logger)
        let mountResult = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
            arguments: ["attach", dmg.path, "-nobrowse", "-mountrandom", "/tmp"])
        guard mountResult.success else {
            await log("WAVES: Mount failed — \(mountResult.output.prefix(80))", logger)
            return false
        }
        let mountPoint = parseMountPoint(mountResult.output)
        guard !mountPoint.isEmpty else {
            await log("WAVES: Could not determine mount point.", logger)
            return false
        }
        await log("WAVES: Mounted at \(mountPoint)", logger)

        defer {
            _ = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
                                               arguments: ["detach", mountPoint, "-force", "-quiet"])
        }

        // Find .app in DMG
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: mountPoint),
              let appName = items.first(where: { $0.hasSuffix(".app") }) else {
            await log("WAVES: No .app found in Waves Central DMG.", logger)
            return false
        }
        let appURL = URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)

        // Remove quarantine
        _ = runSudo("xattr -rd com.apple.quarantine '\(appURL.path)' 2>/dev/null; true", password: adminPassword)

        // Launch installer
        await log("WAVES: Launching \(appName)…", logger)
        guard (await MacUIAutomator.launch(url: appURL, timeout: 25)) != nil else {
            await log("WAVES: Could not launch installer.", logger)
            return false
        }
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Handle Gatekeeper "open this app from internet" dialog
        await handleGatekeeperDialog(logger: logger)
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        // Handle Waves EULA (check checkbox + "I Agree")
        await handleWavesEULA(logger: logger)
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Handle InstallHelperApplication password prompt
        await handleInstallHelperPrompt(adminPassword: adminPassword, logger: logger)
        try? await Task.sleep(nanoseconds: 5_000_000_000)

        // Wait for installer to finish
        await waitForAppToQuit(named: appName.replacingOccurrences(of: ".app", with: ""), timeout: 120, logger: logger)
        await log("WAVES: Waves Central installer finished.", logger)
        return true
    }

    // MARK: - Dialog handlers

    private static func handleGatekeeperDialog(logger: Logger) async {
        let script = """
        tell application "System Events"
            repeat 8 times
                try
                    -- Standard Gatekeeper sheet
                    if exists button "Open" of sheet 1 of window 1 of process "Finder" then
                        click button "Open" of sheet 1 of window 1 of process "Finder"
                        return
                    end if
                end try
                try
                    set allProcs to every process
                    repeat with p in allProcs
                        try
                            if exists button "Open" of window 1 of p then
                                click button "Open" of window 1 of p
                                return
                            end if
                        end try
                    end repeat
                end try
                delay 1
            end repeat
        end tell
        """
        runAppleScript(script)
        await log("WAVES: Handled Gatekeeper dialog.", logger)
    }

    private static func handleWavesEULA(logger: Logger) async {
        let script = """
        tell application "System Events"
            repeat 10 times
                set allProcs to every process whose name contains "Waves"
                repeat with p in allProcs
                    try
                        -- Check any unchecked EULA checkbox
                        repeat with cb in (every checkbox of window 1 of p)
                            if value of cb is 0 then click cb
                        end repeat
                        delay 0.5
                        -- Click I Agree / Accept / Agree
                        repeat with b in (every button of window 1 of p)
                            set n to name of b
                            if n contains "Agree" or n contains "Accept" or n contains "agree" then
                                click b
                                return
                            end if
                        end repeat
                    end try
                end repeat
                delay 1
            end repeat
        end tell
        """
        runAppleScript(script)
        await log("WAVES: Handled EULA agreement.", logger)
    }

    private static func handleInstallHelperPrompt(adminPassword: String, logger: Logger) async {
        let escaped = adminPassword.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            repeat 12 times
                set allProcs to every process
                repeat with p in allProcs
                    try
                        repeat with w in (every window of p)
                            set wName to name of w
                            if wName contains "Install" or wName contains "Helper" or wName contains "Administrator" or wName contains "Password" then
                                -- Type password into any focused or visible text field
                                repeat with tf in (every text field of w)
                                    try
                                        set value of tf to "\(escaped)"
                                    end try
                                end repeat
                                delay 0.4
                                repeat with b in (every button of w)
                                    if name of b is "OK" or name of b contains "Install" then
                                        click b
                                        return
                                    end if
                                end repeat
                            end if
                        end repeat
                    end try
                end repeat
                delay 1
            end repeat
        end tell
        """
        runAppleScript(script)
        await log("WAVES: Handled InstallHelper password prompt.", logger)
    }

    private static func clickOfflineInstaller(logger: Logger) async {
        // Waves Central uses a custom UI — try button labels and static text
        let script = """
        tell application "System Events"
            repeat 20 times
                if exists process "Waves Central" then
                    tell process "Waves Central"
                        try
                            repeat with b in (every button of window 1)
                                if name of b contains "Offline" then
                                    click b
                                    return
                                end if
                            end repeat
                            -- Try clicking any UI element containing "Offline"
                            repeat with e in (every UI element of window 1)
                                try
                                    if value of e contains "Offline" or description of e contains "Offline" or help of e contains "Offline" then
                                        click e
                                        return
                                    end if
                                end try
                            end repeat
                        end try
                    end tell
                end if
                delay 1.5
            end repeat
        end tell
        """
        runAppleScript(script)
        await log("WAVES: Clicked Offline Installer.", logger)
    }

    private static func selectAllAndInstall(adminPassword: String, logger: Logger) async {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        let script = """
        tell application "System Events"
            if exists process "Waves Central" then
                tell process "Waves Central"
                    -- Try "Select All" button
                    try
                        repeat with b in (every button of window 1)
                            if name of b contains "Select All" or name of b contains "All" then
                                click b
                                delay 1
                                exit repeat
                            end if
                        end repeat
                    end try
                    -- Try "Install" / "Install All" button
                    try
                        repeat with b in (every button of window 1)
                            set n to name of b
                            if n is "Install" or n contains "Install All" or n contains "Install Plugins" then
                                click b
                                return
                            end if
                        end repeat
                    end try
                end tell
            end if
        end tell
        """
        runAppleScript(script)
        await log("WAVES: Started plugin install.", logger)

        // Spawn a background watcher that handles permission popups and blocks restarts
        Task.detached {
            await watchForPopupsAndBlockRestarts(adminPassword: adminPassword, logger: logger)
        }
    }

    // Runs for up to 40 minutes, handling system permission dialogs and
    // dismissing any restart prompt with "Later" / "Cancel" — never restarts.
    private static func watchForPopupsAndBlockRestarts(adminPassword: String, logger: Logger) async {
        let escaped = adminPassword.replacingOccurrences(of: "\\", with: "\\\\")
                                   .replacingOccurrences(of: "\"", with: "\\\"")
        for _ in 0..<480 { // 480 × 5s = 40 min max
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            let script = """
            tell application "System Events"
                set allProcs to every process
                repeat with p in allProcs
                    try
                        repeat with w in (every window of p)
                            try
                                repeat with b in (every button of w)
                                    set n to name of b
                                    -- NEVER click Restart — always defer
                                    if n contains "Restart" or n contains "Reboot" then
                                        repeat with cb in (every button of w)
                                            set cn to name of cb
                                            if cn contains "Later" or cn contains "Not Now" or cn contains "Cancel" or cn contains "Skip" then
                                                click cb
                                            end if
                                        end repeat
                                    end if
                                    -- Allow/OK security prompts
                                    if n is "OK" or n is "Allow" or n contains "Continue" or n contains "Install" then
                                        -- Skip if it's a "Cancel" lookalike
                                        if n does not contain "Cancel" then
                                            click b
                                        end if
                                    end if
                                end repeat
                                -- Handle password fields in any dialog
                                repeat with tf in (every text field of w)
                                    try
                                        if focused of tf and value of tf is "" then
                                            set value of tf to "\(escaped)"
                                        end if
                                    end try
                                end repeat
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            """
            runAppleScript(script)

            // Stop watching if Waves Central has exited
            let isRunning = await MainActor.run {
                NSWorkspace.shared.runningApplications.contains(where: {
                    $0.localizedName?.contains("Waves Central") == true
                })
            }
            if !isRunning { break }
        }
        await log("WAVES: Popup watcher finished.", logger)
    }

    // MARK: - Patch

    private static func applyPatch(sourceDir: String, adminPassword: String, logger: Logger) async {
        await log("WAVES: Looking for Waves Ultimate patch DMG…", logger)
        guard let patchDMG = findFile(ext: "dmg", nameHint: "waves-ultimate-patch", in: sourceDir)
                          ?? findFile(ext: "dmg", nameHint: "waves_ultimate_patch", in: sourceDir)
                          ?? findFile(ext: "dmg", nameHint: "wavesultimate", in: sourceDir) else {
            await log("WAVES: Patch DMG not found — skipping patch step.", logger)
            return
        }
        await log("WAVES: Found patch: \(patchDMG.lastPathComponent)", logger)

        let mountResult = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
            arguments: ["attach", patchDMG.path, "-nobrowse", "-mountrandom", "/tmp"])
        guard mountResult.success else {
            await log("WAVES: Could not mount patch DMG.", logger)
            return
        }
        let mountPoint = parseMountPoint(mountResult.output)
        defer {
            _ = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
                                               arguments: ["detach", mountPoint, "-force", "-quiet"])
        }

        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: mountPoint)) ?? []

        if let appName = items.first(where: { $0.hasSuffix(".app") }) {
            let appURL = URL(fileURLWithPath: mountPoint).appendingPathComponent(appName)
            _ = runSudo("xattr -rd com.apple.quarantine '\(appURL.path)' 2>/dev/null; true", password: adminPassword)
            await log("WAVES: Launching patch: \(appName)…", logger)
            if (await MacUIAutomator.launch(url: appURL, timeout: 20)) != nil {
                await waitForAppToQuit(named: appName.replacingOccurrences(of: ".app", with: ""), timeout: 300, logger: logger)
                await log("WAVES: Patch applied.", logger)
            }
        } else if let pkgName = items.first(where: { $0.hasSuffix(".pkg") }) {
            let r = await InstallEngine.runProcessWithPassword(
                password: adminPassword,
                arguments: ["installer", "-pkg", "\(mountPoint)/\(pkgName)", "-target", "/"]
            )
            await log(r.success ? "WAVES: Patch PKG installed." : "WAVES: Patch PKG failed: \(r.output.prefix(80))", logger)
        } else {
            await log("WAVES: No installable file found in patch DMG.", logger)
        }
    }

    // MARK: - AU Registration

    private static func runAURegUtility(logger: Logger) async {
        await log("WAVES: Looking for Waves AU Reg Utility in /Applications/Waves…", logger)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: "/Applications/Waves") else {
            await log("WAVES: /Applications/Waves not found — skipping AU registration.", logger)
            return
        }
        var utilURL: URL? = nil
        for case let path as String in enumerator {
            let name = path.lowercased()
            if (name.contains("au reg") || name.contains("au_reg") || name.contains("aureg"))
                && path.hasSuffix(".app") {
                utilURL = URL(fileURLWithPath: "/Applications/Waves").appendingPathComponent(path)
                break
            }
        }
        guard let url = utilURL else {
            await log("WAVES: AU Reg Utility not found — skipping.", logger)
            return
        }
        await log("WAVES: Running \(url.lastPathComponent)…", logger)
        if (await MacUIAutomator.launch(url: url, timeout: 20)) != nil {
            await waitForAppToQuit(named: "Waves AU Reg Utility", timeout: 120, logger: logger)
            await log("WAVES: AU registration complete.", logger)
        } else {
            await log("WAVES: Could not launch AU Reg Utility.", logger)
        }
    }

    // MARK: - DAW handling

    private static func closeDawsIfOpen(logger: Logger) async {
        let dawNames = [
            "Pro Tools", "Logic Pro", "Ableton Live", "Live", "REAPER",
            "Cubase", "Nuendo", "Studio One", "FL Studio", "Digital Performer", "GarageBand"
        ]
        let running = await MainActor.run { NSWorkspace.shared.runningApplications }
        for daw in dawNames {
            guard let app = running.first(where: { $0.localizedName?.contains(daw) == true }) else { continue }
            let name = app.localizedName ?? daw
            await log("WAVES: Detected open DAW: \(name) — auto-saving and closing…", logger)
            // Try AppleScript save first
            let saveScript = "tell application \"\(name)\" to try\nsave\nend try"
            runAppleScript(saveScript)
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { app.terminate() }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await log("WAVES: Closed \(name).", logger)
        }
    }

    // MARK: - Helpers

    private static func findFile(ext: String, nameHint: String?, in directory: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return nil }
        for case let path as String in enumerator {
            let url     = URL(fileURLWithPath: directory).appendingPathComponent(path)
            let nameLow = url.lastPathComponent.lowercased()
            guard url.pathExtension.lowercased() == ext.lowercased() else { continue }
            if let hint = nameHint {
                if nameLow.contains(hint.lowercased()) { return url }
            } else {
                return url
            }
        }
        return nil
    }

    @discardableResult
    private static func waitForAppToQuit(named name: String, timeout: TimeInterval, logger: Logger) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        var reported = false
        while Date() < deadline {
            let isRunning = await MainActor.run {
                NSWorkspace.shared.runningApplications.contains(where: {
                    $0.localizedName?.contains(name) == true
                })
            }
            if !isRunning { return true }
            if !reported {
                await log("WAVES: Waiting for \(name) to finish…", logger)
                reported = true
            }
            try? await Task.sleep(nanoseconds: 15_000_000_000) // check every 15s
        }
        return false
    }

    private static func parseMountPoint(_ hdiOutput: String) -> String {
        let lines = hdiOutput.components(separatedBy: .newlines)
        return lines.last(where: { $0.contains("/tmp/") || $0.contains("/Volumes/") })?
            .components(separatedBy: "\t").last?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return result?.stringValue ?? (error?["NSAppleScriptErrorMessage"] as? String ?? "")
    }

    @discardableResult
    private static func runSudo(_ command: String, password: String) -> (success: Bool, output: String) {
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let full    = "echo '\(escaped)' | sudo -S sh -c '\(command.replacingOccurrences(of: "'", with: "'\\''"))'"
        return InstallEngine.runShell(full)
    }

    private static func log(_ message: String, _ logger: Logger) async {
        await MainActor.run { logger.log(message) }
    }
}
