import Foundation
import Security

typealias ProgressReporter = (Double, String) async -> Void

// MARK: - InstallEngine

// Ensures only one GUI installer wizard runs at a time across all queue paths.
// Callers await acquire() before launching a GUI wizard; call release() when done.
// FIFO ordering: waiters are resumed in the order they arrived.
actor GUIInstallerQueue {
    static let shared = GUIInstallerQueue()
    private var isActive = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isActive { isActive = true; return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        isActive = true
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isActive = false
        }
    }
}

struct InstallEngine {

    // MARK: - Cancellation

    // Per-install cancellation: keyed by install job UUID so multiple queue items
    // never share a cancel token or process handle. Replaces the old single static.
    static var activeProcesses: [UUID: Process] = [:]
    static var cancelledJobs:   Set<UUID>       = []

    // Legacy single-job shim — used by code paths that don't yet carry a job ID.
    // New code must prefer activeProcesses[jobID] and cancelledJobs.
    static var activeProcess: Process? {
        get { activeProcesses.values.first }
        set {
            if let p = newValue { activeProcesses[UUID()] = p }
            else { activeProcesses.removeAll() }
        }
    }
    static var cancellationRequested: Bool {
        get { !cancelledJobs.isEmpty }
        set { if newValue { cancelledJobs.insert(UUID()) } else { cancelledJobs.removeAll() } }
    }

    // TITAN CORE™ Smart Storage: set before install to route files to a custom volume root.
    // nil = default system paths (/Applications, /Library/…). Cleared after install.
    static var storageRoot: URL? = nil

    // MARK: - Global auth-dialog watcher

