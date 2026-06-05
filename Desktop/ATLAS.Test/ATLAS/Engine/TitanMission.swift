import Foundation
import AppKit

// MARK: - Mission step model

struct TitanMissionStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let action: TitanAction
    var status: Status = .pending
    var resultNote: String = ""

    enum Status { case pending, running, done, failed, skipped }
}

// What TITAN CORE™ actually executes for each step
enum TitanAction {
    // ── Existing actions ────────────────────────────────────────────────────
    case xcodeCommandLineTools
    case installPkg(url: URL)
    case runScript(url: URL)
    case runBinary(url: URL)
    case editHosts(domain: String)
    case shellCommand(String)
    case informUser(String)          // dialog-only, no execution

    // ── Desktop UI automation (MacUIAutomator) ───────────────────────────────
    /// Launch an .app at the given URL and wait for it to finish loading.
    case launchApp(url: URL)
    /// Wait for a window belonging to appName to appear (optional title filter).
    case waitForAppWindow(appName: String, titleHint: String?, timeout: TimeInterval)
    /// Click a button (by label) inside appName's front window.
    case clickAppButton(appName: String, label: String, timeout: TimeInterval)
    /// Select all items in appName (tries "Select All" button, falls back to checkboxes).
    case selectAllInApp(appName: String, timeout: TimeInterval)
    /// Wait for appName to signal completion (progress bar full or done button appears).
    case waitForAppCompletion(appName: String, timeout: TimeInterval)
    /// Quit an app gracefully.
    case quitApp(appName: String)
    /// Move an .app bundle from /Applications to Trash.
    case moveAppToTrash(appName: String)

    // ── File cleanup ─────────────────────────────────────────────────────────
    /// Move a specific path (file or folder) to Trash.
    case trashPath(String)
}

// MARK: - Mission orchestrator

@MainActor
final class TitanMission: ObservableObject {

    @Published var steps: [TitanMissionStep] = []
    @Published var isRunning = false
    @Published var isComplete = false
    @Published var currentNote = ""

    // Source context
    let mountPoint: String
    let sourceURL: URL

    // Filled in from scan
    private(set) var plan: InstallPlan?
    private(set) var scanResult: InstallIntelligence.TitanScanResult?

    // Rollback tracking — populated during execute() for PRO uninstall
    private(set) var installedPKGReceipts: [String] = []
    private(set) var installedFiles: [InstallRecord.InstalledFile] = []
    private(set) var addedHostsEntries: [String] = []

    init(mountPoint: String, sourceURL: URL) {
        self.mountPoint = mountPoint
        self.sourceURL  = sourceURL
    }

    // MARK: - Build the mission from scan + plan

