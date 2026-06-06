import Foundation

typealias ProgressReporter = (Double, String) async -> Void

// MARK: - InstallEngine

struct InstallEngine {

    // MARK: - Cancellation

    static var activeProcess: Process? = nil
    static var cancellationRequested = false
    // TITAN CORE™ Smart Storage: set before install to route files to a custom volume root.
    // nil = default system paths (/Applications, /Library/…). Cleared after install.
    static var storageRoot: URL? = nil

    // MARK: - Global auth-dialog watcher

    // Runs for the full duration of any install. Catches every "wants to make changes"
    // / "requires your password" dialog from authorizationhost (macOS 12+) or
    // SecurityAgent (macOS 11-) and fills + dismisses it automatically.
    static func startAuthWatcher(password: String) -> Process {
        let escaped = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "System Events"
            repeat 7200 times
                delay 0.4
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
                                                    set value of (last item of allFields) to "\(escaped)"
                                                else
                                                    set value of (first item of allFields) to "\(escaped)"
                                                end if
                                                delay 0.2
                                                try
                                                    click button "OK" of w
                                                on error
                                                    try
                                                        click button "Allow" of w
                                                    on error
                                                        try
                                                            click button "Unlock" of w
                                                        on error
                                                            keystroke return
                                                        end try
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
        return p
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
                isPlugin: Bool) {
        // Start global auth-dialog watcher for the full duration of this install.
        // Handles every "wants to make changes" / "requires password" popup automatically.
        let authWatcher: Process?
        if let pwd = KeychainManager.loadPassword() {
            authWatcher = startAuthWatcher(password: pwd)
        } else {
            authWatcher = nil
        }
        defer { authWatcher?.terminate() }

        let type_ = InstallerClassifier.classify(url: url)
        switch type_ {
        case .dmg:                  return await installDMG(url: url, logger: logger, progress: progress)
        case .iso:                  return await installDMG(url: url, logger: logger, progress: progress)
        case .zip:                  return await installZIP(url: url, logger: logger, progress: progress)
        case .app:                  return await installAPP(url: url, logger: logger, progress: progress)
        case .pkg:
            let (result, files, receipts) = await installPKG(
                url: url, installerName: url.lastPathComponent,
                logger: logger, progress: progress)
            return (result, files, receipts, false)
        case .component, .vst3, .vst, .aax:
            await progress(0.2, "Placing plugin in your library…")
            let (result, files) = await PluginInstallEngine.installSinglePlugin(
                url: url, logger: logger)
            await progress(1.0, "")
            return (result, files, [], true)
        case .kontaktLibrary:
            let result = await KontaktInstaller.install(libraryFolder: url, logger: logger, progress: progress)
            return (result, [], [], false)
        case .unsupported(let ext):
            await logger.log("Unsupported file type: .\(ext)")
            return (.failure(reason: "Unsupported file type: .\(ext)"), [], [], false)
        }
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
        await progress(0.03, "Opening the disk image…")

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

        if !mountResult.success {
            let msg = mountResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            await logger.log("Failed to mount: \(msg)")
            return (.failure(reason: "Could not mount file: \(msg)"), [], [], false)
        }

        await logger.log("Mounted at \(mountPoint)")
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
                        let ok = await runPatchApp(step.url, logger: logger)
                        if ok {
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
        guard let password = KeychainManager.loadPassword() else {
            await logger.log("  ⚠ No password stored — cannot run script")
            return
        }
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ATLAS_exec_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            // Copy the script and small siblings so relative imports work
            let parent = url.deletingLastPathComponent()
            let siblings = (try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for sibling in siblings {
                let rv    = try? sibling.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let isDir = rv?.isDirectory ?? false
                let size  = rv?.fileSize ?? 0
                if !isDir && size <= 10 * 1024 * 1024 {
                    try? FileManager.default.copyItem(
                        at: sibling,
                        to: tmpDir.appendingPathComponent(sibling.lastPathComponent))
                }
            }
            let execURL = tmpDir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: execURL.path) {
                try FileManager.default.copyItem(at: url, to: execURL)
            }
            _ = runProcess(path: "/usr/bin/xattr", arguments: ["-cr", execURL.path])
            _ = runProcess(path: "/bin/chmod",     arguments: ["+x",  execURL.path])
            let sysLang = Locale.current.languageCode ?? "en"
        let homeStr = NSHomeDirectory().replacingOccurrences(of: "'", with: "'\\''")
            let r = runShellWithEnv(
                "env TERM=xterm-256color HOME='\(homeStr)' '\(execURL.path)'",
                env: ["SYS_LANG": sysLang, "SUDO_ASKPASS": "", "ATLAS_PASSWORD": password,
                      "TERM": "xterm-256color", "HOME": NSHomeDirectory()],
                adminPassword: password
            )
            try? FileManager.default.removeItem(at: tmpDir)
            if r.success {
                await logger.log("  ✓ Script completed: \(url.lastPathComponent)")
            } else {
                await logger.log("  ⚠ Script exited with error: \(r.output.prefix(120))")
            }
        } catch {
            await logger.log("  ⚠ Could not prepare script: \(error.localizedDescription)")
        }
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

        guard let password = KeychainManager.loadPassword() else {
            return (.failure(reason: "No password stored."), [], [])
        }

        await progress(0.05, "Saving a restore point in case something goes wrong…")
        await logger.log("Taking pre-install snapshot...")
        let beforeReceipts = PKGReceiptScanner.snapshotReceipts()
        let beforeFS = FilesystemSnapshot.take()
        let installStart = Date()  // timestamp for receipt validation

        await progress(0.12, "Running the package installer — this may take a moment…")
        await logger.log("Running installer...")
        let result = await runProcessWithPassword(
            password: password,
            arguments: ["/usr/sbin/installer", "-pkg", url.path, "-target", "/"]
        )

        if !result.success {
            await logger.log("PKG installer failed: \(result.output)")
            return (.failure(reason: "PKG installation failed. \(result.output)"), [], [])
        }

        await logger.log("PKG installer completed")
        await progress(0.82, "Checking that everything installed correctly…")
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // findNewReceipts now validates receipt file timestamps against installStart,
        // preventing background processes from polluting the receipt list.
        var newReceiptIDs = PKGReceiptScanner.findNewReceipts(before: beforeReceipts, since: installStart)
        if newReceiptIDs.isEmpty {
            newReceiptIDs = PKGReceiptScanner.findReceiptsByName(installerName)
        }

        for id in newReceiptIDs { await logger.log("  Receipt: \(id)") }

        await progress(0.90, "Discovering what files were added to your Mac…")
        let afterFS = FilesystemSnapshot.take()
        let changedPaths = FilesystemSnapshot.diff(before: beforeFS, after: afterFS)
        await logger.log("Changes detected: \(changedPaths.count) items")

        if !changedPaths.isEmpty {
            let dirs = Set(changedPaths.map {
                URL(fileURLWithPath: $0).deletingLastPathComponent().path
            }).sorted()
            await logger.log("  Locations: \(dirs.joined(separator: ", "))")
        }

        // Use filesystem snapshot for file tracking. Receipt-based rollback
        // (RollbackEngine Step 1) already re-queries pkgutil at rollback time,
        // so enumerating all receipt files here would be redundant and very
        // slow for large packages (e.g. Serum has thousands of preset files).
        let installedFiles = FilesystemSnapshot.buildInstalledFiles(
            changedPaths: changedPaths)

        await logger.log("Total tracked: \(installedFiles.count) item(s)")
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

        await progress(0.05, "Unzipping the archive…")
        await logger.log("Extracting \(url.lastPathComponent)...")

        let unzipResult = runProcess(
            path: "/usr/bin/unzip",
            arguments: ["-q", url.path, "-d", tempDir.path]
        )

        if !unzipResult.success {
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
                        let ok = await runPatchApp(step.url, logger: logger)
                        if !ok { lastResult = .failure(reason: "Patch failed: \(step.url.lastPathComponent)") }
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
        let appName = url.lastPathComponent
        let destPath = "/Applications/\(appName)"
        let result = await copyApp(appURL: url, logger: logger, progress: progress)
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

    // MARK: - Patch app runner

    // Runs a .app patch fully autonomously:
    //  1. Copy to temp; strip quarantine + ad-hoc codesign
    //  2. Try --mode unattended (InstallBuilder silent install — no window, no interaction)
    //  3. Fall back to GUI mode: watcher clicks through every wizard step automatically
    static func runPatchApp(_ appURL: URL, logger: Logger) async -> Bool {
        let appName = appURL.lastPathComponent

        guard let password = KeychainManager.loadPassword() else {
            await logger.log("No password stored — cannot run patch autonomously")
            return false
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLAS_PATCH_\(UUID().uuidString.prefix(8))")
        let tempApp = tempDir.appendingPathComponent(appName)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: appURL, to: tempApp)
        } catch {
            await logger.log("Could not copy patch to temp: \(error.localizedDescription)")
            return false
        }

        _ = await runProcessWithPassword(password: password,
            arguments: ["/usr/bin/xattr", "-cr", tempApp.path])
        _ = runProcess(path: "/usr/bin/codesign",
            arguments: ["--force", "--deep", "--sign", "-", tempApp.path])

        // ── Path 1: Silent install via --mode unattended ───────────────────────
        // InstallBuilder apps (Xfer Records uses this) support headless install
        // with this flag — no window appears at all, patch is applied silently.
        if let binaryPath = findMainBinary(in: tempApp) {
            await logger.log("Trying unattended install: \(appName)")
            let silent = await runWithTimeout(
                password: password,
                executablePath: binaryPath,
                arguments: ["--mode", "unattended"],
                seconds: 90)
            if silent.success && !silent.timedOut {
                try? FileManager.default.removeItem(at: tempDir)
                await logger.log("✓ Patch applied silently: \(appName)")
                return true
            }
            if silent.timedOut {
                _ = runProcess(path: "/usr/bin/killall",
                              arguments: ["-9", patchProcessName(for: tempApp)])
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await logger.log("Unattended mode unavailable — switching to GUI automation")
        }

        // ── Path 2: GUI wizard — watcher auto-clicks every step ───────────────
        let procName = patchProcessName(for: tempApp)
        let escapedPwd = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        _ = runProcess(path: "/usr/bin/osascript", arguments: ["-e",
            "do shell script \"echo ok\" with administrator privileges password \"\(escapedPwd)\" without prompting user"])

        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        watcher.arguments = ["-e", buildWatchScript(processName: procName, password: escapedPwd)]
        watcher.standardOutput = Pipe()
        watcher.standardError = Pipe()
        try? watcher.run()

        await logger.log("Running patch with GUI automation: \(appName)")
        // -g: no focus steal; -W: wait until patcher exits
        let result = runProcess(path: "/usr/bin/open",
                               arguments: ["-W", "-g", tempApp.path])
        watcher.terminate()
        try? FileManager.default.removeItem(at: tempDir)

        if result.success {
            await logger.log("✓ Patch applied: \(appName)")
        } else {
            await logger.log("✗ Patch failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result.success
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
    private static func findMainBinary(in appURL: URL) -> String? {
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: infoPlist),
           let name = dict["CFBundleExecutable"] as? String {
            let path = appURL.appendingPathComponent("Contents/MacOS/\(name)").path
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        // Fallback: any file in Contents/MacOS
        let macOS = appURL.appendingPathComponent("Contents/MacOS")
        if let files = try? FileManager.default.contentsOfDirectory(atPath: macOS.path),
           let first = files.first(where: { !$0.hasPrefix(".") }) {
            return macOS.appendingPathComponent(first).path
        }
        return nil
    }

    // Runs an executable with sudo and a hard timeout. Returns (success, output, timedOut).
    private static func runWithTimeout(
        password: String,
        executablePath: String,
        arguments: [String],
        seconds: Double
    ) async -> (success: Bool, output: String, timedOut: Bool) {
        let process = Process()
        let inputPipe  = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S", executablePath] + arguments
        process.standardInput  = inputPipe
        process.standardOutput = outputPipe
        process.standardError  = outputPipe
        do { try process.run() } catch { return (false, error.localizedDescription, false) }
        inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()
        activeProcess = process

        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline && !cancellationRequested {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        activeProcess = nil
        if process.isRunning {
            process.terminate()
            return (false, "", !cancellationRequested)
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0,
                String(data: data, encoding: .utf8) ?? "",
                false)
    }

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
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
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
            let fileType = typeName(type_)
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
            var (result, installedFiles, receiptIDs, isPlugin) =
                await InstallEngine.install(url: url, logger: logger, progress: onProgress)
            var remediationAttempted = false

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
                        (result, installedFiles, receiptIDs, isPlugin) =
                            await InstallEngine.install(url: url, logger: logger, progress: onProgress)

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
                                (result, installedFiles, receiptIDs, isPlugin) =
                                    await InstallEngine.install(url: url, logger: logger, progress: onProgress)
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
                        (result, installedFiles, receiptIDs, isPlugin) =
                            await InstallEngine.install(url: url, logger: logger, progress: onProgress)
                    } else {
                        logger.log("Remediation could not fix: \(remediation.detail)")
                    }
                }
            }

            // ── TITAN CORE™ Post-install verification ─────────────────────
            if case .success = result {
                await TitanCore.shared.verify(installedFiles: installedFiles, logger: logger)
            }

            let record = InstallLogger.writeLog(
                fileURL: url,
                fileType: fileType,
                entries: logger.entries,
                result: result,
                installedFiles: installedFiles,
                pkgReceiptIDs: receiptIDs,
                remediationAttempted: remediationAttempted
            )

            historyStore.add(record)

            switch result {
            case .success(let appName):
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
        case .unsupported(let ext): return ext.uppercased()
        }
    }
}