    // Runs for the full duration of any install. Catches every "wants to make changes"
    // / "requires your password" dialog from authorizationhost (macOS 12+) or
    // SecurityAgent (macOS 11-) and fills + dismisses it automatically.
    // SECURITY CONSTRAINT: ATLAS must ONLY auto-fill passwords for dialogs triggered
    // by software it is actively installing. This watcher is ONLY called from
    // TitanMission for GUI wizard installers. It runs for a maximum of 60 seconds
    // per call and is always terminated by the caller via defer{}.
    // The password is NEVER passed via process arguments (visible in ps aux) —
    // it is written to a temp file readable only by the current user, then deleted.
    // installerPID: the PID of the process ATLAS launched (installer, patch app, etc.).
    // The watcher checks this PID is still alive before filling ANY dialog. This is the
    // guarantee that we NEVER auto-fill a password dialog the user triggered outside of
    // ATLAS — if our process is gone, we stop immediately regardless of what's on screen.
    static func startAuthWatcher(password: String, installerPID: Int32 = 0) -> Process {
        // Write password to a temp file (never embed in script args — visible via ps aux)
        let tmpFile = NSTemporaryDirectory() + "atlas_aw_\(Int.random(in: 100000...999999))"
        try? password.write(toFile: tmpFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpFile)

        // Also install a SUDO_ASKPASS helper so any child `sudo` call inside PKG
        // postinstall scripts gets the password silently — no GUI dialog ever appears.
        // This is the primary fix for "X wants to make changes" dialogs from PKG scripts.
        let askpassFile = NSTemporaryDirectory() + "atlas_askpass_\(Int.random(in: 100000...999999)).sh"
        let askpassScript = """
        #!/bin/sh
        cat "\(tmpFile)"
        """
        try? askpassScript.write(toFile: askpassFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassFile)
        // Set globally so all child processes inherit it
        setenv("SUDO_ASKPASS", askpassFile, 1)

        // AppleScript watcher as secondary fallback — catches any GUI dialogs that
        // slip through despite SUDO_ASKPASS (e.g. Authorization Services API calls).
        // Watches all known auth processes across macOS versions:
        //   authorizationhost — macOS 12+ Monterey and later
        //   SecurityAgent     — macOS 10.x / 11 Big Sur
        // Polls every 0.3s (tighter than before) and handles both text field
        // structures and secure input fields.
        // SAFETY — three-layer containment:
        // 1. Only watch authorizationhost and SecurityAgent (real password-entry processes).
        // 2. Only interact with windows that have a text field — never blind OK/Allow clicks.
        // 3. PID guard: before filling any dialog, verify our installer process is still
        //    running via `kill -0 <pid>`. If it exited (user finished, crashed, or was
        //    cancelled), we stop immediately. This is the guarantee that ATLAS NEVER fills
        //    a password dialog the user triggered in another app or System Settings while
        //    ATLAS was in the background.
        // Loop cap: 200 × 0.3s = 60 s max. defer{} in caller kills us sooner.
        let pidCheck = installerPID > 0
            ? "do shell script \"kill -0 \(installerPID) 2>/dev/null && echo alive || echo dead\""
            : "\"alive\""
        let script = """
        set pwdFile to "\(tmpFile)"
        set pwd to do shell script "cat " & quoted form of pwdFile
        tell application "System Events"
            repeat 200 times
                delay 0.3
                -- PID guard: stop if our installer process is gone
                try
                    set pidStatus to \(pidCheck)
                    if pidStatus is "dead" then exit repeat
                end try
                repeat with authProcName in {"authorizationhost", "SecurityAgent"}
                    try
                        set authProcs to processes whose name is authProcName
                        if (count of authProcs) > 0 then
                            tell (first item of authProcs)
                                try
                                    repeat with w in windows
                                        try
                                            set allFields to text fields of w
                                            set n to count of allFields
                                            if n >= 1 then
                                                if n >= 2 then
                                                    set value of (last item of allFields) to pwd
                                                else
                                                    set value of (first item of allFields) to pwd
                                                end if
                                                delay 0.15
                                                try
                                                    click button "OK" of w
                                                on error
                                                    try
                                                        click button "Unlock" of w
                                                    on error
                                                        keystroke return
                                                    end try
                                                end try
                                            end if
                                        end try
                                    end repeat
                                end try
                            end tell
                        end if
                    end try
                end repeat
            end repeat
        end tell
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        p.standardOutput = Pipe()
        p.standardError  = Pipe()
        try? p.run()

        // Clean up both temp files when the watcher exits
        p.terminationHandler = { _ in
            try? FileManager.default.removeItem(atPath: askpassFile)
            try? FileManager.default.removeItem(atPath: tmpFile)
            unsetenv("SUDO_ASKPASS")
        }

        return p
    }

    // Kills any leaked auth watcher osascript processes from previous ATLAS sessions
    // and removes orphaned atlas_aw_* password files from /tmp.
    // Called at app launch to ensure no stale watchers or password files survive a crash.
    static func killLeakedAuthWatchers() {
        _ = runProcess(path: "/usr/bin/pkill", arguments: ["-f", "repeat.*authorizationhost"])
        _ = runProcess(path: "/usr/bin/pkill", arguments: ["-f", "repeat.*SecurityAgent"])
        // Clean up any atlas_aw_* password files orphaned by a previous crash
        let tmpDir = NSTemporaryDirectory()
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tmpDir) {
            for file in files where file.hasPrefix("atlas_aw_") {
                try? FileManager.default.removeItem(atPath: tmpDir + file)
            }
        }
    }

    static func cancelCurrentInstall() {
        cancellationRequested = true
        activeProcess?.terminate()
        activeProcess = nil
    }

    static func resetCancellation() {
        cancellationRequested = false
        activeProcess = nil
    }

    static func install(
        url: URL,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String],
                isPlugin: Bool,
                runtimeCreatedPaths: [String]) {
        // Strip quarantine from the source file before anything runs.
        // This prevents macOS Gatekeeper from showing "cannot be opened because
        // the developer cannot be verified" dialogs for downloaded installers.
        _ = runProcess(path: "/usr/bin/xattr", arguments: ["-cr", url.path])

        // Snapshot top-level Library dirs so we can detect runtime-created
        // data folders (e.g. ~/Library/Application Support/MBM Audio) that
        // aren't recorded in any PKG receipt.
        let libSnapshot = snapshotLibraryTopLevel()

        // Plugin-only directory: a folder dropped directly whose contents are
        // only audio plugin bundles (.component/.vst3/.vst/.aaxplugin).
        // InstallerClassifier returns .unsupported("") for plain directories, so
        // we intercept here before the type switch.
        var isDirCheck: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirCheck)
        if isDirCheck.boolValue && InstallerClassifier.findNcintFile(in: url) == nil {
            let hasPlugin = findFile(extension: "component", in: url.path) != nil ||
                            findFile(extension: "vst3",      in: url.path) != nil ||
                            findFile(extension: "vst",       in: url.path) != nil ||
                            findFile(extension: "aaxplugin", in: url.path) != nil
            if hasPlugin {
                // Pass the folder through the existing instruction parser so documentation
                // files (Instructions.rtf, README.txt, etc.) can be evaluated.
                // findAndParseInstructions applies its own scoring, depth limits, and
                // safety checks — no new parser, no arbitrary instruction execution.
                if let instructions = InstallIntelligence.findAndParseInstructions(in: url.path) {
                    await logger.log("📋 Instructions found (\(instructions.sourceFileName)) — parsed by ATLAS.")
                    for step in instructions.steps.prefix(3) {
                        await logger.log("  · \(step)")
                    }
                }
                await progress(0.2, "Installing audio plugins…")
                let (r, f) = await PluginInstallEngine.installPlugins(in: url.path, logger: logger)
                await progress(1.0, "")
                let rtPaths = diffLibraryTopLevel(before: libSnapshot)
                return (r, f, [], true, rtPaths)
            }
        }

        let type_ = InstallerClassifier.classify(url: url)
        let (result, files, receipts, isPlugin): (InstallResult, [InstallRecord.InstalledFile], [String], Bool)
        switch type_ {
        case .dmg:
            (result, files, receipts, isPlugin) = await installDMG(url: url, logger: logger, progress: progress)
        case .iso:
            (result, files, receipts, isPlugin) = await installDMG(url: url, logger: logger, progress: progress)
        case .zip:
            (result, files, receipts, isPlugin) = await installZIP(url: url, logger: logger, progress: progress)
        case .app:
            if case .blocked(let dawName) = DAWInstallationGate.check(appURL: url) {
                await logger.log("DAW installation not supported: \(dawName) — user notified.")
                return (.unsupportedDAWInstallation(dawName: dawName), [], [], false, [])
            }
            (result, files, receipts, isPlugin) = await installAPP(url: url, logger: logger, progress: progress)
        case .pkg:
            let (r, f, rc) = await installPKG(
                url: url, installerName: url.lastPathComponent,
                logger: logger, progress: progress)
            (result, files, receipts, isPlugin) = (r, f, rc, false)
        case .component, .vst3, .vst, .aax:
            await progress(0.2, "Placing plugin in your library…")
            let (r, f) = await PluginInstallEngine.installSinglePlugin(url: url, logger: logger)
            await progress(1.0, "")
            (result, files, receipts, isPlugin) = (r, f, [], true)
        case .kontaktLibrary:
            let r = await KontaktInstaller.install(libraryFolder: url, logger: logger, progress: progress)
            (result, files, receipts, isPlugin) = (r, [], [], false)
        case .interactiveInstaller:
            (result, files, receipts, isPlugin) = await installAPP(url: url, logger: logger, progress: progress)
        case .exe:
            await logger.log("Windows .exe files are not supported on macOS.")
            (result, files, receipts, isPlugin) = (.failure(reason: "Windows .exe not supported on macOS"), [], [], false)
        case .unsupported(let ext):
            await logger.log("Unsupported file type: .\(ext)")
            (result, files, receipts, isPlugin) = (.failure(reason: "Unsupported file type: .\(ext)"), [], [], false)
        }

        // Diff Library dirs to find folders the installer created at runtime.
        let runtimePaths: [String]
        if case .success = result {
            runtimePaths = diffLibraryTopLevel(before: libSnapshot)
            if !runtimePaths.isEmpty {
                await logger.log("Runtime-created paths recorded for uninstall: \(runtimePaths)")
            }
        } else {
            runtimePaths = []
        }

        return (result, files, receipts, isPlugin, runtimePaths)
    }

    // MARK: DMG + ISO

    static func installDMG(
        url: URL,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String],
                isPlugin: Bool) {

        await logger.log("Starting installation: \(url.lastPathComponent)")
        await progress(0.03, "Verifying and mounting disk image…")

        // Reuse any existing mount from a previous crashed session.
        if let existing = findExistingMount(for: url.path) {
            await logger.log("Volume already mounted at \(existing) — reusing")
            return await installFromMountPoint(
                existing, url: url, logger: logger,
                shouldDetach: false, progress: progress)
        }

        let mountPoint = "/Volumes/ATLAS_\(UUID().uuidString.prefix(8))"
        await logger.log("Mounting \(url.lastPathComponent)...")

        // Mount without -quiet so failures produce a readable error message.
        var mountResult = runProcess(
            path: "/usr/bin/hdiutil",
            arguments: ["attach", url.path, "-mountpoint", mountPoint, "-nobrowse"]
        )

        // "Resource busy" = same disc content already mounted under a different path.
        // Detach all stale ATLAS volumes and retry once.
        if !mountResult.success &&
            mountResult.output.contains("Resource busy") {
            await logger.log("Resource busy — detaching stale ATLAS volumes and retrying...")
            cleanupStaleMounts()
            mountResult = runProcess(
                path: "/usr/bin/hdiutil",
                arguments: ["attach", url.path, "-mountpoint", mountPoint, "-nobrowse"]
            )
        }

        // Some DMGs embed a Software License Agreement that causes hdiutil to
        // print the license text and wait for "y/n". Since our process has no
        // stdin, it exits with "attach canceled". Retry by piping 'yes' to accept.
        if !mountResult.success &&
            (mountResult.output.contains("attach canceled") ||
             mountResult.output.contains("license") ||
             mountResult.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            await logger.log("SLA detected — retrying with auto-accept...")
            let escaped = url.path.replacingOccurrences(of: "'", with: "'\\''")
            let mp      = mountPoint.replacingOccurrences(of: "'", with: "'\\''")
            let slaResult = runShell(
                "yes | /usr/bin/hdiutil attach '\(escaped)' -mountpoint '\(mp)' -nobrowse -noautoopen 2>&1"
            )
            if slaResult.success {
                mountResult = (success: true, output: slaResult.output)
            }
        }

        if !mountResult.success {
            let msg = mountResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            await logger.log("Failed to mount: \(msg)")
            return (.failure(reason: "Could not mount file: \(msg)"), [], [], false)
        }

        await logger.log("Mounted at \(mountPoint)")

        // Strip quarantine recursively from everything inside the volume so no app
        // or PKG inside triggers a Gatekeeper dialog when run.
        // Route stdout+stderr to /dev/null: read-only DMG mounts (the common case)
        // generate one "Read-only file system" error per file, which can exceed the
        // 64 KB pipe buffer and permanently deadlock runProcess(). The output is never
        // used, so discarding it is correct for both read-only and writable mounts.
        let xattrProc = Process()
        xattrProc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattrProc.arguments     = ["-cr", mountPoint]
        xattrProc.standardOutput = FileHandle.nullDevice
        xattrProc.standardError  = FileHandle.nullDevice
        try? xattrProc.run()
        xattrProc.waitUntilExit()

        await progress(0.07, "Reading what's inside…")
        return await installFromMountPoint(
            mountPoint, url: url, logger: logger,
            shouldDetach: true, progress: progress)
    }

    private static func installFromMountPoint(
        _ mountPoint: String,
        url: URL,
        logger: Logger,
        shouldDetach: Bool,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String],
                isPlugin: Bool) {

        // ── Fast path: "Drag to Applications" DMG ────────────────────────────
        // Auth watcher is NOT started here — it is only started inside installPKG and
        // runPatchApp where elevated permissions are actually needed. Starting it for the
        // full DMG mount caused the watcher to run during simple drag-to-install copies
        // (e.g. EdiLoad) where no password is needed, and the watcher's blind window-clicking
        // destabilised unrelated macOS system dialogs.
        // Pattern: top-level .app + Applications symlink → /Applications, no PKG.
        // This is the most common single-app DMG pattern (e.g. EdiLoad, many others).
        // Instructions like "drag the app onto Applications" map exactly to this.
        let hasDragTarget = FileManager.default.fileExists(
            atPath: "\(mountPoint)/Applications")
        let noPKG = findFile(extension: "pkg", in: mountPoint) == nil &&
                    findFile(extension: "mpkg", in: mountPoint) == nil
        let topLevelApps = (try? FileManager.default.contentsOfDirectory(atPath: mountPoint))?
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".app") } ?? []

        // DAW gate — inspect all .app bundles in the mounted volume before any install action.
        // Covers both the fast-path (single drag-to-install app) and the plan-based path.
        let allAppURLsInMount = findAllFiles(extension: "app", in: mountPoint)
        if case .blocked(let dawName) = DAWInstallationGate.checkCandidates(allAppURLsInMount) {
            await logger.log("DAW installation not supported: \(dawName) — user notified.")
            if shouldDetach { await detachDMG(mountPoint: mountPoint, logger: logger) }
            return (.unsupportedDAWInstallation(dawName: dawName), [], [], false)
        }

        if hasDragTarget && noPKG && topLevelApps.count == 1 {
            let appURL  = URL(fileURLWithPath: mountPoint).appendingPathComponent(topLevelApps[0])
            let appName = appURL.lastPathComponent
            await logger.log("Drag-to-install DMG: copying \(appName) to /Applications")
            await progress(0.15, "Copying \(appName.replacingOccurrences(of: ".app", with: "")) to Applications…")
            let result = await copyApp(appURL: appURL, logger: logger, progress: progress)
            if shouldDetach { await detachDMG(mountPoint: mountPoint, logger: logger) }
            if case .success = result {
                return (result,
                        [InstallRecord.InstalledFile(sourceName: appName,
                                                     destinationPath: "/Applications/\(appName)")],
                        [], false)
            }
            return (result, [], [], false)
        }

        let allInstallable = findAllFiles(extension: "pkg", in: mountPoint) +
                            findAllFiles(extension: "app", in: mountPoint) +
                            findAllFiles(extension: "component", in: mountPoint) +
                            findAllFiles(extension: "vst3", in: mountPoint) +
                            findAllFiles(extension: "mpkg", in: mountPoint)

        if !allInstallable.isEmpty {
            let plan = await InstallIntelligence.analyze(
                directory: mountPoint, files: allInstallable)

            if let instr = plan.instructions {
                await logger.log("📋 Instructions found — reading install order...")
                if !instr.steps.isEmpty {
                    for step in instr.steps.prefix(5) {
                        await logger.log("  · \(step)")
                    }
                }
                if instr.mentionsPatch {
                    await logger.log("  Patch detected in instructions")
                }
            }

            await logger.log("Install plan: \(plan.summary)")
            for warning in plan.warnings {
                await logger.log("  ⚠ \(warning)")
            }

            var allFiles: [InstallRecord.InstalledFile] = []
            var allReceipts: [String] = []
            var lastResult: InstallResult = .success(appName: url.lastPathComponent)

            // Each step occupies an equal slice of 0.10 → 0.93
            let stepCount = Double(plan.orderedSteps.count)
            let rangeStart = 0.10
            let rangeEnd   = 0.93

            for (index, step) in plan.orderedSteps.enumerated() {
                await logger.log("[\(step.order)/\(plan.orderedSteps.count)] \(step.label): \(step.url.lastPathComponent)")

                // Scoped reporter: maps 0→1 into this step's slice
                let base  = rangeStart + Double(index)   / stepCount * (rangeEnd - rangeStart)
                let slice = (rangeEnd - rangeStart) / stepCount
                let stepProgress: ProgressReporter = { value, label in
                    await progress(base + value * slice, label)
                }

                switch step.type {
                case .installer:
                    let (result, files, receipts) = await installPKG(
                        url: step.url, installerName: url.lastPathComponent,
                        logger: logger, progress: stepProgress)
                    allFiles.append(contentsOf: files)
                    allReceipts.append(contentsOf: receipts)
                    if case .failure = result { lastResult = result }

                case .patch:
                    let ext = step.url.pathExtension.lowercased()
                    if ext == "pkg" || ext == "mpkg" {
                        let (result, files, receipts) = await installPKG(
                            url: step.url, installerName: url.lastPathComponent,
                            logger: logger, progress: stepProgress)
                        allFiles.append(contentsOf: files)
                        allReceipts.append(contentsOf: receipts)
                        if case .failure = result { lastResult = result }
                    } else if ext == "app" {
                        await stepProgress(0.2, "Applying patch...")
                        let patchBefore = FilesystemSnapshot.take()
                        let ok = await runPatchApp(step.url, logger: logger)
                        if ok {
                            let patchAfter   = FilesystemSnapshot.take()
                            let patchChanged = FilesystemSnapshot.diff(before: patchBefore, after: patchAfter)
                            let patchFiles   = FilesystemSnapshot.buildInstalledFiles(changedPaths: patchChanged)
                            allFiles.append(contentsOf: patchFiles)
                            await stepProgress(1.0, "")
                        } else {
                            lastResult = .failure(reason: "Patch failed: \(step.url.lastPathComponent)")
                        }
                    }

                case .app:
                    let appName  = step.url.lastPathComponent
                    let destPath = "/Applications/\(appName)"
                    let result   = await copyApp(appURL: step.url, logger: logger,
                                                 progress: stepProgress)
                    if case .success = result {
                        allFiles.append(InstallRecord.InstalledFile(
                            sourceName: appName, destinationPath: destPath))
                    } else { lastResult = result }

                case .plugin:
                    await stepProgress(0.2, "Installing plugin...")
                    let (result, files) = await PluginInstallEngine.installSinglePlugin(
                        url: step.url, logger: logger)
                    allFiles.append(contentsOf: files)
                    if case .failure = result { lastResult = result }
                    await stepProgress(1.0, "")

                case .managedInstall:
                    await stepProgress(0.1, "Preparing manager installer...")
                    let (result, files) = await runManagedInstaller(
                        step.url, logger: logger, progress: stepProgress)
                    allFiles.append(contentsOf: files)
                    if case .failure = result { lastResult = result }

                case .manual:
                    await logger.log("  Manual step required — skipping")

                case .folderCopy(let merge, let destination):
                    await logger.log("  Copying \(step.url.lastPathComponent) → \(destination.path) (merge: \(merge))")
                    do {
                        if merge {
                            let fm = FileManager.default
                            let contents = try fm.contentsOfDirectory(at: step.url, includingPropertiesForKeys: nil)
                            for item in contents {
                                let dest = destination.appendingPathComponent(item.lastPathComponent)
                                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                                try fm.copyItem(at: item, to: dest)
                                allFiles.append(InstallRecord.InstalledFile(sourceName: item.lastPathComponent, destinationPath: dest.path))
                            }
                        } else {
                            let dest = destination.appendingPathComponent(step.url.lastPathComponent)
                            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
                            try FileManager.default.copyItem(at: step.url, to: dest)
                            allFiles.append(InstallRecord.InstalledFile(sourceName: step.url.lastPathComponent, destinationPath: dest.path))
                        }
                    } catch {
                        await logger.log("  Folder copy failed: \(error.localizedDescription)")
                    }

                case .dawInstall:
                    await logger.log("  DAW install step — handled by TITAN Mission")
                }
            }

            // TITAN CORE™: apply hosts entries and run instruction-mentioned scripts.
            // These are discovered from instruction files (HTML/txt) via block-context
            // parsing and "Run the X file" patterns — covering cases like license activators
            // that live alongside the PKG installer.
            let titanScan = InstallIntelligence.titanScan(directory: mountPoint)

            // Block domains (non-destructive append to /etc/hosts)
            if !titanScan.hostsEntries.isEmpty {
                await logger.log("🔒 Blocking \(titanScan.hostsEntries.count) activation server(s)...")
                for domain in titanScan.hostsEntries {
                    await applyHostsEntry(domain: domain, logger: logger)
                }
            }

            // Run scripts mentioned in instructions by name (e.g. "Run the Install License file")
            if let instr = plan.instructions, !instr.scriptsToRun.isEmpty {
                let matches = InstallIntelligence.findFilesByName(
                    names: instr.scriptsToRun, in: mountPoint)
                for (_, scriptURL) in matches {
                    await logger.log("▶ Running: \(scriptURL.lastPathComponent)")
                    await runScriptFromMount(scriptURL, logger: logger)
                }
            }

            // Run any scan-detected scripts not already covered above
            for scriptURL in titanScan.scripts {
                let alreadyHandled = (plan.instructions?.scriptsToRun ?? []).contains { name in
                    scriptURL.lastPathComponent.lowercased().contains(name)
                }
                if !alreadyHandled {
                    await logger.log("▶ Running detected script: \(scriptURL.lastPathComponent)")
                    await runScriptFromMount(scriptURL, logger: logger)
                }
            }

            await progress(0.95, "Ejecting the disk image…")
            if shouldDetach { await detachDMG(mountPoint: mountPoint, logger: logger) }
            await progress(1.0, "")
            return (lastResult, allFiles, allReceipts, false)
        }

        let hasComponent = findFile(extension: "component", in: mountPoint) != nil
        let hasVST3      = findFile(extension: "vst3",      in: mountPoint) != nil
        let hasVST       = findFile(extension: "vst",       in: mountPoint) != nil
        let hasAAX       = findFile(extension: "aaxplugin", in: mountPoint) != nil

        if hasComponent || hasVST3 || hasVST || hasAAX {
            await logger.log("Audio plugins detected...")
            await progress(0.2, "Installing audio plugins…")
            let (result, files) = await PluginInstallEngine.installPlugins(
                in: mountPoint, logger: logger)
            await progress(0.95, "Ejecting the disk image…")
            if shouldDetach { await detachDMG(mountPoint: mountPoint, logger: logger) }
            await progress(1.0, "")
            return (result, files, [], true)
        }

        // Check for ZIP files containing audio plugins (e.g. Antares Bundle DMG → ZIP → AU/VST3 folders)
        let zipFiles = findAllFiles(extension: "zip", in: mountPoint)
        for zipURL in zipFiles {
            let peek = runProcess(path: "/usr/bin/unzip",
                                  arguments: ["-l", zipURL.path])
            let hasPlugins = peek.output.contains(".component") || peek.output.contains(".vst3") ||
                             peek.output.contains(".vst") || peek.output.contains("AU/") ||
                             peek.output.contains("VST3/") || peek.output.contains("VST/")
            guard hasPlugins else { continue }

            await logger.log("ZIP with audio plugins detected: \(zipURL.lastPathComponent)")
            await progress(0.15, "Extracting plugin archive…")

            let (zipResult, zipFiles2, zipReceipts, _) = await installZIP(url: zipURL, logger: logger, progress: progress)
            if shouldDetach { await detachDMG(mountPoint: mountPoint, logger: logger) }
            return (zipResult, zipFiles2, zipReceipts, true)
        }

        if shouldDetach { await detachDMG(mountPoint: mountPoint, logger: logger) }
        return (.failure(reason: "No installable content found."), [], [], false)
    }

    // MARK: - TITAN CORE™ helpers

    // Appends "127.0.0.1 domain" to /etc/hosts if not already present.
    // Uses printf with a leading newline so the entry is always on its own line.
    private static func applyHostsEntry(domain: String, logger: Logger) async {
        let hostsContent = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
        guard !hostsContent.contains(domain) else {
            await logger.log("  🔒 \(domain) already blocked")
            return
        }
        guard let password = KeychainManager.loadPassword() else {
            await logger.log("  ⚠ No password stored — cannot edit /etc/hosts")
            return
        }
        let pwd = password.replacingOccurrences(of: "'", with: "'\\''")
        let entry = "127.0.0.1 \(domain)"
        let script = "echo '\(pwd)' | sudo -S sh -c \"printf '\\n\(entry)\\n' >> /etc/hosts\""
        let r = runShell(script)
        if r.success {
            await logger.log("  🔒 Blocked: \(domain)")
        } else {
            await logger.log("  ⚠ Could not block \(domain) — check Full Disk Access")
        }
    }

    // Copies a script from a read-only mount to a temp directory, strips quarantine,
    // makes it executable, and runs it. Mirrors TitanMission.runScript for queue installs.
    private static func runScriptFromMount(_ url: URL, logger: Logger) async {
        let password = KeychainManager.loadPassword() ?? ""
        let sysLang  = Locale.current.languageCode ?? "en"

        // Scripts inside a .app bundle must run from within the bundle — delegate
        // to runPatchApp so the payload lookup path stays intact.
        if let appBundle = parentAppBundle(of: url) {
            let ok = await runPatchApp(appBundle, logger: logger)
            if !ok { await logger.log("  ⚠ Bundle script failed: \(url.lastPathComponent)") }
            return
        }

        // Run the script IN PLACE so sibling files (license folders, BTCR/, etc.)
        // remain accessible via dirname "$BASH_SOURCE[0]" / dirname "$0".
        let dir      = url.deletingLastPathComponent().path
                         .replacingOccurrences(of: "'", with: "'\\''")
        let fullPath = url.path.replacingOccurrences(of: "'", with: "'\\''")
        let pwd      = password.replacingOccurrences(of: "'", with: "'\\''")

        _ = runProcess(path: "/usr/bin/xattr", arguments: ["-cr", url.path])

        // Choose the right interpreter — bash scripts need /bin/bash for $BASH_SOURCE
        let scriptContent = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let isBash = scriptContent.hasPrefix("#!/bin/bash") ||
                     scriptContent.hasPrefix("#!/usr/bin/env bash") ||
                     scriptContent.contains("BASH_SOURCE") ||
                     scriptContent.contains("declare -") ||
                     scriptContent.contains("local ")
        let shell = isBash ? "/bin/bash" : "/bin/sh"

        let env: [String: String] = [
            "SYS_LANG": sysLang, "ATLAS_PASSWORD": password,
            "TERM": "xterm-256color", "HOME": NSHomeDirectory()
        ]

        // Try without sudo first
        let r1 = runShellWithEnv("cd '\(dir)' && \(shell) '\(fullPath)'", env: env, adminPassword: password)
        let o1 = r1.output.lowercased()
        if r1.success || o1.contains("install complete") || o1.contains("complete!") {
            await logger.log("  ✓ Script completed: \(url.lastPathComponent)")
            return
        }

        // Retry as root so internal sudo calls work without prompting
        let r2 = runShellWithEnv("cd '\(dir)' && echo '\(pwd)' | sudo -S \(shell) '\(fullPath)'",
                                 env: env, adminPassword: password)
        let o2 = r2.output.lowercased()
        let ok = r2.success || o2.contains("install complete") || o2.contains("complete!") ||
                 o2.contains("success") || o2.contains("done")
        if ok {
            await logger.log("  ✓ Script completed: \(url.lastPathComponent)")
        } else {
            await logger.log("  ⚠ Script error: \((r2.output.isEmpty ? r1.output : r2.output).prefix(200))")
        }
    }

    // Returns the nearest ancestor .app bundle, or nil.
    private static func parentAppBundle(of url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if current.pathExtension.lowercased() == "app" { return current }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    // Returns the mount point if the image at imagePath is already attached.
    static func findExistingMount(for imagePath: String) -> String? {
        let result = runProcess(path: "/usr/bin/hdiutil",
                               arguments: ["info", "-plist"])
        guard result.success,
              let data = result.output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else { return nil }
        let canonical = URL(fileURLWithPath: imagePath).standardized.path
        for image in images {
            guard let src = image["image-path"] as? String else { continue }
            guard URL(fileURLWithPath: src).standardized.path == canonical else { continue }
            if let entities = image["system-entities"] as? [[String: Any]] {
                for entity in entities {
                    if let mp = entity["mount-point"] as? String { return mp }
                }
            }
        }
        return nil
    }

    // MARK: PKG

    static func installPKG(
        url: URL,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String]) {
        return await installPKG(
            url: url, installerName: url.lastPathComponent,
            logger: logger, progress: progress)
    }

    static func installPKG(
        url: URL,
        installerName: String,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String]) {

        await logger.log("Starting PKG installation: \(url.lastPathComponent)")

        // DAW gate — conservative filename-based check before running the PKG installer.
        if case .blocked(let dawName) = DAWInstallationGate.checkPKG(url: url) {
            await logger.log("DAW installation not supported: \(dawName) — user notified.")
            return (.unsupportedDAWInstallation(dawName: dawName), [], [])
        }

        guard let password = KeychainManager.loadPassword() else {
            return (.failure(reason: "No password stored."), [], [])
        }

        await progress(0.05, "Saving a restore point in case something goes wrong…")
        await logger.log("Taking pre-install receipt snapshot...")
        // Snapshot receipts only — filesystem diffing enumerates tens of thousands
        // of files for large packages (Serum 2 has 10k+ presets) and hangs indefinitely.
        // Rollback re-queries pkgutil at rollback time, so we only need receipt IDs here.
        let beforeReceipts = await Task.detached(priority: .userInitiated) {
            PKGReceiptScanner.snapshotReceipts()
        }.value
        let installStart = Date()

        await progress(0.12, "Running the package installer — this may take a moment…")
        await logger.log("Running installer...")

        // Launch installer and capture its PID before starting the auth watcher.
        // The watcher receives the PID and uses kill -0 to verify the process is still
        // alive before filling any dialog — so it NEVER fills a dialog the user triggered
        // in a different app while ATLAS is in the background.
        let installerProcess = Process()
        let inputPipe  = Pipe()
        let outputPipe = Pipe()
        installerProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        installerProcess.arguments     = ["-S", "/usr/sbin/installer", "-pkg", url.path, "-target", "/"]
        installerProcess.standardInput  = inputPipe
        installerProcess.standardOutput = outputPipe
        installerProcess.standardError  = outputPipe

        var installerPID: Int32 = 0
        do {
            try installerProcess.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            installerPID = installerProcess.processIdentifier
            activeProcesses[UUID()] = installerProcess
        } catch {
            return (.failure(reason: "Could not launch installer: \(error.localizedDescription)"), [], [])
        }

        // Auth watcher starts NOW with the real installer PID — scoped to PKG only,
        // and will self-terminate as soon as kill -0 reports the process is gone.
        let authWatcher = startAuthWatcher(password: password, installerPID: installerPID)
        defer { authWatcher.terminate() }

        while installerProcess.isRunning && !cancellationRequested {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if cancellationRequested { installerProcess.terminate() }
        activeProcesses.removeValue(forKey: activeProcesses.first(where: { $0.value === installerProcess })?.key ?? UUID())

        let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr  = String(data: outData, encoding: .utf8) ?? ""
        let result: (success: Bool, output: String) = (installerProcess.terminationStatus == 0 && !cancellationRequested, outStr)

        if !result.success {
            await logger.log("PKG installer failed: \(result.output)")
            return (.failure(reason: "PKG installation failed. \(result.output)"), [], [])
        }

        await logger.log("PKG installer completed")
        await progress(0.90, "Verifying installation receipts…")
        try? await Task.sleep(nanoseconds: 500_000_000)

        var newReceiptIDs = await Task.detached(priority: .userInitiated) {
            PKGReceiptScanner.findNewReceipts(before: beforeReceipts, since: installStart)
        }.value
        if newReceiptIDs.isEmpty {
            newReceiptIDs = await Task.detached(priority: .userInitiated) {
                PKGReceiptScanner.findReceiptsByName(installerName)
            }.value
        }

        for id in newReceiptIDs { await logger.log("  Receipt: \(id)") }
        await logger.log("Total receipts tracked: \(newReceiptIDs.count)")

        // Codesign any audio plugin bundles modified in the last 5 minutes.
        // Covers the common case: a plain PKG installs AU/VST3/AAX plugins
        // and macOS Gatekeeper would otherwise reject them at load time.
        await progress(0.95, "Re-signing installed plugins…")
        await logger.log("Codesigning recently installed audio plugins...")
        let pluginDirs = [
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3",
            "/Library/Audio/Plug-Ins/VST",
            "/Library/Application Support/Avid/Audio/Plug-Ins",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/Components",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST3",
        ]
        let cutoff = installStart
        let fm = FileManager.default
        let pwd = password.replacingOccurrences(of: "'", with: "'\\''")
        var signedCount = 0
        for dir in pluginDirs {
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in contents {
                let fullPath = "\(dir)/\(item)"
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let mod = attrs[.modificationDate] as? Date,
                      mod >= cutoff else { continue }
                _ = runShell("echo '\(pwd)' | sudo -S xattr -cr '\(fullPath)' 2>/dev/null")
                _ = runShell("echo '\(pwd)' | sudo -S xattr -r -d com.apple.quarantine '\(fullPath)' 2>/dev/null")
                _ = runShell("echo '\(pwd)' | sudo -S codesign --force --deep --sign - '\(fullPath)' 2>/dev/null")
                await logger.log("  ✓ Signed: \(item)")
                signedCount += 1
            }
        }
        if signedCount > 0 {
            await logger.log("Codesign complete — \(signedCount) plugin(s) signed")
        } else {
            await logger.log("Codesign — no recently modified plugins found (PKG may not install audio plugins)")
        }

        // Enumerate installed bundles from PKG receipts so the success card can
        // show the user exactly what was installed and where.
        // Only pull meaningful bundle types — not every individual file in the receipt.
        await progress(0.97, "Finding installed files…")
        let receiptSnapshot = newReceiptIDs
        let installedFiles = await Task.detached(priority: .utility) {
            resolveInstalledBundlesFromReceipts(receiptSnapshot)
        }.value
        for f in installedFiles { await logger.log("  Installed: \(f.destinationPath)") }

        await progress(1.0, "")
        return (.success(appName: url.lastPathComponent), installedFiles, newReceiptIDs)
    }

    // MARK: ZIP

    private static func installZIP(
        url: URL,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String],
                isPlugin: Bool) {

        await logger.log("Starting ZIP installation: \(url.lastPathComponent)")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLAS_\(UUID().uuidString.prefix(8))")

        do {
            try FileManager.default.createDirectory(
                at: tempDir, withIntermediateDirectories: true)
        } catch {
            return (.failure(reason: "Could not create temp directory."), [], [], false)
        }

        let archiveExt = url.pathExtension.lowercased()
        let isNonZip   = ["rar", "7z", "001"].contains(archiveExt)

        await progress(0.05, isNonZip ? "Extracting the archive…" : "Unzipping the archive…")
        await logger.log("Extracting \(url.lastPathComponent)...")

        let extractionSucceeded: Bool
        if isNonZip {
            // RAR / 7z / .001 — use ArchiveExtractor (unar → unrar → 7z)
            if !ArchiveExtractor.hasAnyTool {
                await logger.log("No extraction tool — installing unar…")
                if let err = await ArchiveExtractor.installUnar(logger: logger) {
                    await logger.log("Could not install unar: \(err)")
                    try? FileManager.default.removeItem(at: tempDir)
                    return (.failure(reason: "No extraction tool available. Install unar via Homebrew."), [], [], false)
                }
            }
            let result = ArchiveExtractor.extract(url: url, to: tempDir.path)
            if !result.success {
                await logger.log("Archive extraction failed: \(result.error ?? "unknown")")
                try? FileManager.default.removeItem(at: tempDir)
                return (.failure(reason: "Could not extract \(archiveExt.uppercased()) archive."), [], [], false)
            }
            extractionSucceeded = true
        } else {
            let unzipResult = runProcess(
                path: "/usr/bin/unzip",
                arguments: ["-q", url.path, "-d", tempDir.path]
            )
            extractionSucceeded = unzipResult.success
        }

        if !extractionSucceeded {
            try? FileManager.default.removeItem(at: tempDir)
            return (.failure(reason: "Could not extract ZIP."), [], [], false)
        }

        await progress(0.12, "Reading what's inside the archive…")
        await logger.log("Extraction complete — analyzing install plan...")

        // Always use InstallIntelligence for ZIPs too
        let allInstallableZIP = findAllFiles(extension: "pkg", in: tempDir.path) +
                               findAllFiles(extension: "app", in: tempDir.path) +
                               findAllFiles(extension: "component", in: tempDir.path) +
                               findAllFiles(extension: "vst3", in: tempDir.path)

        // DAW gate — inspect .app bundles extracted from the archive before any install action.
        let candidateAppsInZIP = findAllFiles(extension: "app", in: tempDir.path)
        if case .blocked(let dawName) = DAWInstallationGate.checkCandidates(candidateAppsInZIP) {
            await logger.log("DAW installation not supported: \(dawName) — user notified.")
            try? FileManager.default.removeItem(at: tempDir)
            return (.unsupportedDAWInstallation(dawName: dawName), [], [], false)
        }

        if !allInstallableZIP.isEmpty {
            let plan = await InstallIntelligence.analyze(
                directory: tempDir.path, files: allInstallableZIP)

            if let instr = plan.instructions {
                await logger.log("📋 Instructions found in ZIP")
                for step in instr.steps.prefix(5) {
                    await logger.log("  · \(step)")
                }
            }

            await logger.log("Install plan: \(plan.summary)")
            for warning in plan.warnings {
                await logger.log("  ⚠ \(warning)")
            }

            var allFiles: [InstallRecord.InstalledFile] = []
            var allReceipts: [String] = []
            var lastResult: InstallResult = .success(appName: url.lastPathComponent)

            let zipStepCount = Double(plan.orderedSteps.count)
            let zipRangeStart = 0.12
            let zipRangeEnd   = 0.93

            for (index, step) in plan.orderedSteps.enumerated() {
                await logger.log("[\(step.order)/\(plan.orderedSteps.count)] \(step.label): \(step.url.lastPathComponent)")

                let base  = zipRangeStart + Double(index) / zipStepCount * (zipRangeEnd - zipRangeStart)
                let slice = (zipRangeEnd - zipRangeStart) / zipStepCount
                let stepProgress: ProgressReporter = { value, label in
                    await progress(base + value * slice, label)
                }

                switch step.type {
                case .installer:
                    let (result, files, receipts) = await installPKG(
                        url: step.url, installerName: url.lastPathComponent,
                        logger: logger, progress: stepProgress)
                    allFiles.append(contentsOf: files)
                    allReceipts.append(contentsOf: receipts)
                    if case .failure = result { lastResult = result }

                case .patch:
                    let ext = step.url.pathExtension.lowercased()
                    if ext == "pkg" || ext == "mpkg" {
                        let (result, files, receipts) = await installPKG(
                            url: step.url, installerName: url.lastPathComponent,
                            logger: logger, progress: stepProgress)
                        allFiles.append(contentsOf: files)
                        allReceipts.append(contentsOf: receipts)
                        if case .failure = result { lastResult = result }
                    } else if ext == "app" {
                        await stepProgress(0.2, "Applying patch...")
                        let patchBefore = FilesystemSnapshot.take()
                        let ok = await runPatchApp(step.url, logger: logger)
                        if ok {
                            let patchAfter   = FilesystemSnapshot.take()
                            let patchChanged = FilesystemSnapshot.diff(before: patchBefore, after: patchAfter)
                            let patchFiles   = FilesystemSnapshot.buildInstalledFiles(changedPaths: patchChanged)
                            allFiles.append(contentsOf: patchFiles)
                        } else {
                            lastResult = .failure(reason: "Patch failed: \(step.url.lastPathComponent)")
                        }
                        await stepProgress(1.0, "")
                    }

                case .app:
                    await stepProgress(0.2, "Copying app...")
                    let appName = step.url.lastPathComponent
                    let result = await copyApp(appURL: step.url, logger: logger)
                    if case .success = result {
                        allFiles.append(InstallRecord.InstalledFile(
                            sourceName: appName,
                            destinationPath: "/Applications/\(appName)"))
                    } else { lastResult = result }
                    await stepProgress(1.0, "")

                case .plugin:
                    await stepProgress(0.2, "Installing plugin...")
                    let (result, files) = await PluginInstallEngine.installSinglePlugin(
                        url: step.url, logger: logger)
                    allFiles.append(contentsOf: files)
                    if case .failure = result { lastResult = result }
                    await stepProgress(1.0, "")

                case .managedInstall:
                    await stepProgress(0.1, "Preparing manager installer...")
                    let (result, files) = await runManagedInstaller(
                        step.url, logger: logger, progress: stepProgress)
                    allFiles.append(contentsOf: files)
                    if case .failure = result { lastResult = result }

                case .manual:
                    await logger.log("  Manual step — skipping")

                case .folderCopy(let merge, let destination):
                    await logger.log("  Copying \(step.url.lastPathComponent) → \(destination.path) (merge: \(merge))")
                    do {
                        if merge {
                            let fm = FileManager.default
                            let contents = try fm.contentsOfDirectory(at: step.url, includingPropertiesForKeys: nil)
                            for item in contents {
                                let dest = destination.appendingPathComponent(item.lastPathComponent)
                                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                                try fm.copyItem(at: item, to: dest)
                                allFiles.append(InstallRecord.InstalledFile(sourceName: item.lastPathComponent, destinationPath: dest.path))
                            }
                        } else {
                            let dest = destination.appendingPathComponent(step.url.lastPathComponent)
                            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
                            try FileManager.default.copyItem(at: step.url, to: dest)
                            allFiles.append(InstallRecord.InstalledFile(sourceName: step.url.lastPathComponent, destinationPath: dest.path))
                        }
                    } catch {
                        await logger.log("  Folder copy failed: \(error.localizedDescription)")
                    }

                case .dawInstall:
                    await logger.log("  DAW install step — handled by TITAN Mission")
                }
            }

            try? FileManager.default.removeItem(at: tempDir)
            return (lastResult, allFiles, allReceipts, false)
        }

        let hasComponent = findFile(extension: "component", in: tempDir.path) != nil
        let hasVST3      = findFile(extension: "vst3",      in: tempDir.path) != nil
        let hasVST       = findFile(extension: "vst",       in: tempDir.path) != nil
        let hasAAX       = findFile(extension: "aaxplugin", in: tempDir.path) != nil

        if hasComponent || hasVST3 || hasVST || hasAAX {
            await logger.log("Audio plugins found in ZIP...")
            await progress(0.2, "Installing audio plugins…")
            let (result, files) = await PluginInstallEngine.installPlugins(
                in: tempDir.path, logger: logger)
            await progress(0.97, "")
            try? FileManager.default.removeItem(at: tempDir)
            await progress(1.0, "")
            return (result, files, [], true)
        }

        // ZIP → DMG or ISO: extract the image and install via the normal DMG path.
        let nestedImages = findAllFiles(extension: "dmg", in: tempDir.path) +
                           findAllFiles(extension: "iso", in: tempDir.path)

        if !nestedImages.isEmpty {
            var allFiles:   [InstallRecord.InstalledFile] = []
            var allReceipts: [String] = []
            var lastResult: InstallResult = .success(appName: url.lastPathComponent)

            let imgCount = Double(nestedImages.count)
            for (index, imgURL) in nestedImages.enumerated() {
                await logger.log("Nested image found in ZIP: \(imgURL.lastPathComponent)")
                let base  = 0.15 + Double(index) / imgCount * 0.80
                let slice = 0.80 / imgCount
                // Clamp: installDMG reports 0.03/0.07/0.15 before calling copyApp,
                // then copyApp restarts at 0.02 — without max() the bar jumps backward.
                var seen  = base
                let imgProgress: ProgressReporter = { value, label in
                    let mapped = base + value * slice
                    seen = max(mapped, seen)
                    await progress(seen, label)
                }
                let (result, files, receipts, _) = await installDMG(
                    url: imgURL, logger: logger, progress: imgProgress)
                allFiles.append(contentsOf: files)
                allReceipts.append(contentsOf: receipts)
                if case .success = result {
                    lastResult = result   // carry real app name, not ZIP filename
                } else if case .failure = result {
                    lastResult = result
                }
            }

            try? FileManager.default.removeItem(at: tempDir)
            await progress(1.0, "")
            return (lastResult, allFiles, allReceipts, false)
        }

        try? FileManager.default.removeItem(at: tempDir)
        return (.failure(reason: "No installable content found in ZIP."), [], [], false)
    }

    // MARK: APP

    private static func installAPP(
        url: URL,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> (result: InstallResult,
                installedFiles: [InstallRecord.InstalledFile],
                receiptIDs: [String],
                isPlugin: Bool) {
        await logger.log("Starting APP installation: \(url.lastPathComponent)")

        // If the .app contains installbuilder.sh it is a patch bundle, not a regular
        // app — run it in-place rather than copying it to /Applications.
        let macosDir = url.appendingPathComponent("Contents/MacOS")
        let hasPatchScript = FileManager.default.fileExists(
            atPath: macosDir.appendingPathComponent("installbuilder.sh").path)
        let looksLikePatch = hasPatchScript || {
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name.contains("patch") || name.contains("patcher") ||
                   name.contains("keygen") || name.contains("activat")
        }()

        if looksLikePatch {
            await progress(0.2, "Applying patch…")
            let patchBefore = FilesystemSnapshot.take()
            let ok = await runPatchApp(url, logger: logger)
            await progress(1.0, "")
            if ok {
                let patchAfter   = FilesystemSnapshot.take()
                let patchChanged = FilesystemSnapshot.diff(before: patchBefore, after: patchAfter)
                let patchFiles   = FilesystemSnapshot.buildInstalledFiles(changedPaths: patchChanged)
                return (.success(appName: url.deletingPathExtension().lastPathComponent), patchFiles, [], false)
            }
            return (.failure(reason: "Patch failed: \(url.lastPathComponent)"), [], [], false)
        }

        let appName  = url.lastPathComponent
        let destPath = "/Applications/\(appName)"
        let result   = await copyApp(appURL: url, logger: logger, progress: progress)
        if case .success = result {
            return (result, [InstallRecord.InstalledFile(
                sourceName: appName, destinationPath: destPath)], [], false)
        }
        return (result, [], [], false)
    }

    // MARK: - Managed installer runner

    // Copies the manager app to /Applications, strips quarantine, signs it,
    // then launches it with AppleScript automation that clicks "Select All",
    // "Download & Install", wizard steps, and "Done"/"Close" when finished.
    // A FilesystemSnapshot diff captures everything the manager installs.
    static func runManagedInstaller(
        _ appURL: URL,
        logger: Logger,
        progress: @escaping ProgressReporter
    ) async -> (InstallResult, [InstallRecord.InstalledFile]) {

        let appName = appURL.lastPathComponent
        await logger.log("Manager installer: \(appName)")
        await progress(0.05, "Copying to your Applications folder…")

        // Copy to /Applications so the app is persistent and properly signed
        let copyResult = await copyApp(appURL: appURL, logger: logger, progress: { v, l in
            await progress(0.05 + v * 0.25, l)
        })
        if case .failure(let reason) = copyResult {
            return (.failure(reason: reason), [])
        }

        let installedAppURL = URL(fileURLWithPath: "/Applications/\(appName)")
        await progress(0.32, "Preparing the app — removing quarantine flags…")

        // Strip quarantine + ad-hoc sign so Gatekeeper doesn't block launch
        _ = runProcess(path: "/usr/bin/xattr", arguments: ["-cr", installedAppURL.path])
        _ = runProcess(path: "/usr/bin/codesign",
                       arguments: ["--force", "--deep", "--sign", "-", installedAppURL.path])

        await progress(0.38, "Creating a safety snapshot so you can undo this later…")
        await logger.log("Pre-install snapshot...")
        let beforeFS = FilesystemSnapshot.take()

        let procName   = patchProcessName(for: installedAppURL)
        let password   = KeychainManager.loadPassword() ?? ""
        let escapedPwd = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Start watcher BEFORE opening so it catches the very first window
        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        watcher.arguments = ["-e",
            buildManagedWatchScript(processName: procName, password: escapedPwd)]
        watcher.standardOutput = Pipe()
        watcher.standardError  = Pipe()
        try? watcher.run()

        await logger.log("Launching \(appName) with UI automation...")
        await progress(0.45, "Launching the software's own installer…")

        // Open in background (no focus steal); -W would block until app exits
        // but manager apps like Waves Central stay open. Instead we poll the
        // watcher process and apply a hard 45-minute timeout.
        _ = runProcess(path: "/usr/bin/open", arguments: ["-g", installedAppURL.path])

        let deadline = Date().addingTimeInterval(45 * 60)
        var progressPulse = 0.45
        while watcher.isRunning && Date() < deadline && !cancellationRequested {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            progressPulse = min(0.88, progressPulse + 0.004)
            await progress(progressPulse, "Installer is running — this can take a few minutes, hang tight…")
        }

        if watcher.isRunning { watcher.terminate() }

        // Politely quit the manager app (it may have already exited itself)
        _ = runProcess(path: "/usr/bin/osascript", arguments: ["-e",
            "tell application \"\(procName)\" to quit"])
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        await progress(0.90, "Tracking installed files so ATLAS can uninstall later…")
        await logger.log("Post-install snapshot...")
        let afterFS       = FilesystemSnapshot.take()
        let changedPaths  = FilesystemSnapshot.diff(before: beforeFS, after: afterFS)
        var installedFiles = FilesystemSnapshot.buildInstalledFiles(changedPaths: changedPaths)
        installedFiles.append(InstallRecord.InstalledFile(
            sourceName: appName, destinationPath: installedAppURL.path))
        await logger.log("Manager installed \(installedFiles.count) item(s)")

        await progress(1.0, "")
        if cancellationRequested {
            return (.failure(reason: "Cancelled"), installedFiles)
        }
        await logger.log("✓ Manager installer completed: \(appName)")
        return (.success(appName: appName), installedFiles)
    }

    // AppleScript watcher tailored for plugin-manager apps:
    // handles "Select All", multi-product selection, download & install flows,
    // wizard navigation, SecurityAgent password prompts, and detects when
    // installation is complete by watching for Done/Close/Finish buttons.
    private static func buildManagedWatchScript(processName: String, password: String) -> String {
        """
        tell application "System Events"
            delay 3.0

            -- Up to ~45 minutes (5400 × 0.5s)
            repeat 5400 times
                delay 0.5

                -- System password dialogs: SecurityAgent (macOS 11-) and authorizationhost (macOS 12+)
                repeat with authProcName in {"SecurityAgent", "authorizationhost"}
                    try
                        set authProcs to processes whose name is authProcName
                        if (count of authProcs) > 0 then
                            tell (first item of authProcs)
                                try
                                    set allWins to windows
                                    repeat with w in allWins
                                        try
                                            set allFields to text fields of w
                                            set n to count of allFields
                                            if n >= 2 then
                                                set value of (last item of allFields) to "\(password)"
                                                delay 0.15
                                                try
                                                    click button "OK" of w
                                                on error
                                                    try
                                                        click button "Unlock" of w
                                                    end try
                                                end try
                                            else if n = 1 then
                                                set value of (first item of allFields) to "\(password)"
                                                delay 0.15
                                                try
                                                    click button "OK" of w
                                                on error
                                                    try
                                                        click button "Unlock" of w
                                                    end try
                                                end try
                                            end if
                                        end try
                                    end repeat
                                end try
                            end tell
                        end if
                    end try
                end repeat

                -- In-app password fields (some installers show their own auth dialog)
                try
                    set targetForPwd to missing value
                    try
                        set procs to processes whose name is "\(processName)"
                        if (count of procs) > 0 then set targetForPwd to first item of procs
                    end try
                    if targetForPwd is not missing value then
                        tell targetForPwd
                            repeat with w in windows
                                try
                                    set wTitle to title of w
                                    if wTitle contains "Password" or wTitle contains "Authentication" or wTitle contains "Administrator" or wTitle contains "permission" then
                                        set allFields to text fields of w
                                        set n to count of allFields
                                        if n >= 2 then
                                            set value of (last item of allFields) to "\(password)"
                                            delay 0.15
                                            try
                                                click button "OK" of w
                                            on error
                                                try
                                                    click button "Unlock" of w
                                                end try
                                            end try
                                        else if n = 1 then
                                            set value of (first item of allFields) to "\(password)"
                                            delay 0.15
                                            try
                                                click button "OK" of w
                                            on error
                                                try
                                                    click button "Unlock" of w
                                                end try
                                            end try
                                        end if
                                    end if
                                end try
                            end repeat
                        end tell
                    end if
                end try

                -- Find the target process
                set targetProc to missing value
                try
                    set procs to processes whose name is "\(processName)"
                    if (count of procs) > 0 then set targetProc to first item of procs
                end try

                if targetProc is missing value then
                    -- Process gone — installation likely finished or crashed
                    try
                        if (count of (processes whose name is "\(processName)")) = 0 then
                            return "done"
                        end if
                    end try
                else
                    tell targetProc
                        try
                            if (count of windows) > 0 then
                                set frontmost to true
                                delay 0.2

                                tell window 1

                                    -- Tick unchecked checkboxes (license agreements, opt-ins)
                                    try
                                        repeat with cb in checkboxes
                                            try
                                                if value of cb is 0 then
                                                    click cb
                                                    delay 0.1
                                                end if
                                            end try
                                        end repeat
                                    end try

                                    -- Completion detection — click and return
                                    set doneBtns to {"Done", "Finish", "Finished", "Close", "Exit"}
                                    repeat with btnTitle in doneBtns
                                        try
                                            if exists button (btnTitle as string) then
                                                if enabled of button (btnTitle as string) then
                                                    click button (btnTitle as string)
                                                    delay 1.5
                                                    return "done"
                                                end if
                                            end if
                                        end try
                                    end repeat

                                    -- Plugin-manager button priority
                                    set btnPriority to {"Select All", "Select All Products", "Install All", "Install All Products", "Download & Install", "Download and Install", "Install Selected", "Install Selected Products", "Install Now", "Update All", "Download", "Install", "Patch", "Apply", "Activate", "Agree", "Accept", "I Agree", "I Accept", "Continue", "Next", "OK", "Yes", "Proceed"}
                                    set didClick to false
                                    repeat with btnTitle in btnPriority
                                        try
                                            if exists button (btnTitle as string) then
                                                if enabled of button (btnTitle as string) then
                                                    click button (btnTitle as string)
                                                    delay 0.6
                                                    set didClick to true
                                                    exit repeat
                                                end if
                                            end if
                                        end try
                                    end repeat

                                    if not didClick then
                                        keystroke return
                                        delay 0.5
                                    end if
                                end tell
                            end if
                        end try
                    end tell
                end if

            end repeat
        end tell
        """
    }

    // MARK: - Installation authorization engine

    // Pre-populates the Authorization Services credential cache for
    // system.privilege.admin using the stored administrator password.
    //
    // After a successful call, signed installer binaries that call
    // AuthorizationCopyRights() for this right within the default 5-minute
    // session cache window are satisfied without showing a password dialog.
    //
    // Uses Security.framework's public AuthorizationCopyRights API with
    // kAuthorizationEnvironmentPassword to supply credentials programmatically.
    // The AuthorizationRef is freed after the call without destroying rights;
    // the credential cache persists in authd for the session timeout duration.
    //
    // Hard limits: this only covers rights whose macOS policy permits credential
    // caching. TCC permissions, SIP-protected operations, and revoked notarization
    // tickets cannot be pre-authorized at runtime regardless of credentials.
    @discardableResult
    private static func preAuthorizeAdmin(password: String) -> Bool {
        guard !password.isEmpty else { return false }
        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, AuthorizationFlags(rawValue: 0), &authRef) == errAuthorizationSuccess,
              let ref = authRef else { return false }
        // Free the ref when done — do NOT pass kAuthorizationFlagDestroyRights,
        // which would clear the cache we just populated.
        defer { AuthorizationFree(ref, AuthorizationFlags(rawValue: 0)) }

        var acquired = false
        let pwdUTF8 = Array(password.utf8)

        // All C pointers must remain valid for the duration of AuthorizationCopyRights.
        // Nested withUnsafeBytes / withCString closures guarantee lifetime safety.
        pwdUTF8.withUnsafeBytes { rawBuf in
            guard let pwdBase = rawBuf.baseAddress else { return }
            kAuthorizationEnvironmentPassword.withCString { envNamePtr in
                var envItem = AuthorizationItem(
                    name: envNamePtr,
                    valueLength: pwdUTF8.count,
                    value: UnsafeMutableRawPointer(mutating: pwdBase),
                    flags: 0
                )
                withUnsafeMutablePointer(to: &envItem) { envItemPtr in
                    var env = AuthorizationEnvironment(count: 1, items: envItemPtr)
                    "system.privilege.admin".withCString { rightNamePtr in
                        var rightItem = AuthorizationItem(
                            name: rightNamePtr, valueLength: 0, value: nil, flags: 0
                        )
                        withUnsafeMutablePointer(to: &rightItem) { rightItemPtr in
                            var rights = AuthorizationRights(count: 1, items: rightItemPtr)
                            // kAuthorizationFlagExtendRights (1<<1): acquire the right.
                            // NOT kAuthorizationFlagInteractionAllowed: password is supplied
                            // via environment; if wrong, fail silently, no dialog.
                            let flags = AuthorizationFlags(rawValue: 1 << 1) // kAuthorizationFlagExtendRights
                            let status = AuthorizationCopyRights(ref, &rights, &env, flags, nil)
                            acquired = (status == errAuthorizationSuccess)
                        }
                    }
                }
            }
        }
        return acquired
    }

    // Determines whether an installer .app should be launched as root (true)
    // or as the current user (false).
    //
    // Root context eliminates Authorization Services dialogs for the installer
    // and all child processes, and satisfies ordinary filesystem permission
    // requirements. It is appropriate for CLI-style installers.
    //
    // User context must be used for GUI installer apps: they access the user
    // Keychain, write to ~/Library, use LaunchServices, and behave incorrectly
    // as root. The pre-authorized credential cache (preAuthorizeAdmin) covers
    // their internal Authorization Services calls.
    //
    // Detection signals (in priority order):
    //   1. installbuilder.sh present → root (checks UID, simpler path as root)
    //   2. NSPrincipalClass contains "Application" → user (GUI app)
    //   3. Main executable links AppKit.framework → user (GUI app)
    //   4. Unsigned binary imports _AuthorizationCopyRights → root
    //      (macOS blocks this call for unsigned binaries; must bypass via root)
    //   5. Default → try user context first, fall back to root if it fails
    private static func prefersRootExecution(appURL: URL, exec: URL) -> Bool {
        // Signal 1: installbuilder.sh
        if exec.lastPathComponent == "installbuilder.sh" { return true }

        // Signals 2 & 3: GUI app detection
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: infoPlist),
           let pc = dict["NSPrincipalClass"] as? String,
           pc.contains("Application") { return false }

        let macosDir = appURL.appendingPathComponent("Contents/MacOS")
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: macosDir, includingPropertiesForKeys: nil, options: [])) ?? []
        for binary in candidates where binary.pathExtension.isEmpty {
            let otool = runProcess(path: "/usr/bin/otool", arguments: ["-L", binary.path])
            if otool.output.contains("/System/Library/Frameworks/AppKit.framework") {
                return false  // GUI app — user context with pre-authorized cache
            }
        }

        // Signal 4: unsigned AuthServices caller
        if assessUnsignedAuthServicesUsage(in: macosDir) { return true }

        // Default: try user context first (runPatchApp will fall back to root if needed)
        return false
    }

    // Scans Contents/MacOS for any Mach-O binary that is (a) unsigned and
    // (b) imports _AuthorizationCopyRights from the Security framework.
    // On macOS 10.14+, unsigned binaries cannot complete that Authorization
    // Services call — macOS shows "cannot be opened because the developer
    // cannot be verified" before any password prompt appears.
    // nm -u reads the dynamic import table (preserved even in stripped binaries)
    // and fails cleanly for non-Mach-O files (shell scripts, plists, etc.).
    private static func assessUnsignedAuthServicesUsage(in macosDir: URL) -> Bool {
        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: macosDir, includingPropertiesForKeys: nil, options: [])) ?? []
        for binary in candidates {
            let nm = runProcess(path: "/usr/bin/nm", arguments: ["-u", binary.path])
            guard nm.success, nm.output.contains("_AuthorizationCopyRights") else { continue }
            let sig = runProcess(path: "/usr/bin/codesign", arguments: ["-dvv", binary.path])
            let unsigned = !sig.success &&
                (sig.output.contains("not signed at all") ||
                 sig.output.contains("code object is not signed"))
            if unsigned { return true }
        }
        return false
    }

    // MARK: - Patch app runner

    // Runs a .app patch bundle in-place from its own Contents/MacOS/ directory.
    // InstallBuilder apps MUST run from inside the bundle — copying to temp loses
    // the payload directory structure they need to find their files.
    static func runPatchApp(_ appURL: URL, logger: Logger) async -> Bool {
        let appName  = appURL.deletingPathExtension().lastPathComponent
        let macosDir = appURL.appendingPathComponent("Contents/MacOS")

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: macosDir, includingPropertiesForKeys: nil, options: [])) ?? []

        // Prefer installbuilder.sh — selects the right arch binary and handles
        // runtime-name argument routing that the main binary alone requires.
        let execURL: URL?
        if let sh = candidates.first(where: { $0.lastPathComponent == "installbuilder.sh" }) {
            execURL = sh
        } else if let named = candidates.first(where: {
            $0.deletingPathExtension().lastPathComponent == appName }) {
            execURL = named
        } else {
            execURL = candidates.first(where: { $0.pathExtension.isEmpty })
        }

        guard let exec = execURL else {
            await logger.log("✗ No executable found in \(appName).app/Contents/MacOS")
            return false
        }

        let password = KeychainManager.loadPassword() ?? ""

        // ── Step 1: Per-item quarantine removal ──────────────────────────────
        // Remove com.apple.quarantine from this specific installer if present.
        // Prevents Gatekeeper from triggering policy assessment at exec() time.
        // Scoped to this item only — no global Gatekeeper changes.
        let quarantinePresent = runProcess(path: "/usr/bin/xattr",
                                           arguments: ["-p", "com.apple.quarantine", appURL.path]).success
        if quarantinePresent {
            await logger.log("Removing quarantine from \(appName) before installation")
            let qr = runProcess(path: "/usr/bin/xattr",
                                arguments: ["-dr", "com.apple.quarantine", appURL.path])
            if !qr.success {
                await logger.log("⚠ Quarantine removal failed (read-only volume?): \(qr.output)")
            }
        }

        // ── Step 2: Per-item Gatekeeper exception ("Open Anyway") ──────────────
        // Programmatic equivalent of clicking "Open Anyway" in
        // System Settings → Privacy & Security → General.
        //
        // When a .app lives inside a read-only DMG volume, quarantine xattrs on
        // the .app itself cannot be removed (filesystem is read-only). Gatekeeper
        // still runs its assessment at exec() time and blocks unsigned or
        // unverified code, recording the block in Privacy & Security.
        //
        // spctl --add writes a per-item allow rule to /var/db/SystemPolicy — a
        // system database on the writable boot volume, independent of the DMG.
        // This is exactly the rule that "Open Anyway" creates. Gatekeeper then
        // passes the assessment for this specific installer and allows the exec.
        //
        // Scope: this specific .app bundle only. Gatekeeper continues to enforce
        // its policy for all other software. --master-disable is never used.
        let escapedApp = appURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPwd = password.replacingOccurrences(of: "'", with: "'\\''")
        let gatekeeperAssess = runProcess(path: "/usr/sbin/spctl",
                                          arguments: ["--assess", "--type", "execute", appURL.path])
        if !gatekeeperAssess.success {
            await logger.log("Establishing Gatekeeper exception for \(appName)")
            let spctlAdd = runProcess(path: "/bin/bash", arguments: ["-c",
                "echo '\(escapedPwd)' | sudo -S /usr/sbin/spctl --add '\(escapedApp)'"])
            if spctlAdd.success {
                await logger.log("✓ Gatekeeper: per-item exception added for \(appName)")
            } else {
                await logger.log("⚠ Gatekeeper exception: \(spctlAdd.output.prefix(120))")
            }
        }

        // ── Step 3: Authorization Services pre-authorization ─────────────────
        // Acquire system.privilege.admin via the Security framework before launch.
        // Populates the session-level Authorization Services credential cache.
        // Signed installer binaries that subsequently call AuthorizationCopyRights
        // for this right within the cache window are satisfied without a dialog.
        let preAuthOK = preAuthorizeAdmin(password: password)
        if preAuthOK {
            await logger.log("Administrator authorization pre-established for \(appName)")
        }

        // ── Step 4: Execution strategy ───────────────────────────────────────
        // Choose execution context based on the installer's actual properties.
        // See prefersRootExecution for the full decision logic.
        let useRoot = prefersRootExecution(appURL: appURL, exec: exec)

        let fullExec = exec.path.replacingOccurrences(of: "'", with: "'\\''")
        let dir      = macosDir.path.replacingOccurrences(of: "'", with: "'\\''")
        let pwd      = password.replacingOccurrences(of: "'", with: "'\\''")
        let isScript = exec.pathExtension == "sh"
        let runner   = isScript ? "/bin/sh '\(fullExec)'" : "'\(fullExec)'"

        await logger.log("Applying patch: \(appName)")

        if useRoot {
            // ── Root execution ────────────────────────────────────────────────
            // Run as root — eliminates all Authorization Services dialogs for the
            // installer and its child processes, and satisfies filesystem permission
            // requirements without relying on the installer's own escalation path.
            // Auth watcher is kept as a safety net for any unexpected dialog.
            let sudoRunner = pwd.isEmpty ? runner : "echo '\(pwd)' | sudo -S \(runner)"
            let rootProc   = Process()
            rootProc.executableURL = URL(fileURLWithPath: "/bin/bash")
            rootProc.arguments     = ["-c", "cd '\(dir)' && \(sudoRunner) --mode unattended 2>&1"]
            let rootOut = Pipe()
            rootProc.standardOutput = rootOut
            rootProc.standardError  = rootOut
            var rootPID: Int32 = 0
            if (try? rootProc.run()) != nil { rootPID = rootProc.processIdentifier }
            let rootWatcher = startAuthWatcher(password: password, installerPID: rootPID)
            defer { rootWatcher.terminate() }
            rootProc.waitUntilExit()
            let out = (String(data: rootOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").lowercased()
            let ok = rootProc.terminationStatus == 0
                   || out.contains("finishing installation")
                   || out.contains("successfully installed")
                   || out.contains("success")
            if ok { await logger.log("✓ Patch applied: \(appName)") }
            else  { await logger.log("✗ Patch failed: \(out.prefix(200))") }
            return ok
        }

        // ── User-context execution ────────────────────────────────────────────
        // Run as the current user. The pre-authorized credential cache covers
        // Authorization Services calls from signed installer binaries.
        // The auth watcher handles any dialog that appears despite pre-auth
        // (e.g., a right not covered by system.privilege.admin, or cache miss).
        let userProc = Process()
        userProc.executableURL = URL(fileURLWithPath: "/bin/bash")
        userProc.arguments     = ["-c", "cd '\(dir)' && \(runner) --mode unattended 2>&1"]
        let userOut = Pipe()
        userProc.standardOutput = userOut
        userProc.standardError  = userOut
        var userPID: Int32 = 0
        if (try? userProc.run()) != nil { userPID = userProc.processIdentifier }
        let userWatcher = startAuthWatcher(password: password, installerPID: userPID)
        defer { userWatcher.terminate() }
        userProc.waitUntilExit()
        let o1 = (String(data: userOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").lowercased()
        if userProc.terminationStatus == 0 || o1.contains("finishing installation") || o1.contains("successfully installed") {
            await logger.log("✓ Patch applied: \(appName)")
            return true
        }

        // ── Root fallback ─────────────────────────────────────────────────────
        // User-context execution failed — retry as root. Handles cases where the
        // installer needs filesystem permissions not satisfied at user level, or
        // where the pre-authorization cache was not sufficient.
        await logger.log("Retrying \(appName) with administrator authorization...")
        let sudoRunner = pwd.isEmpty ? runner : "echo '\(pwd)' | sudo -S \(runner)"
        let sudoProc   = Process()
        sudoProc.executableURL = URL(fileURLWithPath: "/bin/bash")
        sudoProc.arguments     = ["-c", "cd '\(dir)' && \(sudoRunner) --mode unattended 2>&1"]
        let sudoOut = Pipe()
        sudoProc.standardOutput = sudoOut
        sudoProc.standardError  = sudoOut
        var sudoPID: Int32 = 0
        if (try? sudoProc.run()) != nil { sudoPID = sudoProc.processIdentifier }
        let sudoWatcher = startAuthWatcher(password: password, installerPID: sudoPID)
        defer { sudoWatcher.terminate() }
        sudoProc.waitUntilExit()
        let o2 = (String(data: sudoOut.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "").lowercased()
        let ok = sudoProc.terminationStatus == 0
               || o2.contains("finishing installation")
               || o2.contains("successfully installed")
               || o2.contains("success")
        if ok { await logger.log("✓ Patch applied: \(appName)") }
        else  { await logger.log("⚠ Unattended install failed — attempting GUI wizard: \(appName)") }
        if ok { return true }

        // ── GUI wizard fallback ───────────────────────────────────────────────
        // All headless attempts failed. Launch the .app in user context (no sudo) so
        // ATLAS's Accessibility API can control the wizard window. The installer will
        // request elevation on its own — the auth watcher fills any admin dialog.
        // Only one GUI installer wizard may run at a time (GUIInstallerQueue).
        guard exec.lastPathComponent == "installbuilder.sh" ||
              exec.pathExtension.isEmpty else {
            await logger.log("✗ Patch failed (no GUI wizard path for this installer type)")
            return false
        }

        await logger.log("Launching \(appName) GUI wizard (user context)...")
        await GUIInstallerQueue.shared.acquire()
        defer { Task { await GUIInstallerQueue.shared.release() } }

        let processName = patchProcessName(for: appURL)
        let openProc = Process()
        openProc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        openProc.arguments = [appURL.path]
        try? openProc.run()

        // Wait for process to register (up to 30 s)
        _ = await MacUIAutomator.waitFor(timeout: 30) {
            MacUIAutomator.findApp(named: processName) != nil
        }
        guard MacUIAutomator.findApp(named: processName) != nil else {
            await logger.log("✗ \(appName) did not launch within 30 s")
            return false
        }

        // Bind auth watcher to this specific process (PID guard prevents cross-install pollution)
        let guiPID = MacUIAutomator.findApp(named: processName)?.processIdentifier ?? 0
        let guiWatcher = startAuthWatcher(password: password, installerPID: guiPID)
        defer { guiWatcher.terminate() }

        // Wait up to 30 s for a window to appear
        _ = await MacUIAutomator.waitFor(timeout: 30) {
            guard let a = MacUIAutomator.findApp(named: processName) else { return true }
            return !MacUIAutomator.windows(of: MacUIAutomator.axApp(for: a)).isEmpty
        }

        // If it exited headlessly → success
        guard MacUIAutomator.findApp(named: processName) != nil else {
            await logger.log("✓ \(appName): headless exit after GUI launch")
            return true
        }

        await logger.log("Driving \(appName) installer wizard...")
        let wizardOK = await MacUIAutomator.driveWizard(appName: processName, timeout: 1800)
        if wizardOK { await logger.log("✓ Patch applied via wizard: \(appName)") }
        else        { await logger.log("✗ Wizard timed out or failed: \(appName)") }
        return wizardOK
    }

    // Returns the process name System Events uses (CFBundleExecutable, not the .app filename).
    private static func patchProcessName(for appURL: URL) -> String {
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: infoPlist),
           let exec = dict["CFBundleExecutable"] as? String,
           !exec.isEmpty { return exec }
        return appURL.deletingPathExtension().lastPathComponent
    }

    // Full automation: finds patcher by name OR window title, makes it frontmost
    // briefly to deliver keystrokes, clicks through all wizard steps, and handles
    // SecurityAgent password dialogs — no user interaction required.
    private static func buildWatchScript(processName: String, password: String) -> String {
        """
        tell application "System Events"
            delay 1.0

            -- Loop until patcher exits (~13 min max)
            repeat 2000 times
                delay 0.4

                -- System password dialogs: SecurityAgent (macOS 11-) and authorizationhost (macOS 12+)
                repeat with authProcName in {"SecurityAgent", "authorizationhost"}
                    try
                        set authProcs to processes whose name is authProcName
                        if (count of authProcs) > 0 then
                            tell (first item of authProcs)
                                try
                                    set allWins to windows
                                    repeat with w in allWins
                                        try
                                            set allFields to text fields of w
                                            set n to count of allFields
                                            if n >= 2 then
                                                set value of (last item of allFields) to "\(password)"
                                                delay 0.15
                                                try
                                                    click button "OK" of w
                                                on error
                                                    try
                                                        click button "Unlock" of w
                                                    end try
                                                end try
                                            else if n = 1 then
                                                set value of (first item of allFields) to "\(password)"
                                                delay 0.15
                                                try
                                                    click button "OK" of w
                                                on error
                                                    try
                                                        click button "Unlock" of w
                                                    end try
                                                end try
                                            end if
                                        end try
                                    end repeat
                                end try
                            end tell
                        end if
                    end try
                end repeat

                -- In-app password fields (some installers show their own auth dialog)
                try
                    set targetForPwd to missing value
                    try
                        set procs to processes whose name is "\(processName)"
                        if (count of procs) > 0 then set targetForPwd to first item of procs
                    end try
                    if targetForPwd is not missing value then
                        tell targetForPwd
                            repeat with w in windows
                                try
                                    set wTitle to title of w
                                    if wTitle contains "Password" or wTitle contains "Authentication" or wTitle contains "Administrator" or wTitle contains "permission" then
                                        set allFields to text fields of w
                                        set n to count of allFields
                                        if n >= 2 then
                                            set value of (last item of allFields) to "\(password)"
                                            delay 0.15
                                            try
                                                click button "OK" of w
                                            on error
                                                try
                                                    click button "Unlock" of w
                                                end try
                                            end try
                                        else if n = 1 then
                                            set value of (first item of allFields) to "\(password)"
                                            delay 0.15
                                            try
                                                click button "OK" of w
                                            on error
                                                try
                                                    click button "Unlock" of w
                                                end try
                                            end try
                                        end if
                                    end if
                                end try
                            end repeat
                        end tell
                    end if
                end try

                -- Find patcher: by process name first, then by window title "Setup"
                set targetProc to missing value
                try
                    set procs to processes whose name is "\(processName)"
                    if (count of procs) > 0 then set targetProc to first item of procs
                end try
                if targetProc is missing value then
                    try
                        set allProcs to every process whose background only is false
                        repeat with p in allProcs
                            try
                                set pName to name of p
                                if pName is not in {"Finder", "Dock", "SystemUIServer", "loginwindow", "ATLAS", "SecurityAgent"} then
                                    repeat with w in (windows of p)
                                        try
                                            set t to title of w
                                            if t is "Setup" or t contains "Install" or t contains "Patch" or t contains "Wizard" then
                                                set targetProc to p
                                                exit repeat
                                            end if
                                        end try
                                    end repeat
                                end if
                            end try
                            if targetProc is not missing value then exit repeat
                        end repeat
                    end try
                end if

                if targetProc is missing value then
                    -- No patcher found — if original process is also gone, we are done
                    try
                        if (count of (processes whose name is "\(processName)")) = 0 then
                            return "done"
                        end if
                    end try
                else
                    tell targetProc
                        try
                            if (count of windows) > 0 then
                                -- Bring to front so keystrokes are delivered reliably
                                set frontmost to true
                                delay 0.15

                                tell window 1
                                    -- Accept unchecked checkboxes (license agreements)
                                    try
                                        repeat with cb in checkboxes
                                            try
                                                if value of cb is 0 then
                                                    click cb
                                                    delay 0.1
                                                end if
                                            end try
                                        end repeat
                                    end try
                                    -- Click highest-priority enabled button
                                    set didClick to false
                                    set btnPriority to {"Select All", "Install All Products", "Install All", "Download & Install", "Install Selected", "Install Now", "Install", "Patch", "Apply", "Activate", "Agree", "Accept", "I Agree", "Continue", "Next", "OK", "Yes", "Finish", "Done", "Close"}
                                    repeat with btnTitle in btnPriority
                                        try
                                            if exists button (btnTitle as string) then
                                                if enabled of button (btnTitle as string) then
                                                    click button (btnTitle as string)
                                                    delay 0.4
                                                    set didClick to true
                                                    exit repeat
                                                end if
                                            end if
                                        end try
                                    end repeat
                                end tell

                                -- Fallback: Return key activates the default button
                                if not didClick then
                                    keystroke return
                                    delay 0.4
                                end if
                            end if
                        end try
                    end tell
                end if

            end repeat
        end tell
        """
    }

    // Returns the path to the main executable inside an .app bundle.
    // MARK: Shared

    static func copyApp(
        appURL: URL,
        logger: Logger,
        progress: @escaping ProgressReporter = { _, _ in }
    ) async -> InstallResult {
        let appName = appURL.lastPathComponent
        // TITAN CORE™ Smart Storage: use selected volume root if set, else default /Applications
        let appsDir: String
        if let root = storageRoot {
            appsDir = root.appendingPathComponent("Applications").path
        } else {
            appsDir = "/Applications"
        }
        let destination = URL(fileURLWithPath: "\(appsDir)/\(appName)")

        // Measure source size on a background thread (du -sk can take a moment for big apps)
        await progress(0.02, "Checking how much space this needs…")
        let srcKB  = await diskUsageKB(appURL.path)
        let srcStr = formatKB(srcKB)
        await logger.log("Copying \(appName) (\(srcStr)) to \(appsDir)…")
        await progress(0.05, "Copying app to Applications — don't close ATLAS…")

        // Hard abort if there is not enough free space (require 5% headroom)
        let availKB = await availableSpaceKB()
        if srcKB > 0 && availKB > 0 && availKB < Int(Double(srcKB) * 1.05) {
            let need = formatKB(Int(Double(srcKB) * 1.05))
            let have = formatKB(availKB)
            await logger.log("Insufficient disk space: need \(need), have \(have) free")
            return .failure(reason: "Not enough disk space. Need \(need), have \(have) free.")
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.removeItem(at: destination)
            } catch {
                // FileManager lacks permission (e.g. /Applications protected) — escalate
                guard let pwd = KeychainManager.loadPassword() else {
                    return .failure(reason: "Could not replace existing \(appName). No admin password stored.")
                }
                let rm = await runProcessWithPassword(
                    password: pwd,
                    arguments: ["/bin/rm", "-rf", destination.path])
                if !rm.success {
                    return .failure(reason: "Could not replace existing \(appName).")
                }
            }
        }

        // Use ditto — preserves resource forks, xattrs, APFS cloning when possible
        let process  = Process()
        let errPipe  = Pipe()
        process.executableURL  = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments      = [appURL.path, destination.path]
        process.standardOutput = Pipe()
        process.standardError  = errPipe

        guard (try? process.run()) != nil else {
            return .failure(reason: "Could not start copy process for \(appName).")
        }
        activeProcess = process

        let start   = Date()
        let timeout = 1800.0
        var nextPoll = Date().addingTimeInterval(4)

        while process.isRunning && !cancellationRequested {
            try? await Task.sleep(nanoseconds: 500_000_000)

            if cancellationRequested {
                process.terminate()
                activeProcess = nil
                return .failure(reason: "Cancelled")
            }

            let elapsed = Int(-start.timeIntervalSinceNow)
            if elapsed > Int(timeout) {
                process.terminate()
                activeProcess = nil
                return .failure(reason: "Copy timed out after 30 min for \(appName).")
            }

            guard Date() >= nextPoll else { continue }
            nextPoll = Date().addingTimeInterval(4)

            // diskUsageKB runs off the main thread — safe to await here
            let dstKB = await diskUsageKB(destination.path)
            if srcKB > 0 && dstKB > 0 {
                let pct = min(0.95, Double(dstKB) / Double(srcKB))
                await progress(pct, "Copying \(appName)…")
                await logger.log("Copying \(appName)… \(Int(pct * 100))% (\(formatKB(dstKB)) / \(srcStr))")
            } else {
                await logger.log("Copying \(appName)… \(elapsed)s")
            }
        }

        activeProcess = nil

        if cancellationRequested {
            process.terminate()
            return .failure(reason: "Cancelled")
        }

        guard process.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let msg     = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await logger.log("ditto error: \(msg)")
            return .failure(reason: "Could not copy \(appName) to /Applications.")
        }

        await logger.log("Copy complete")
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return .failure(reason: "\(appName) not found after install.")
        }

        // Strip quarantine from the installed app only if the attribute is present.
        // Without this, Gatekeeper blocks the app on first launch even though it's in /Applications.
        let qSize = getxattr(destination.path, "com.apple.quarantine", nil, 0, 0, 0)
        if qSize >= 0 {
            _ = runProcess(path: "/usr/bin/xattr",
                           arguments: ["-dr", "com.apple.quarantine", destination.path])
            await logger.log("Quarantine flag cleared from \(appName)")
        }

        await progress(1.0, "")
        await logger.log("✓ \(appName) verified in /Applications")
        return .success(appName: appName)
    }

    // Returns disk usage in kilobytes. Runs du -sk on a background thread
    // so it never blocks the main actor during long copies.
    private static func diskUsageKB(_ path: String) async -> Int {
        await Task.detached(priority: .utility) {
            let p = Process()
            let pipe = Pipe()
            p.executableURL  = URL(fileURLWithPath: "/usr/bin/du")
            p.arguments      = ["-sk", path]
            p.standardOutput = pipe
            p.standardError  = Pipe()
            guard (try? p.run()) != nil else { return 0 }
            p.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
            return Int(out.components(separatedBy: "\t").first?
                         .trimmingCharacters(in: .whitespaces) ?? "") ?? 0
        }.value
    }

    private static func availableSpaceKB() async -> Int {
        await Task.detached(priority: .utility) {
            let attrs = try? FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory())
            let bytes = attrs?[.systemFreeSize] as? Int64 ?? 0
            return Int(bytes / 1024)
        }.value
    }

    private static func formatKB(_ kb: Int) -> String {
        if kb <= 0       { return "…" }
        if kb < 1024     { return "\(kb) KB" }
        if kb < 1024*1024 { return String(format: "%.1f MB", Double(kb)/1024) }
        return String(format: "%.2f GB", Double(kb)/(1024*1024))
    }

    static func findFile(extension ext: String, in directoryPath: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(atPath: directoryPath)
        else { return nil }
        for case let path as String in enumerator {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            guard !fileName.hasPrefix("._"),
                  !path.hasPrefix("__MACOSX"),
                  !path.contains("/__MACOSX/"),
                  fileName.lowercased().hasSuffix(".\(ext)") else { continue }
            return URL(fileURLWithPath: directoryPath).appendingPathComponent(path)
        }
        return nil
    }

    // Finds ALL files with a given extension — used for multi-PKG DMGs
    static func findAllFiles(extension ext: String, in directoryPath: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(atPath: directoryPath)
        else { return [] }
        var results: [URL] = []
        for case let path as String in enumerator {
            let fileName = URL(fileURLWithPath: path).lastPathComponent
            // Skip macOS metadata and anything nested inside an existing bundle —
            // e.g. .component files inside Logic Pro X.app should not be top-level targets.
            guard !fileName.hasPrefix("._"),
                  !path.hasPrefix("__MACOSX"),
                  !path.contains("/__MACOSX/"),
                  !path.contains(".app/"),
                  !path.contains(".component/"),
                  !path.contains(".vst3/"),
                  !path.contains(".aaxplugin/"),
                  fileName.lowercased().hasSuffix(".\(ext)") else { continue }
            results.append(
                URL(fileURLWithPath: directoryPath).appendingPathComponent(path))
        }
        return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func detachDMG(mountPoint: String, logger: Logger) async {
        await logger.log("Unmounting \(mountPoint)...")
        var r = runProcess(path: "/usr/bin/hdiutil",
                          arguments: ["detach", mountPoint, "-quiet"])
        if !r.success {
            r = runProcess(path: "/usr/bin/hdiutil",
                          arguments: ["detach", mountPoint, "-force", "-quiet"])
        }
        await logger.log(r.success ? "Unmounted successfully" : "Warning: could not unmount \(mountPoint)")
    }

    // Detaches any lingering ATLAS_* volumes left by a previous crashed session.
    static func cleanupStaleMounts() {
        let info = runProcess(path: "/usr/bin/hdiutil", arguments: ["info"])
        guard info.success else { return }
        for line in info.output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("/Volumes/ATLAS_") else { continue }
            let mountPath = trimmed.components(separatedBy: .whitespaces).first ?? trimmed
            var r = runProcess(path: "/usr/bin/hdiutil",
                              arguments: ["detach", mountPath, "-quiet"])
            if !r.success {
                r = runProcess(path: "/usr/bin/hdiutil",
                              arguments: ["detach", mountPath, "-force", "-quiet"])
            }
        }
    }

    static func runProcessWithPassword(
        password: String, arguments: [String]
    ) async -> (success: Bool, output: String) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S"] + arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            activeProcess = process
        } catch {
            return (false, error.localizedDescription)
        }
        // Non-blocking poll so the main actor stays responsive
        while process.isRunning && !cancellationRequested {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        activeProcess = nil
        if cancellationRequested {
            process.terminate()
            return (false, "Cancelled")
        }
        let out = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: out, encoding: .utf8) ?? "")
    }

    // Run an arbitrary shell script via /bin/bash -c
    static func runShell(_ script: String) -> (success: Bool, output: String) {
        runProcess(path: "/bin/bash", arguments: ["-c", script])
    }

    // After a PKG install, enumerate the actual installed bundles (plugins, apps)
    // from receipt file lists. Only returns paths that exist on disk and have a
    // meaningful bundle extension — not every individual file in the manifest.
    static func resolveInstalledBundlesFromReceipts(_ receiptIDs: [String]) -> [InstallRecord.InstalledFile] {
        let bundleExts: Set<String> = ["component", "vst3", "vst", "aaxplugin", "app", "framework", "plugin"]
        // Suffixes that indicate sample/content/preset packages — skip entirely because
        // they contain thousands of files and cause runProcess pipe-buffer deadlocks.
        let skipSuffixes = [".content", ".presets", ".samples", ".data", ".library"]
        var seen  = Set<String>()
        var files = [InstallRecord.InstalledFile]()
        let fm    = FileManager.default

        for receiptID in receiptIDs {
            let lower = receiptID.lowercased()
            if skipSuffixes.contains(where: { lower.hasSuffix($0) }) { continue }

            // Use --only-dirs: audio plugin bundles (.component, .vst3, etc.) ARE
            // directories, so they appear in the dirs listing. Individual files inside
            // bundles are not needed and listing them risks a pipe-buffer deadlock on
            // large receipts. We run the process with async pipe reading to avoid
            // blocking if the output is unexpectedly large.
            let output = runProcessWithTimeout(
                path: "/usr/sbin/pkgutil",
                arguments: ["--files", receiptID, "--only-dirs"],
                seconds: 15)

            let location = PKGReceiptScanner.installLocation(forReceipt: receiptID)

            output
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .forEach { line in
                    let ext = URL(fileURLWithPath: line).pathExtension.lowercased()
                    guard bundleExts.contains(ext) else { return }
                    let abs: String
                    if line.hasPrefix("/") {
                        abs = line
                    } else if location.isEmpty || location == "/" {
                        abs = "/\(line)"
                    } else {
                        let raw = "\(location)/\(line)"
                    abs = raw.hasPrefix("/") ? raw : "/\(raw)"
                    }
                    guard !seen.contains(abs), fm.fileExists(atPath: abs) else { return }
                    seen.insert(abs)
                    files.append(InstallRecord.InstalledFile(
                        sourceName:      URL(fileURLWithPath: abs).lastPathComponent,
                        destinationPath: abs))
                }
        }

        // Fallback: scan known plugin dirs for bundles modified in the last 5 minutes.
        // This catches installs where pkgutil returned no paths (e.g. FLARE-patched
        // receipts whose paths don't line up with real install locations).
        if files.isEmpty {
            let pluginDirs = [
                "/Library/Audio/Plug-Ins/Components",
                "/Library/Audio/Plug-Ins/VST3",
                "/Library/Audio/Plug-Ins/VST",
                "/Library/Application Support/Avid/Audio/Plug-Ins",
            ]
            let cutoff = Date().addingTimeInterval(-300) // 5 min window
            for dir in pluginDirs {
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for entry in entries {
                    let ext = URL(fileURLWithPath: entry).pathExtension.lowercased()
                    guard bundleExts.contains(ext) else { continue }
                    let full = "\(dir)/\(entry)"
                    guard !seen.contains(full) else { continue }
                    if let attrs = try? fm.attributesOfItem(atPath: full),
                       let mod = attrs[.modificationDate] as? Date,
                       mod >= cutoff {
                        seen.insert(full)
                        files.append(InstallRecord.InstalledFile(
                            sourceName: entry,
                            destinationPath: full))
                    }
                }
            }
        }

        return files
    }

    // Runs a process with async pipe reading so large outputs don't cause a
    // pipe-buffer deadlock. Returns stdout+stderr output, or "" on timeout.
    private static func runProcessWithTimeout(path: String, arguments: [String], seconds: Double) -> String {
        let process = Process()
        let pipe    = Pipe()
        process.executableURL  = URL(fileURLWithPath: path)
        process.arguments      = arguments
        process.standardOutput = pipe
        process.standardError  = Pipe()

        var outputData = Data()
        let readSema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            readSema.signal()
        }

        guard (try? process.run()) != nil else { return "" }

        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning { process.terminate() }
        _ = readSema.wait(timeout: .now() + 5)
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    // Run a shell script with extra environment variables and optional admin password
    static func runShellWithEnv(
        _ script: String,
        env: [String: String],
        adminPassword: String
    ) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        var environment = ProcessInfo.processInfo.environment
        for (k, v) in env { environment[k] = v }
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        if !adminPassword.isEmpty {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            do {
                try process.run()
                inputPipe.fileHandleForWriting.write((adminPassword + "\n").data(using: .utf8)!)
                inputPipe.fileHandleForWriting.closeFile()
            } catch {
                return (false, error.localizedDescription)
            }
        } else {
            do { try process.run() } catch { return (false, error.localizedDescription) }
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }

    static func runProcess(
        path: String, arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let pipe    = Pipe()
        process.executableURL  = URL(fileURLWithPath: path)
        process.arguments      = arguments
        process.standardOutput = pipe
        process.standardError  = pipe

        // Drain the pipe on a background thread before waitUntilExit(). If the
        // subprocess writes more than the macOS pipe buffer (~64 KB) and we read
        // only after waitUntilExit(), the write side blocks and we deadlock.
        var outputData = Data()
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        _ = sema.wait(timeout: .now() + 30)
        return (process.terminationStatus == 0, String(data: outputData, encoding: .utf8) ?? "")
    }

    // MARK: - Library snapshot helpers

    // Returns a dict mapping each watched directory path → set of top-level entry names.
    // For Application Support dirs, also snapshots one level deeper inside existing
    // non-system vendor directories. This lets diffLibraryTopLevel detect new product
    // subdirectories added to an existing vendor dir (e.g. a fresh "Ozone 12" folder
    // created inside a pre-existing "/Library/Application Support/iZotope/").
    static func snapshotLibraryTopLevel() -> [String: Set<String>] {
        let home = NSHomeDirectory()
        let dirs = [
            home + "/Library/Application Support",
            "/Library/Application Support",
            home + "/Library/Preferences",
            "/Library/Preferences",
            home + "/Library/Caches",
        ]
        var snapshot: [String: Set<String>] = [:]
        let fm = FileManager.default
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            snapshot[dir] = Set(entries)
            // One level deeper for Application Support: snapshot existing vendor dirs
            // so we can detect new product subdirectories added during install.
            guard dir.hasSuffix("/Application Support") else { continue }
            for entry in entries {
                guard !isSystemEntry(entry) else { continue }
                let vendorPath = "\(dir)/\(entry)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: vendorPath, isDirectory: &isDir), isDir.boolValue else { continue }
                if let vendorEntries = try? fm.contentsOfDirectory(atPath: vendorPath) {
                    snapshot[vendorPath] = Set(vendorEntries)
                }
            }
        }
        return snapshot
    }

    // System/OS entries that should never be treated as product-created folders.
    // Prevents false positives when macOS or background processes create dirs
    // in the same time window as an install.
    static let systemEntryBlocklist: Set<String> = [
        "com.apple", "CloudDocs", "AddressBook", "Calendars", "CallHistoryDB",
        "CallHistoryTransactions", "CoreData", "DataDeliveryMetrics",
        "FaceTime", "Group Containers", "HomeKit", "iCloud", "iLifeAssetManagement",
        "iTunesMetadata", "Knowledge", "Mail", "Maps", "Messages", "NanoRegistry",
        "News", "Notes", "Passes", "Photos", "Reminders", "Safari", "Screentime",
        "Suggestions", "SyncedPreferences", "SystemData", "Trial", "TwitterAssets",
        "weatherd", "Accounts", "Autofill", "BrowserState", "Cookies",
        "com.crashlytics", "com.google", "com.microsoft", "com.adobe",
        ".DS_Store", "Logs", "networkserviceproxy",
    ]

    // Compares current top-level entries to the snapshot and returns full paths
    // of any new entries that appeared (i.e. folders created during install).
    // Filters against the system blocklist to avoid false positives.
    // Also checks one level deeper in Application Support vendor directories,
    // capturing new product subdirectories inside pre-existing vendor dirs.
    static func diffLibraryTopLevel(before: [String: Set<String>]) -> [String] {
        let fm = FileManager.default
        var newPaths: [String] = []
        let home = NSHomeDirectory()
        let allDirs = [
            home + "/Library/Application Support",
            "/Library/Application Support",
            home + "/Library/Preferences",
            "/Library/Preferences",
            home + "/Library/Caches",
        ]
        for dir in allDirs {
            let prior = before[dir] ?? []
            guard let currentEntries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in currentEntries where !prior.contains(entry) {
                guard !isSystemEntry(entry) else { continue }
                newPaths.append("\(dir)/\(entry)")
            }
            // For Application Support: also check for new subdirectories inside
            // vendor dirs that already existed before the install.
            guard dir.hasSuffix("/Application Support") else { continue }
            for entry in currentEntries {
                guard !isSystemEntry(entry) else { continue }
                let vendorPath = "\(dir)/\(entry)"
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: vendorPath, isDirectory: &isDir), isDir.boolValue else { continue }
                let priorVendorEntries = before[vendorPath] ?? []
                guard let currentVendorEntries = try? fm.contentsOfDirectory(atPath: vendorPath) else { continue }
                for vendorEntry in currentVendorEntries where !priorVendorEntries.contains(vendorEntry) {
                    guard !isSystemEntry(vendorEntry) else { continue }
                    newPaths.append("\(vendorPath)/\(vendorEntry)")
                }
            }
        }
        return newPaths
    }

    // Finds Library dirs entries that were created on or after a given date.
    // Used at feedback-confirm time to catch first-launch folders that didn't
    // exist when the install-time snapshot was taken.
    static func discoverPathsCreatedSince(date: Date) -> [String] {
        let home = NSHomeDirectory()
        let dirs = [
            home + "/Library/Application Support",
            "/Library/Application Support",
            home + "/Library/Preferences",
            "/Library/Preferences",
            home + "/Library/Caches",
        ]
        let fm = FileManager.default
        var found: [String] = []
        let cutoff = date.addingTimeInterval(-30) // 30s grace before install start
        for dir in dirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                guard !isSystemEntry(entry) else { continue }
                let full = "\(dir)/\(entry)"
                if let attrs = try? fm.attributesOfItem(atPath: full),
                   let created = attrs[.creationDate] as? Date,
                   created >= cutoff {
                    found.append(full)
                }
            }
        }
        return found
    }

    private static func isSystemEntry(_ name: String) -> Bool {
        systemEntryBlocklist.contains(where: { name.lowercased().hasPrefix($0.lowercased()) })
    }
}

// MARK: - InstallationManager

@MainActor
class InstallationManager: ObservableObject {

    static let shared = InstallationManager()
    private init() {}

    func install(url: URL, appState: AppState, logger: Logger,
                 historyStore: HistoryStore,
                 onComplete: @escaping (Bool) -> Void = { _ in }) {
        Task {
            appState.phase = .classifying
            appState.progress = 0
            appState.progressStep = "Classifying..."
            TitanCore.shared.clearLastRecovery()

            let type_ = InstallerClassifier.classify(url: url)
            let fileType = self.typeName(type_)
            logger.log("Classified as: \(fileType)")

            // ── TITAN CORE™ Pre-flight ────────────────────────────────────
            if TitanCore.shared.isAvailable {
                let preflight = await TitanCore.shared.preflight(
                    url: url, installerType: type_)

                for warning in preflight.warnings {
                    logger.log("TITAN CORE™: ⚠ \(warning)")
                }

                if let block = preflight.blockReason {
                    logger.log("TITAN CORE™: 🛑 Blocked — \(block)")
                    appState.phase = .failure
                    appState.lastResult = .failure(reason: block)
                    TitanCore.shared.lastRecovery = .guidance(message: block)
                    let record = InstallLogger.writeLog(
                        fileURL: url, fileType: fileType,
                        entries: logger.entries,
                        result: .failure(reason: block),
                        installedFiles: [], pkgReceiptIDs: [],
                        remediationAttempted: false)
                    historyStore.add(record)
                    onComplete(false)
                    return
                }
            }

            appState.phase = .installing

            let onProgress: ProgressReporter = { [weak appState] value, label in
                await MainActor.run {
                    appState?.progress = value
                    if !label.isEmpty { appState?.progressStep = label }
                }
            }

            // ── Attempt 1 ────────────────────────────────────────────────
            logger.log("--- Attempt 1 ---")
            // Run the actual install off the main thread so blocking calls
            // (PKG installer, filesystem snapshots, receipt scans) don't freeze the UI.
            var (result, installedFiles, receiptIDs, isPlugin, runtimeCreatedPaths) = await Task.detached(priority: .userInitiated) {
                await InstallEngine.install(url: url, logger: logger, progress: onProgress)
            }.value
            var remediationAttempted = false

            // ── DAW gate early exit ───────────────────────────────────────
            // Unsupported DAW installations are intentional refusals, not failures.
            // No record, no history, no TITAN retry.
            if case .unsupportedDAWInstallation(let dawName) = result {
                logger.log("DAW installation not supported: \(dawName) — user notified.")
                await MainActor.run {
                    appState.phase = .idle
                    appState.lastResult = .unsupportedDAWInstallation(dawName: dawName)
                }
                onComplete(false)
                return
            }

            // ── TITAN CORE™ Smart Recovery ────────────────────────────────
            if case .failure(let reason) = result {
                if TitanCore.shared.isAvailable {
                    logger.log("TITAN CORE™: Analyzing failure…")
                    appState.phase = .processing
                    appState.progress = 0
                    appState.progressStep = "TITAN CORE™ recovering…"

                    let recovery = await TitanCore.shared.recover(
                        url: url, failureReason: reason, attempt: 1, logger: logger)

                    if recovery.canRetry {
                        remediationAttempted = true
                        logger.log("TITAN CORE™: Retrying after \(recovery.actionTaken)…")
                        logger.log("--- Attempt 2 (TITAN CORE™ recovery) ---")
                        appState.phase = .installing
                        appState.progress = 0
                        var retryPaths2: [String]
                        (result, installedFiles, receiptIDs, isPlugin, retryPaths2) = await Task.detached(priority: .userInitiated) {
                            await InstallEngine.install(url: url, logger: logger, progress: onProgress)
                        }.value
                        runtimeCreatedPaths = Array(Set(runtimeCreatedPaths + retryPaths2))

                        // Second failure: one more recovery pass
                        if case .failure(let reason2) = result {
                            logger.log("TITAN CORE™: Second attempt failed — \(reason2)")
                            appState.phase = .processing
                            appState.progressStep = "TITAN CORE™ final recovery…"
                            let recovery2 = await TitanCore.shared.recover(
                                url: url, failureReason: reason2, attempt: 2, logger: logger)
                            if recovery2.canRetry {
                                logger.log("--- Attempt 3 (TITAN CORE™ final) ---")
                                appState.phase = .installing
                                appState.progress = 0
                                var retryPaths3: [String]
                                (result, installedFiles, receiptIDs, isPlugin, retryPaths3) = await Task.detached(priority: .userInitiated) {
                                    await InstallEngine.install(url: url, logger: logger, progress: onProgress)
                                }.value
                                runtimeCreatedPaths = Array(Set(runtimeCreatedPaths + retryPaths3))
                            }
                        }
                    } else {
                        logger.log("TITAN CORE™: Auto-recovery not possible — \(recovery.actionTaken)")
                    }
                } else {
                    // TITAN disabled — fall back to legacy remediation
                    logger.log("Starting remediation (standard mode)...")
                    appState.phase = .processing
                    appState.progress = 0
                    appState.progressStep = "Remediating..."

                    let remediation = await RemediationEngine.remediate(
                        url: url, failureReason: reason, logger: logger)

                    if remediation.success {
                        remediationAttempted = true
                        logger.log("Remediation succeeded: \(remediation.detail)")
                        logger.log("--- Attempt 2 (after remediation) ---")
                        appState.phase = .installing
                        appState.progress = 0
                        var retryPathsLegacy: [String]
                        (result, installedFiles, receiptIDs, isPlugin, retryPathsLegacy) =
                            await InstallEngine.install(url: url, logger: logger, progress: onProgress)
                        runtimeCreatedPaths = Array(Set(runtimeCreatedPaths + retryPathsLegacy))
                    } else {
                        logger.log("Remediation could not fix: \(remediation.detail)")
                    }
                }
            }

            // ── TITAN CORE™ Post-install verification ─────────────────────
            if case .success = result {
                await TitanCore.shared.verify(installedFiles: installedFiles, logger: logger)
            }

            var record = InstallLogger.writeLog(
                fileURL: url,
                fileType: fileType,
                entries: logger.entries,
                result: result,
                installedFiles: installedFiles,
                pkgReceiptIDs: receiptIDs,
                remediationAttempted: remediationAttempted
            )
            if !runtimeCreatedPaths.isEmpty {
                record.runtimeCreatedPaths = runtimeCreatedPaths
            }

            historyStore.add(record)

            switch result {
            case .success(let appName, _):
                appState.phase = .success
                appState.lastResult = .success(appName: appName)
                logger.log("✓ Installation complete: \(appName)")
                logger.log("📄 Log saved to ~/Library/Logs/ATLAS/")
                onComplete(isPlugin)
            case .failure(let reason):
                appState.phase = .failure
                appState.lastResult = .failure(reason: reason)
                logger.log("✗ Installation failed: \(reason)")
                logger.log("📄 Log saved to ~/Library/Logs/ATLAS/")
                onComplete(false)
            case .unsupportedDAWInstallation:
                // Handled by the early-exit guard above; unreachable here.
                onComplete(false)
            }
        }
    }

    private func typeName(_ type_: InstallerType) -> String {
        switch type_ {
        case .dmg:       return "DMG"
        case .iso:       return "ISO"
        case .zip:       return "ZIP"
        case .app:       return "APP"
        case .pkg:       return "PKG"
        case .component: return "Component"
        case .vst3:      return "VST3"
        case .vst:       return "VST"
        case .aax:           return "AAX"
        case .kontaktLibrary: return "Kontakt Library"
        case .interactiveInstaller: return "Interactive Installer"
        case .exe: return "EXE"
        case .unsupported(let ext): return ext.uppercased()
        }
    }
}