    func buildMission(plan: InstallPlan, scan: InstallIntelligence.TitanScanResult) {
        self.plan       = plan
        self.scanResult = scan

        var newSteps: [TitanMissionStep] = []
        var handledPaths = Set<String>()   // tracks URLs already added as steps

        // ── Step 0: Xcode Command Line Tools ─────────────────────────────
        if scan.needsXcodeTools || (plan.instructions?.mentionsXcodeTools == true) {
            newSteps.append(TitanMissionStep(
                icon: "hammer.fill",
                title: L(.titanStepXcodeTools),
                detail: "xcode-select --install",
                action: .xcodeCommandLineTools
            ))
        }

        // ── Steps from the ordered install plan (PKGs, APPs, plugins) ────
        let plannedURLs = Set(plan.orderedSteps.map { $0.url.path })
        plannedURLs.forEach { handledPaths.insert($0) }

        for step in plan.orderedSteps {
            switch step.type {
            case .installer:
                newSteps.append(TitanMissionStep(
                    icon: "shippingbox.fill",
                    title: "\(L(.titanStepInstallPkg)): \(step.url.lastPathComponent)",
                    detail: step.note,
                    action: .installPkg(url: step.url)
                ))
            case .patch, .app, .managedInstall, .plugin:
                newSteps.append(TitanMissionStep(
                    icon: step.icon,
                    title: "\(step.label): \(step.url.lastPathComponent)",
                    detail: step.note,
                    action: .installPkg(url: step.url)
                ))
            case .manual:
                newSteps.append(TitanMissionStep(
                    icon: "hand.point.right.fill",
                    title: step.url.lastPathComponent,
                    detail: step.note,
                    action: .informUser(step.note)
                ))
            }
        }

        // ── Instruction-guided steps (in the order the instructions say) ─
        //
        // ParsedInstructions.scriptsToRun / binariesToRun hold name fragments
        // extracted from "Run the Block server file", "Run the Keyfilemaker file", etc.
        // We find actual files in the mounted directory by fuzzy name matching and
        // insert them in instruction order — BEFORE falling back to the blind scan.
        // Hosts entries are also inserted here so they land in the right position
        // relative to the other instruction-guided steps.

        if let instr = plan.instructions {
            // Combine into one ordered list (instructions mention them in sequence)
            var seen = Set<String>()
            let mentionedNames = (instr.scriptsToRun + instr.binariesToRun)
                .filter { seen.insert($0).inserted }   // preserve order, deduplicate

            if !mentionedNames.isEmpty {
                let matches = InstallIntelligence.findFilesByName(
                    names: mentionedNames, in: mountPoint)

                let scriptPaths = Set(scan.scripts.map { $0.path })

                var instrHandledBundles = Set<String>()
                for (_, url) in matches {
                    guard !handledPaths.contains(url.path) else { continue }
                    let ext = url.pathExtension.lowercased()
                    // Skip non-executable file types
                    guard !["pkg", "mpkg", "app", "component", "vst3",
                            "vst", "aaxplugin"].contains(ext) else { continue }

                    handledPaths.insert(url.path)

                    // Files inside a .app bundle: run the whole bundle as a patch
                    if let appBundle = parentAppBundle(of: url) {
                        let ap = appBundle.path
                        guard !handledPaths.contains(ap), !instrHandledBundles.contains(ap) else { continue }
                        instrHandledBundles.insert(ap)
                        newSteps.append(TitanMissionStep(
                            icon: "app.badge.checkmark",
                            title: "Apply patch: \(appBundle.deletingPathExtension().lastPathComponent)",
                            detail: "Runs per installation instructions",
                            action: .runBinary(url: url)
                        ))
                        continue
                    }

                    // Determine action: script (shebang, .command, .sh) or binary
                    let isScript = scriptPaths.contains(url.path) ||
                                   ["sh", "command", "bash", "zsh"].contains(ext)

                    newSteps.append(TitanMissionStep(
                        icon: isScript ? "terminal.fill" : "gearshape.2.fill",
                        title: (isScript ? L(.titanStepRunScript) : L(.titanStepRunBinary))
                               + ": \(url.lastPathComponent)",
                        detail: "Runs per installation instructions",
                        action: isScript ? .runScript(url: url) : .runBinary(url: url)
                    ))
                }
            }

            // Insert hosts entries here — instruction-ordered position (after server-
            // blocking scripts, which is what instructions typically specify).
            for domain in scan.hostsEntries {
                newSteps.append(TitanMissionStep(
                    icon: "network.badge.shield.half.filled",
                    title: L(.titanStepEditHosts),
                    detail: "127.0.0.1 \(domain)",
                    action: .editHosts(domain: domain)
                ))
            }
        }

        // ── Remaining scan-detected scripts (not already added) ───────────
        var handledAppBundles = Set<String>()
        for script in scan.scripts where !handledPaths.contains(script.path) {
            handledPaths.insert(script.path)

            // If the script lives inside a .app bundle, treat the whole bundle as the step.
            if let appBundle = parentAppBundle(of: script) {
                let appPath = appBundle.path
                guard !handledPaths.contains(appPath), !handledAppBundles.contains(appPath) else { continue }
                handledAppBundles.insert(appPath)
                newSteps.append(TitanMissionStep(
                    icon: "app.badge.checkmark",
                    title: "Apply patch: \(appBundle.deletingPathExtension().lastPathComponent)",
                    detail: "Patch application — runs in-place with admin rights",
                    action: .runBinary(url: script)
                ))
                continue
            }

            newSteps.append(TitanMissionStep(
                icon: "terminal.fill",
                title: "\(L(.titanStepRunScript)): \(script.lastPathComponent)",
                detail: "Shell script — will run with admin password",
                action: .runScript(url: script)
            ))
        }

        // ── Remaining scan-detected binaries (not already added) ──────────
        for binary in scan.binaries where !handledPaths.contains(binary.path) {
            handledPaths.insert(binary.path)

            // If the binary lives inside a .app bundle, treat the whole bundle as the step.
            if let appBundle = parentAppBundle(of: binary) {
                let appPath = appBundle.path
                guard !handledPaths.contains(appPath), !handledAppBundles.contains(appPath) else { continue }
                handledAppBundles.insert(appPath)
                newSteps.append(TitanMissionStep(
                    icon: "app.badge.checkmark",
                    title: "Apply patch: \(appBundle.deletingPathExtension().lastPathComponent)",
                    detail: "Patch application — runs in-place with admin rights",
                    action: .runBinary(url: binary)
                ))
                continue
            }

            newSteps.append(TitanMissionStep(
                icon: "gearshape.2.fill",
                title: "\(L(.titanStepRunBinary)): \(binary.lastPathComponent)",
                detail: "Executable — generates license or applies activation",
                action: .runBinary(url: binary)
            ))
        }

        // ── Hosts entries fallback (if no instruction-guided ordering) ─────
        if plan.instructions == nil {
            for domain in scan.hostsEntries {
                newSteps.append(TitanMissionStep(
                    icon: "network.badge.shield.half.filled",
                    title: L(.titanStepEditHosts),
                    detail: "127.0.0.1 \(domain)",
                    action: .editHosts(domain: domain)
                ))
            }
        }

        steps = newSteps
    }

