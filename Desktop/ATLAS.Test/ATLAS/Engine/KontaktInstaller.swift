import Foundation
import AppKit

// MARK: - Kontakt Library Installer
// Automates "Add Library for macOS v4.app" (bundled in ATLAS resources)
// to register a Kontakt sample library via Native Access.

struct KontaktInstaller {

    // MARK: - Tool location

    static var toolURL: URL? {
        // 1. SPM resource bundle (primary — works in both debug and release .app builds)
        if let bundled = Bundle.atlasResources.url(forResource: "Add Library for macOS v4", withExtension: "app"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        // 2. Fall back to known user locations
        let home = FileManager.default.homeDirectoryForCurrentUser
        let fallbacks: [URL] = [
            home.appendingPathComponent("Desktop/Add Library for macOS v4.app"),
            URL(fileURLWithPath: "/Applications/Add Library for macOS v4.app"),
            home.appendingPathComponent("Applications/Add Library for macOS v4.app"),
        ]
        return fallbacks.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Main install entry point

    static func install(
        libraryFolder: URL,
        logger: Logger,
        progress: @escaping @Sendable (Double, String) async -> Void
    ) async -> InstallResult {

        await logger.log("Kontakt library: \(libraryFolder.lastPathComponent)")

        // Verify .ncint exists inside the folder
        guard InstallerClassifier.findNcintFile(in: libraryFolder) != nil else {
            await logger.log("✗ No .ncint file found in folder — not a Kontakt library")
            return .failure(reason: "No .ncint file found inside the selected folder.")
        }

        guard let tool = toolURL else {
            await logger.log("✗ 'Add Library for macOS v4' tool not found.")
            return .failure(
                reason: "Add Library tool not found. Please place 'Add Library for macOS v4.app' in your Applications folder or Desktop."
            )
        }

        await logger.log("Using tool: \(tool.path)")
        await progress(0.05, "Preparing...")

        // Strip quarantine so macOS doesn't block the unsigned applet
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-cr", tool.path]
        xattr.standardOutput = Pipe()
        xattr.standardError  = Pipe()
        try? xattr.run(); xattr.waitUntilExit()
        await logger.log("Quarantine stripped from tool")

        await progress(0.12, "Launching Add Library tool...")

        // Launch the AppleScript applet
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", tool.path]
        open.standardOutput = Pipe()
        open.standardError  = Pipe()
        try? open.run(); open.waitUntilExit()

        await logger.log("Add Library tool launched — waiting for Native Access...")
        await progress(0.20, "Waiting for Native Access...")

        // Run the GUI automation
        let script = buildAutomationScript(libraryPath: libraryFolder.path)
        let outcome = await runScript(script, logger: logger, progress: progress)

        switch outcome {
        case "done", "chosen":
            await logger.log("✓ Kontakt library added successfully")
            return .success(appName: libraryFolder.lastPathComponent)
        case "timeout":
            await logger.log("⚠ Library may have been added (tool timed out waiting for confirmation)")
            return .success(appName: libraryFolder.lastPathComponent)
        default:
            await logger.log("✗ Could not automate Add Library tool: \(outcome)")
            return .failure(reason: "Automation error: \(outcome)")
        }
    }

    // MARK: - AppleScript automation

    private static func buildAutomationScript(libraryPath: String) -> String {
        // Escape the path for AppleScript string embedding
        let escaped = libraryPath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        -- Wait for Native Access to be running (launched by the applet)
        set nativeAccessName to ""
        set elapsed to 0
        repeat
            delay 0.5
            set elapsed to elapsed + 0.5
            if elapsed > 20 then
                return "timeout_launch"
            end if
            tell application "System Events"
                repeat with proc in every process
                    set pn to name of proc
                    if pn contains "Native Access" then
                        set nativeAccessName to pn
                        exit repeat
                    end if
                end repeat
            end tell
            if nativeAccessName is not "" then exit repeat
        end repeat

        delay 2

        tell application "System Events"
            tell process nativeAccessName
                set frontmost to true
                delay 1

                -- Some versions present an open panel right away;
                -- others require clicking "Add Library" first.
                set elapsed to 0
                repeat
                    delay 0.5
                    set elapsed to elapsed + 0.5
                    if elapsed > 25 then return "timeout_panel"

                    -- Try to find an open panel (sheet or floating panel with Choose button)
                    set foundPanel to false
                    try
                        set wins to every window
                        repeat with w in wins
                            try
                                -- Sheet case
                                set sh to sheet 1 of w
                                set foundPanel to true
                                exit repeat
                            end try
                            try
                                -- Direct panel case — look for Choose/Open button
                                if exists (button "Choose" of w) then
                                    set foundPanel to true
                                    exit repeat
                                end if
                            end try
                        end repeat
                    end try

                    if foundPanel then
                        exit repeat
                    end if

                    -- Click any "Add Library" / "Add" button in the main window
                    try
                        repeat with btn in buttons of window 1
                            set bTitle to name of btn
                            if bTitle is "Add Library" or bTitle is "Add" or bTitle is "Browse" then
                                click btn
                                delay 1
                                exit repeat
                            end if
                        end repeat
                    end try
                end repeat

                -- Now navigate to the library folder using Go to Folder (Cmd+Shift+G)
                keystroke "g" using {command down, shift down}
                delay 1

                -- Type the path into the Go to Folder field
                set the clipboard to "\(escaped)"
                keystroke "v" using {command down}
                delay 0.4
                keystroke return
                delay 0.8

                -- Click Choose / Open in the open panel
                set didChoose to false
                try
                    -- Try sheet first
                    repeat with w in every window
                        try
                            set sh to sheet 1 of w
                            repeat with btn in buttons of sh
                                set bTitle to name of btn
                                if bTitle is "Choose" or bTitle is "Open" or bTitle is "Select" then
                                    click btn
                                    set didChoose to true
                                    exit repeat
                                end if
                            end repeat
                        end try
                        if didChoose then exit repeat
                        -- Try direct window buttons
                        try
                            repeat with btn in buttons of w
                                set bTitle to name of btn
                                if bTitle is "Choose" or bTitle is "Open" then
                                    click btn
                                    set didChoose to true
                                    exit repeat
                                end if
                            end repeat
                        end try
                        if didChoose then exit repeat
                    end repeat
                end try

                -- Fallback: just press Return to confirm the panel
                if not didChoose then
                    keystroke return
                    delay 0.5
                end if

                -- Wait for Done / Next / Finish button (library being added)
                set elapsed to 0
                repeat
                    delay 1
                    set elapsed to elapsed + 1
                    if elapsed > 90 then return "timeout"
                    try
                        repeat with btn in buttons of window 1
                            set bTitle to name of btn
                            if bTitle is "Done" or bTitle is "Finish" or bTitle is "Next" or bTitle is "Close" then
                                click btn
                                delay 0.5
                                return "done"
                            end if
                        end repeat
                    end try
                end repeat

                return "done"
            end tell
        end tell
        """
    }

    // MARK: - Script runner

    private static func runScript(
        _ source: String,
        logger: Logger,
        progress: @escaping @Sendable (Double, String) async -> Void
    ) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Progress ticker while script runs
                let ticker = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
                var pct = 0.25
                ticker.schedule(deadline: .now() + 2, repeating: 3)
                ticker.setEventHandler {
                    pct = min(pct + 0.06, 0.90)
                    let snapshot = pct
                    Task { await progress(snapshot, "Adding library...") }
                }
                ticker.resume()

                var error: NSDictionary?
                let script = NSAppleScript(source: source)
                let result = script?.executeAndReturnError(&error)

                ticker.cancel()

                if let err = error {
                    let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
                    Task { await logger.log("Automation error: \(msg)") }
                    continuation.resume(returning: "error: \(msg)")
                    return
                }

                let outcome = result?.stringValue ?? "done"
                Task { await progress(0.95, "Finishing...") }
                continuation.resume(returning: outcome)
            }
        }
    }
}