    // MARK: - Execute all steps

    func execute(adminPassword: String) async {
        guard !steps.isEmpty else { return }
        isRunning  = true
        isComplete = false
        // Reset rollback tracking
        installedPKGReceipts = []
        installedFiles       = []
        addedHostsEntries    = []
        WidgetStateManager.shared.menuStatus = .installing

        // Global auth watcher: auto-fills every "wants to make changes" dialog
        let authWatcher = InstallEngine.startAuthWatcher(password: adminPassword)

        for i in steps.indices {
            // Capture step for execution (avoid passing inout to async)
            let step = steps[i]
            steps[i].status = .running
            currentNote = step.title

            let result = await executeStep(step, adminPassword: adminPassword)

            if result.success {
                steps[i].status     = .done
                steps[i].resultNote = result.note
            } else {
                steps[i].status     = .failed
                steps[i].resultNote = result.note

                // Abort on failures that make it impossible to continue
                let isCritical: Bool = {
                    switch step.action {
                    case .installPkg, .launchApp, .clickAppButton, .selectAllInApp:
                        return true
                    default:
                        return false
                    }
                }()

                if isCritical {
                    currentNote = "Failed: \(step.title)"
                    // Mark all remaining steps as skipped so the log is clear
                    for j in (i + 1)..<steps.count {
                        steps[j].status = .skipped
                    }
                    break
                }
            }
        }

        authWatcher.terminate()
        isRunning  = false
        isComplete = true
        currentNote = ""
        WidgetStateManager.shared.menuStatus = .idle
    }

    // MARK: - Individual step execution

    private struct StepResult {
        let success: Bool
        let note: String
    }

    private func executeStep(_ step: TitanMissionStep, adminPassword: String) async -> StepResult {
        switch step.action {

        case .xcodeCommandLineTools:
            return await runXcodeTools()

        case .installPkg(let url):
            return await runPkg(url: url, adminPassword: adminPassword)

        case .runScript(let url):
            return await runScript(url: url, adminPassword: adminPassword)

        case .runBinary(let url):
            return await runBinary(url: url, adminPassword: adminPassword)

        case .editHosts(let domain):
            return await editHosts(domain: domain, adminPassword: adminPassword)

        case .shellCommand(let cmd):
            return await runShellCommand(cmd, adminPassword: adminPassword)

        case .informUser(let msg):
            return StepResult(success: true, note: msg)

        // ── Desktop UI automation ─────────────────────────────────────────────

        case .launchApp(let url):
            return await uiLaunchApp(url: url)

        case .waitForAppWindow(let appName, let hint, let timeout):
            return await uiWaitForWindow(appName: appName, titleHint: hint, timeout: timeout)

        case .clickAppButton(let appName, let label, let timeout):
            return await uiClickButton(appName: appName, label: label, timeout: timeout)

        case .selectAllInApp(let appName, let timeout):
            return await uiSelectAll(appName: appName, timeout: timeout)

        case .waitForAppCompletion(let appName, let timeout):
            return await uiWaitForCompletion(appName: appName, timeout: timeout)

        case .quitApp(let appName):
            return await uiQuitApp(appName: appName)

        case .moveAppToTrash(let appName):
            let ok = MacUIAutomator.moveToTrash(appNamed: appName)
            return StepResult(success: ok,
                              note: ok ? "Moved \(appName) to Trash" : "\(appName) not found in /Applications")

        case .trashPath(let path):
            let ok = MacUIAutomator.trashItem(atPath: path)
            let name = URL(fileURLWithPath: path).lastPathComponent
            return StepResult(success: ok,
                              note: ok ? "Removed: \(name)" : "Not found (already clean): \(name)")
        }
    }

    // MARK: - Executors

    private func runXcodeTools() async -> StepResult {
        // Check if already installed
        let checkResult = InstallEngine.runProcess(
            path: "/usr/bin/xcode-select",
            arguments: ["-p"])
        if checkResult.success {
            return StepResult(success: true, note: "Already installed at \(checkResult.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        // Trigger installation dialog
        let r = InstallEngine.runProcess(
            path: "/usr/bin/xcode-select",
            arguments: ["--install"])
        return StepResult(success: r.success || r.output.contains("already"),
                          note: r.success ? "Xcode tools installed" : "Xcode tools install dialog opened — complete it then click Continue")
    }

    private func runPkg(url: URL, adminPassword: String) async -> StepResult {
        // Snapshot receipts before install to detect what the PKG adds
        let receiptsBefore = PKGReceiptScanner.snapshotReceipts()
        let installStart   = Date()

        // Remove quarantine first
        _ = InstallEngine.runProcess(path: "/usr/bin/xattr",
                                     arguments: ["-cr", url.path])
        let pwdLine = adminPassword.isEmpty ? "" : "echo '\(adminPassword.replacingOccurrences(of: "'", with: "'\\''"))' | sudo -S "
        let script = "\(pwdLine)/usr/sbin/installer -pkg '\(url.path)' -target / 2>&1"
        let r = InstallEngine.runShell(script)
        let success = r.success || r.output.contains("successful")

        if success {
            // Capture new PKG receipts for rollback
            let newReceipts = PKGReceiptScanner.findNewReceipts(
                before: receiptsBefore, since: installStart)
            installedPKGReceipts.append(contentsOf: newReceipts)
            // Build file list from receipts for fine-grained rollback
            let newFiles = PKGReceiptScanner.buildInstalledFiles(newReceipts: newReceipts)
            installedFiles.append(contentsOf: newFiles)
        }

        return StepResult(success: success,
                          note: success ? "Package installed successfully" : r.output.prefix(200).description)
    }

    // Copies a file from a read-only volume to a writable temp directory.
    // Also copies small sibling files (< 10 MB) so scripts that do relative
    // imports (e.g. `import utils`) can find their dependencies.
    // Large files (.pkg, .dmg, etc.) are intentionally skipped to avoid
    // copying gigabytes from a mounted installer image.
    private func makeWritableCopy(of url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ATLAS_exec_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

            let maxSiblingBytes = 10 * 1024 * 1024  // 10 MB — enough for scripts, skip installers
            let siblings = (try? FileManager.default.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []

            for sibling in siblings {
                let rv     = try? sibling.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let isDir  = rv?.isDirectory ?? false
                let size   = rv?.fileSize   ?? 0
                if isDir || size > maxSiblingBytes { continue }   // skip folders and large files
                try? FileManager.default.copyItem(
                    at: sibling,
                    to: tmpDir.appendingPathComponent(sibling.lastPathComponent))
            }

            // Safety: ensure the primary file is present even if it exceeded the size heuristic
            let primary = tmpDir.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: primary.path) {
                try FileManager.default.copyItem(at: url, to: primary)
            }
            return primary
        } catch { return nil }
    }

    // Returns "arch -x86_64 " when the binary at `url` is Intel-only,
    // so Rosetta is used on Apple Silicon instead of failing outright.
    private func archPrefix(for url: URL) -> String {
        let info = InstallEngine.runProcess(path: "/usr/bin/file", arguments: [url.path])
        let out  = info.output.lowercased()
        // x86_64-only: contains "x86_64" but not "arm64" or "universal"
        if out.contains("x86_64") && !out.contains("arm64") && !out.contains("universal") {
            return "arch -x86_64 "
        }
        return ""
    }

    // Returns the nearest ancestor .app bundle containing `url`, or nil.
    private func parentAppBundle(of url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if current.pathExtension.lowercased() == "app" { return current }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    // Runs a .app patch bundle in-place from its own Contents/MacOS/ directory.
    // InstallBuilder apps use installbuilder.sh as the proper entry point — it
    // auto-selects the right arch binary and handles the runtime argument routing.
    private func runAppBundle(_ appURL: URL, adminPassword: String) async -> StepResult {
        let macosDir = appURL.appendingPathComponent("Contents/MacOS")
        let appName  = appURL.deletingPathExtension().lastPathComponent

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: macosDir, includingPropertiesForKeys: nil, options: [])) ?? []

        // installbuilder.sh is the correct entry point: it selects the right arch
        // binary and handles the runtime-name argument that KOMPLETE FX Bundle needs.
        // Fall back to a binary named after the bundle, then any binary without extension.
        let execURL: URL
        if let sh = candidates.first(where: { $0.lastPathComponent == "installbuilder.sh" }) {
            execURL = sh
        } else if let named = candidates.first(where: { $0.deletingPathExtension().lastPathComponent == appName }) {
            execURL = named
        } else if let any = candidates.first(where: { $0.pathExtension.isEmpty }) {
            execURL = any
        } else {
            return StepResult(success: false,
                              note: "No executable found in \(appName).app/Contents/MacOS")
        }

        // Strip quarantine from the entire bundle — must stay in-place
        _ = InstallEngine.runProcess(path: "/usr/bin/xattr", arguments: ["-cr", appURL.path])

        // Use the full absolute path so sudo can find the script regardless of cwd.
        // Use /bin/sh as interpreter so the execute bit on a read-only DMG doesn't matter.
        let fullExec = execURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let dir      = macosDir.path.replacingOccurrences(of: "'", with: "'\\''")
        let pwd      = adminPassword.replacingOccurrences(of: "'", with: "'\\''")

        let isShellScript = execURL.pathExtension == "sh"
        let runner        = isShellScript ? "/bin/sh '\(fullExec)'" : "'\(fullExec)'"

        // Try without sudo first — installbuilder.sh exits 0 as a regular user
        let r1 = InstallEngine.runShellWithEnv(
            "cd '\(dir)' && \(runner) --mode unattended 2>&1",
            env: ["ATLAS_PASSWORD": adminPassword],
            adminPassword: adminPassword
        )
        let out1 = r1.output.lowercased()
        if r1.success
            || out1.contains("finishing installation")
            || out1.contains("successfully installed")
            || out1.contains("installation complete") {
            return StepResult(success: true,
                              note: r1.output.isEmpty ? "Patch applied" : r1.output.prefix(200).description)
        }

        // Retry with sudo — full path so sudo doesn't look in $PATH
        let sudoCmd = pwd.isEmpty
            ? "cd '\(dir)' && \(runner) --mode unattended 2>&1"
            : "cd '\(dir)' && echo '\(pwd)' | sudo -S \(runner) --mode unattended 2>&1"
        let r2 = InstallEngine.runShellWithEnv(
            sudoCmd,
            env: ["ATLAS_PASSWORD": adminPassword],
            adminPassword: adminPassword
        )
        let out2     = r2.output.lowercased()
        let success2 = r2.success
                    || out2.contains("finishing installation")
                    || out2.contains("successfully installed")
                    || out2.contains("success")
                    || out2.contains("license file created")
        return StepResult(success: success2,
                          note: success2
                              ? (r2.output.isEmpty ? "Patch applied" : r2.output.prefix(200).description)
                              : r2.output.prefix(200).description)
    }

    private func runScript(url: URL, adminPassword: String) async -> StepResult {
        let sysLang = Locale.current.languageCode ?? "en"

        // Python scripts: run via python3 from their source directory.
        if url.pathExtension.lowercased() == "py" {
            let dir  = url.deletingLastPathComponent().path
                          .replacingOccurrences(of: "'", with: "'\\''")
            let file = url.lastPathComponent
                          .replacingOccurrences(of: "'", with: "'\\''")
            let r = InstallEngine.runShellWithEnv(
                "cd '\(dir)' && python3 '\(file)'",
                env: ["SYS_LANG": sysLang,
                      "SUDO_ASKPASS": "",
                      "ATLAS_PASSWORD": adminPassword],
                adminPassword: adminPassword
            )
            return StepResult(success: r.success,
                              note: r.success ? "Script completed" : r.output.prefix(200).description)
        }

        // Scripts inside a .app bundle: the bundle's own payload lookup is relative
        // to the bundle structure, so we MUST run in-place — not from a temp copy.
        if let appBundle = parentAppBundle(of: url) {
            return await runAppBundle(appBundle, adminPassword: adminPassword)
        }

        // All other scripts: copy to writable temp to strip quarantine, then run.
        let execURL = makeWritableCopy(of: url) ?? url
        _ = InstallEngine.runProcess(path: "/usr/bin/xattr", arguments: ["-cr", execURL.path])
        _ = InstallEngine.runProcess(path: "/bin/chmod", arguments: ["+x", execURL.path])

        let r = InstallEngine.runShellWithEnv(
            "'\(execURL.path)'",
            env: ["SYS_LANG": sysLang,
                  "SUDO_ASKPASS": "",
                  "ATLAS_PASSWORD": adminPassword],
            adminPassword: adminPassword
        )
        try? FileManager.default.removeItem(at: execURL.deletingLastPathComponent())
        return StepResult(success: r.success,
                          note: r.success ? "Script completed" : r.output.prefix(200).description)
    }

    private func runBinary(url: URL, adminPassword: String) async -> StepResult {
        // Binaries inside a .app bundle must run from within the bundle context —
        // copying to temp loses the payload directory structure InstallBuilder needs.
        if let appBundle = parentAppBundle(of: url) {
            return await runAppBundle(appBundle, adminPassword: adminPassword)
        }

        let execURL = makeWritableCopy(of: url) ?? url

        _ = InstallEngine.runProcess(path: "/usr/bin/xattr", arguments: ["-cr", execURL.path])
        _ = InstallEngine.runProcess(path: "/bin/chmod", arguments: ["+x", execURL.path])
        _ = InstallEngine.runProcess(path: "/usr/bin/codesign",
                                     arguments: ["--force", "--deep", "--sign", "-", execURL.path])

        // Detect x86_64-only binaries and invoke via Rosetta on Apple Silicon
        let prefix = archPrefix(for: execURL)
        let r = InstallEngine.runShellWithEnv(
            "\(prefix)'\(execURL.path)'",
            env: ["ATLAS_PASSWORD": adminPassword],
            adminPassword: adminPassword
        )
        try? FileManager.default.removeItem(at: execURL.deletingLastPathComponent())
        let success = r.success ||
                      r.output.lowercased().contains("success") ||
                      r.output.lowercased().contains("created") ||
                      r.output.lowercased().contains("license file created")
        return StepResult(success: success,
                          note: success
                              ? (r.output.isEmpty ? "Tool completed" : r.output.prefix(200).description)
                              : r.output.prefix(200).description)
    }

    private func editHosts(domain: String, adminPassword: String) async -> StepResult {
        // Check if entry already exists (we still track it for rollback if present)
        let hostsContent = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
        let entry = "127.0.0.1 \(domain)"
        if hostsContent.contains(domain) {
            // Already blocked — track for rollback so we can remove it if user uninstalls
            if !addedHostsEntries.contains(domain) { addedHostsEntries.append(domain) }
            return StepResult(success: true, note: "Already blocked: \(domain)")
        }
        let pwd = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
        // printf with a leading \n guarantees the entry starts on its own line even if
        // the existing hosts file has no trailing newline.
        let script = "echo '\(pwd)' | sudo -S sh -c \"printf '\\n\(entry)\\n' >> /etc/hosts\""
        let r = InstallEngine.runShell(script)
        if r.success {
            // Record for rollback — we only remove what we added
            if !addedHostsEntries.contains(domain) { addedHostsEntries.append(domain) }
        }
        return StepResult(success: r.success,
                          note: r.success ? "Blocked: \(domain)" : "Could not edit /etc/hosts — ensure ATLAS has Full Disk Access")
    }

    private func runShellCommand(_ command: String, adminPassword: String) async -> StepResult {
        let r = InstallEngine.runShell(command)
        return StepResult(success: r.success, note: r.output.prefix(150).description)
    }

    // MARK: - UI Automation executors

    private func uiLaunchApp(url: URL) async -> StepResult {
        let name = url.deletingPathExtension().lastPathComponent
        let app  = await MacUIAutomator.launch(url: url, timeout: 30)
        let ok   = app != nil
        return StepResult(success: ok,
                          note: ok ? "Launched \(name)" : "Could not launch \(name) — check it exists at \(url.path)")
    }

    private func uiWaitForWindow(appName: String, titleHint: String?,
                                  timeout: TimeInterval) async -> StepResult {
        let win = await MacUIAutomator.waitForWindow(appName: appName,
                                                     titleContaining: titleHint,
                                                     timeout: timeout)
        let ok  = win != nil
        let label = titleHint ?? appName
        return StepResult(success: ok,
                          note: ok ? "\(label) window ready" : "Timed out waiting for \(label) window")
    }

    private func uiClickButton(appName: String, label: String,
                                timeout: TimeInterval) async -> StepResult {
        let ok = await MacUIAutomator.clickButton(inApp: appName, labeled: label, timeout: timeout)
        return StepResult(success: ok,
                          note: ok ? "Clicked '\(label)'" : "Button '\(label)' not found in \(appName)")
    }

    private func uiSelectAll(appName: String, timeout: TimeInterval) async -> StepResult {
        let count = await MacUIAutomator.selectAll(inApp: appName, timeout: timeout)
        if count == -1 {
            return StepResult(success: true, note: "Clicked 'Select All' in \(appName)")
        } else if count > 0 {
            return StepResult(success: true, note: "Selected \(count) item(s) in \(appName)")
        } else {
            return StepResult(success: false, note: "No selectable items found in \(appName)")
        }
    }

    private func uiWaitForCompletion(appName: String, timeout: TimeInterval) async -> StepResult {
        let ok = await MacUIAutomator.waitForCompletion(inApp: appName, timeout: timeout)
        return StepResult(success: ok,
                          note: ok ? "\(appName) finished" : "Timed out waiting for \(appName) to complete")
    }

    private func uiQuitApp(appName: String) async -> StepResult {
        await MacUIAutomator.quitApp(named: appName, timeout: 15)
        let gone = MacUIAutomator.findApp(named: appName) == nil
        return StepResult(success: true,
                          note: gone ? "Closed \(appName)" : "\(appName) close requested")
    }
}
