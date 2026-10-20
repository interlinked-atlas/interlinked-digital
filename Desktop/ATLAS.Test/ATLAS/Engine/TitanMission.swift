import Foundation
import AppKit
import os

// MARK: - Mission step model

struct TitanMissionStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let action: TitanAction
    var status: Status = .pending
    var resultNote: String = ""

    enum Status { case pending, running, done, failed, warning, skipped }
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

    // ── Plugin codesigning ───────────────────────────────────────────────────
    /// Re-sign patched audio plugin bundles in standard plugin directories.
    case codesignApp(url: URL)

    // ── ZIP plugin bundle install ────────────────────────────────────────────
    /// Extract a ZIP and copy AU/VST3 plugin folders to the correct system directories.
    case installZIP(url: URL)

    // ── Activation asset installation ────────────────────────────────────────
    /// Verify that a license/activation file from the installer was deployed,
    /// and copy it to the correct destination if it wasn't consumed by the PKG.
    case installLicenseAsset(licenseFile: URL, installerDir: URL)

    // ── Guaranteed file copy (destination resolved at plan-build time) ────────
    /// Copy source to destination, creating the parent directory if needed.
    /// Used when the correct destination is known before execution begins.
    case copyFile(source: URL, destination: URL)
}

// MARK: - Mission orchestrator

@MainActor
final class TitanMission: ObservableObject {

    @Published var steps: [TitanMissionStep] = []
    @Published var isRunning = false
    @Published var isComplete = false
    @Published var currentNote = ""
    /// True when the mission could not start because the monthly install-limit
    /// reservation was denied (device already at 25 confirmed+active this period).
    @Published var limitReached = false

    // Source context
    let mountPoint: String
    let sourceURL: URL

    private let lic = os.Logger(subsystem: "digital.interlinked.atlas", category: "titan-license")

    // Filled in from scan
    private(set) var plan: InstallPlan?
    private(set) var scanResult: InstallIntelligence.TitanScanResult?

    // Rollback tracking — populated during execute() for PRO uninstall
    private(set) var installedPKGReceipts: [String] = []
    private(set) var installedFiles: [InstallRecord.InstalledFile] = []
    private(set) var addedHostsEntries: [String] = []
    private(set) var runtimeCreatedPaths: [String] = []

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
            case .folderCopy, .dawInstall:
                newSteps.append(TitanMissionStep(
                    icon: step.icon,
                    title: "\(step.label): \(step.url.lastPathComponent)",
                    detail: step.note,
                    action: .installPkg(url: step.url)
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

            // Insert hosts entries — merge TITAN MEMORY™ entries (instr.hostsEntries)
            // with any auto-detected entries (scan.hostsEntries), deduplicated.
            var seenDomains = Set<String>()
            for domain in (instr.hostsEntries + scan.hostsEntries) {
                guard seenDomains.insert(domain).inserted else { continue }
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

            // Skip bare InstallBuilder launcher scripts at the mount root — they require
            // their sibling payload data files and must be run via the .app bundle instead.
            let name = script.lastPathComponent.lowercased()
            if name == "installbuilder.sh" { continue }

            newSteps.append(TitanMissionStep(
                icon: "terminal.fill",
                title: "\(L(.titanStepRunScript)): \(script.lastPathComponent)",
                detail: "Shell script — will run with admin password",
                action: .runScript(url: script)
            ))
        }

        // ── Remaining scan-detected binaries (not already added) ──────────
        // Known InstallBuilder arch-launcher names that live alongside .app bundles
        // at the DMG root — they cannot run standalone without their payload data.
        let installBuilderLaunchers: Set<String> = ["osx-arm64", "osx-x86_64", "osx-x86", "installbuilder"]
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

            // Skip bare InstallBuilder arch-launcher binaries at the mount root.
            let bname = binary.deletingPathExtension().lastPathComponent.lowercased()
            if installBuilderLaunchers.contains(bname) { continue }

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

        // ── ZIP plugin bundles in the mount ─────────────────────────────────────
        // If the volume contains a ZIP with AU/ or VST3/ subdirectories,
        // add an installZIP step so ATLAS extracts and copies them automatically.
        let mountURL = URL(fileURLWithPath: mountPoint)
        if let mountContents = try? FileManager.default.contentsOfDirectory(
            at: mountURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for item in mountContents where item.pathExtension.lowercased() == "zip" {
                guard !handledPaths.contains(item.path) else { continue }
                // Peek inside the ZIP (unzip -l) to check for AU/ or VST3/ paths
                let peekResult = InstallEngine.runProcess(
                    path: "/usr/bin/unzip",
                    arguments: ["-l", item.path])
                let hasPluginFolders = peekResult.output.contains("AU/") ||
                                       peekResult.output.contains("VST3/") ||
                                       peekResult.output.contains("VST/") ||
                                       peekResult.output.contains(".component") ||
                                       peekResult.output.contains(".vst3") ||
                                       peekResult.output.contains(".vst")
                if hasPluginFolders {
                    handledPaths.insert(item.path)
                    newSteps.append(TitanMissionStep(
                        icon: "archivebox.fill",
                        title: "Extract & install plugins: \(item.lastPathComponent)",
                        detail: "Copies audio plugins to system plugin directories",
                        action: .installZIP(url: item)
                    ))
                }
            }
        }

        // ── Activation asset installation ─────────────────────────────────────
        // Scan for license files in known activation folders anywhere in the installer volume.
        // Pre-copy each found file to a local temp directory immediately — this eliminates any
        // dependency on the volume being mounted when the step executes.
        //
        // Baby Audio detection: volume name or ISO filename contains "baby" + "audio".
        // This is the primary and most reliable signal; PKG metadata is not used.
        //
        // For non-Baby-Audio installers the generic path attempts destination resolution
        // from PKG scripts at execution time.
        let volName  = mountURL.lastPathComponent.lowercased()
        let srcName  = sourceURL.deletingPathExtension().lastPathComponent.lowercased()
        let isBabyAudio = (volName.contains("baby") && volName.contains("audio"))
                       || (srcName.contains("baby") && srcName.contains("audio"))
                       || srcName.contains("babyaudio") || srcName.contains("baby_audio")

        let activationAssets = TitanMission.findActivationAssets(in: mountPoint)

        for asset in activationAssets {
            // Pre-copy to local temp so the step works even if the volume unmounts
            let fm = FileManager.default
            let tempDir = fm.temporaryDirectory
                .appendingPathComponent("atlas_lic_\(UUID().uuidString)")
            var effectiveSource = asset
            do {
                try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempFile = tempDir.appendingPathComponent(asset.lastPathComponent)
                try fm.copyItem(at: asset, to: tempFile)
                effectiveSource = tempFile
            } catch { /* fallback: use original path on volume */ }

            if isBabyAudio {
                let destDir = "\(NSHomeDirectory())/Library/Application Support/af854ba56b229a56c422472ee764eba8"
                let destination = URL(fileURLWithPath: destDir)
                    .appendingPathComponent(asset.lastPathComponent)
                newSteps.append(TitanMissionStep(
                    icon: "key.fill",
                    title: "Install license: \(asset.lastPathComponent)",
                    detail: "→ ~/Library/Application Support/af854ba56b229a56c422472ee764eba8/",
                    action: .copyFile(source: effectiveSource, destination: destination)
                ))
            } else {
                newSteps.append(TitanMissionStep(
                    icon: "key.fill",
                    title: "Verify license: \(asset.lastPathComponent)",
                    detail: "Confirming activation file placement",
                    action: .installLicenseAsset(licenseFile: effectiveSource, installerDir: mountURL)
                ))
            }
        }

        // Always add a codesign step after any install step — PKG, patch .app, or ZIP.
        // Even a plain PKG may install audio plugins that need re-signing so macOS trusts them.
        let needsCodesign = newSteps.contains { step in
            switch step.action {
            case .installPkg:   return true   // PKGs, patch .apps
            case .installZIP:   return true   // ZIP plugin bundles
            default:            return false
            }
        }
        if needsCodesign {
            // Use a placeholder URL — codesignApp will scan plugin dirs instead
            // when it detects the path is on /Volumes/ or not a real bundle
            newSteps.append(TitanMissionStep(
                icon: "signature",
                title: "Re-sign installed audio plugins",
                detail: "Strips quarantine flags and re-signs plugins so macOS trusts them",
                action: .codesignApp(url: URL(fileURLWithPath: "/Volumes/"))
            ))
        }

        steps = newSteps
    }

    // MARK: - Execute all steps

    func execute(adminPassword: String) async {
        guard !steps.isEmpty else { return }

        // Server-authoritative install-limit gate — atomic reserve. The current
        // architecture has no authoritative way to distinguish independent
        // top-level products from one product's multi-step workflow (confirmed by
        // investigation — no heuristic is used here), so an entire mission is
        // reserved and counted as ONE product, confirmed on overall mission
        // success or released on overall mission failure below.
        let reservation = await MonthlyLimitManager.shared.reserveSlot()
        guard reservation.allowed else {
            limitReached = true
            return
        }
        let reservationID = reservation.reservationID

        isRunning  = true
        isComplete = false
        // Reset rollback tracking
        installedPKGReceipts = []
        installedFiles       = []
        addedHostsEntries    = []
        runtimeCreatedPaths  = []
        MenuBarStatusManager.shared.menuStatus = .installing

        // Snapshot Library dirs before any installation step runs, so we can diff
        // after completion to detect directories this specific install created at runtime.
        let libSnapshot = InstallEngine.snapshotLibraryTopLevel()

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
                steps[i].resultNote = result.note

                // Critical steps abort the mission on failure.
                // Non-critical steps (codesign, metadata, optional post-processing)
                // get .warning — they don't gate the overall success result.
                let isCritical: Bool = {
                    switch step.action {
                    case .installPkg, .launchApp, .clickAppButton, .selectAllInApp:
                        return true
                    default:
                        return false
                    }
                }()

                if isCritical {
                    steps[i].status = .failed
                    currentNote = "Failed: \(step.title)"
                    // Mark all remaining steps as skipped so the log is clear
                    for j in (i + 1)..<steps.count {
                        steps[j].status = .skipped
                    }
                    break
                } else {
                    // Non-critical failure — warn but continue
                    steps[i].status = .warning
                }
            }
        }

        // Record runtime-created paths only when the mission succeeded.
        // A failed install should not leave ownership claims on the filesystem.
        let didFail = steps.contains(where: { $0.status == .failed })
        runtimeCreatedPaths = didFail ? [] : InstallEngine.diffLibraryTopLevel(before: libSnapshot)

        // Confirm the mission-level reservation on overall success, release on
        // overall failure — this mission was reserved and counted as ONE product.
        if let reservationID {
            if didFail {
                await MonthlyLimitManager.shared.releaseReservation(reservationID: reservationID)
            } else {
                await MonthlyLimitManager.shared.confirmSuccess(reservationID: reservationID)
            }
        }

        isRunning  = false
        isComplete = true
        currentNote = ""
        MenuBarStatusManager.shared.menuStatus = .idle
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

        case .codesignApp(let url):
            return await codesignApp(at: url)

        case .installZIP(let url):
            return await installZIPPlugins(url: url, adminPassword: adminPassword)

        case .installLicenseAsset(let licenseFile, let installerDir):
            return await installLicenseAsset(licenseFile: licenseFile,
                                             installerDir: installerDir,
                                             adminPassword: adminPassword)

        case .copyFile(let source, let destination):
            return await copyFileStep(from: source, to: destination, adminPassword: adminPassword)
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
        let urlPath = url.path
        let pwdEscaped = adminPassword.replacingOccurrences(of: "'", with: "'\\''")

        // If this is a .app bundle (patch patcher), route to runAppBundle instead
        if url.pathExtension.lowercased() == "app" {
            return await runAppBundleOffMain(url, adminPassword: adminPassword)
        }

        // Run all blocking work off the main thread
        let (success, output, newReceipts, newFiles) = await Task.detached(priority: .userInitiated) {
            let receiptsBefore = PKGReceiptScanner.snapshotReceipts()
            let installStart   = Date()

            _ = InstallEngine.runProcess(path: "/usr/bin/xattr", arguments: ["-cr", urlPath])

            // Scoped SUDO_ASKPASS: write password to a temp file so any `sudo` calls
            // inside PKG postinstall scripts get the password silently (no GUI dialog).
            // No AppleScript watcher needed — installer itself uses sudo -S (stdin).
            // Both temp files are cleaned up in the defer block below.
            let tmpFile = NSTemporaryDirectory() + "atlas_aw_\(Int.random(in: 100000...999999))"
            let askpassFile = NSTemporaryDirectory() + "atlas_askpass_\(Int.random(in: 100000...999999)).sh"
            try? adminPassword.write(toFile: tmpFile, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpFile)
            let askpassScript = "#!/bin/sh\ncat \"\(tmpFile)\"\n"
            try? askpassScript.write(toFile: askpassFile, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassFile)
            setenv("SUDO_ASKPASS", askpassFile, 1)
            defer {
                try? FileManager.default.removeItem(atPath: askpassFile)
                try? FileManager.default.removeItem(atPath: tmpFile)
                unsetenv("SUDO_ASKPASS")
            }

            let pwdLine = pwdEscaped.isEmpty ? "" : "echo '\(pwdEscaped)' | sudo -S "
            let script = "\(pwdLine)/usr/sbin/installer -pkg '\(urlPath)' -target / 2>&1"
            let r = InstallEngine.runShell(script)
            let success = r.success || r.output.contains("successful")

            var receipts: [String] = []
            var files: [InstallRecord.InstalledFile] = []
            if success {
                receipts = PKGReceiptScanner.findNewReceipts(before: receiptsBefore, since: installStart)
                // Classify each attributed receipt as .created (new to system) or .rewritten
                // (pre-existed and was overwritten by the installer). This mirrors the provenance
                // logic in installPKG so RollbackEngine can skip --forget for .rewritten receipts.
                var provenance: [String: ReceiptProvenance] = [:]
                for id in receipts {
                    provenance[id] = receiptsBefore.contains(id) ? .rewritten : .created
                }
                InstallEngine.lastPKGReceiptProvenance = provenance
                // Enumerate installed plugin bundles from receipt BOMs using --only-dirs,
                // which limits output to bundle-level directories and avoids the pipe-buffer
                // deadlock risk of raw --files output on large receipts (e.g. Serum presets).
                // resolveInstalledBundlesFromReceipts is format-agnostic: it discovers any
                // bundle type (.component, .vst3, .vst, .aaxplugin, .clap, .app, etc.) for
                // any vendor, using each receipt's own install-location for path resolution.
                files = InstallEngine.resolveInstalledBundlesFromReceipts(receipts)
            }
            return (success, r.output, receipts, files)
        }.value

        if success {
            installedPKGReceipts.append(contentsOf: newReceipts)
            installedFiles.append(contentsOf: newFiles)
        }

        return StepResult(success: success,
                          note: success ? "Package installed successfully" : output.prefix(200).description)
    }

    // Runs runAppBundle on a background thread so AX polling never blocks the main actor.
    private func runAppBundleOffMain(_ url: URL, adminPassword: String) async -> StepResult {
        let urlCopy = url
        let pwdCopy = adminPassword
        return await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return StepResult(success: false, note: "Mission deallocated") }
            return await self.runAppBundle(urlCopy, adminPassword: pwdCopy)
        }.value
    }

    // Re-signs the plugin bundle (or recently patched bundles) at url.
    // If url is on a read-only /Volumes/ mount, scans standard plugin dirs instead.
    private func codesignApp(at url: URL) async -> StepResult {
        // "/Volumes/" is the placeholder URL used when no specific bundle path
        // is known at plan-build time. URL(fileURLWithPath: "/Volumes/").path
        // normalizes to "/Volumes" (no trailing slash), so check for both.
        if url.path.hasPrefix("/Volumes") {
            return await codesignRecentlyPatchedBundles()
        }
        let path = url.path
        let r = await Task.detached(priority: .userInitiated) {
            InstallEngine.runProcess(path: "/usr/bin/codesign",
                                     arguments: ["--force", "--deep", "--sign", "-", path])
        }.value
        return StepResult(success: r.success,
                          note: r.success ? "Re-signed: \(url.lastPathComponent)" : r.output.prefix(200).description)
    }

    // Scans standard audio plugin directories for bundles modified in the last 5 minutes,
    // strips quarantine attributes, and re-signs them. Used when the target path is on
    // a read-only /Volumes/ mount, or after folder-copy plugin installs.
    private func codesignRecentlyPatchedBundles() async -> StepResult {
        let pluginDirs = [
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3",
            "/Library/Audio/Plug-Ins/VST",
            "/Library/Audio/Plug-Ins/AAX",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/Components",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST3",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST",
        ]
        let cutoff = Date().addingTimeInterval(-300)  // 5 minutes
        let fm = FileManager.default
        let signed = await Task.detached(priority: .userInitiated) {
            var count = 0
            for dir in pluginDirs {
                guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for item in contents {
                    let fullPath = "\(dir)/\(item)"
                    guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                          let mod = attrs[.modificationDate] as? Date,
                          mod >= cutoff else { continue }
                    // Strip all extended attributes and quarantine flag before signing
                    _ = InstallEngine.runProcess(path: "/usr/bin/xattr",
                                                 arguments: ["-cr", fullPath])
                    _ = InstallEngine.runProcess(path: "/usr/bin/xattr",
                                                 arguments: ["-r", "-d", "com.apple.quarantine", fullPath])
                    _ = InstallEngine.runProcess(path: "/usr/bin/codesign",
                                                 arguments: ["--force", "--deep", "--sign", "-", fullPath])
                    count += 1
                }
            }
            return count
        }.value

        return StepResult(success: true,
                          note: signed > 0 ? "Re-signed \(signed) plugin bundle(s)" : "No recently modified plugins found")
    }

    // Extracts a ZIP containing AU/ and/or VST3/ plugin folders, then copies each
    // vendor subfolder to the correct system plugin directory.
    private func installZIPPlugins(url: URL, adminPassword: String) async -> StepResult {
        let pwdEscaped = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
        let zipPath = url.path

        let result = await Task.detached(priority: .userInitiated) { [weak self] in
            let fm = FileManager.default
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ATLAS_zip_\(UUID().uuidString)")
            do {
                try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            } catch {
                return StepResult(success: false, note: "Could not create temp dir: \(error.localizedDescription)")
            }
            defer { try? fm.removeItem(at: tmpDir) }

            // Extract ZIP
            let unzip = InstallEngine.runProcess(path: "/usr/bin/unzip",
                                                 arguments: ["-q", "-o", zipPath, "-d", tmpDir.path])
            if !unzip.success && !fm.fileExists(atPath: tmpDir.path) {
                return StepResult(success: false, note: "Unzip failed: \(unzip.output.prefix(200))")
            }

            // Map of plugin type folder name → system destination
            let pluginMap: [(source: String, dest: String)] = [
                ("AU",   "/Library/Audio/Plug-Ins/Components"),
                ("VST3", "/Library/Audio/Plug-Ins/VST3"),
                ("VST",  "/Library/Audio/Plug-Ins/VST"),
                ("AAX",  "/Library/Application Support/Avid/Audio/Plug-Ins"),
            ]

            var copiedPaths: [String] = []
            var errors: [String] = []

            for mapping in pluginMap {
                let sourceFolder = tmpDir.appendingPathComponent(mapping.source)
                guard fm.fileExists(atPath: sourceFolder.path) else { continue }

                // Find vendor subfolders (e.g. "Antares/") inside the AU/VST3 folder
                let vendorFolders = (try? fm.contentsOfDirectory(
                    at: sourceFolder,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: .skipsHiddenFiles)) ?? []

                for vendor in vendorFolders {
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: vendor.path, isDirectory: &isDir), isDir.boolValue else { continue }

                    let destDir = URL(fileURLWithPath: mapping.dest)
                    let destVendor = destDir.appendingPathComponent(vendor.lastPathComponent)

                    // Create destination directory with sudo if needed
                    let mkdirScript = "echo '\(pwdEscaped)' | sudo -S mkdir -p '\(destVendor.path)'"
                    _ = InstallEngine.runShell(mkdirScript)

                    // Copy vendor folder contents into destination with sudo
                    let copyScript = "echo '\(pwdEscaped)' | sudo -S cp -R '\(vendor.path)/.' '\(destVendor.path)/'"
                    let copyResult = InstallEngine.runShell(copyScript)
                    if copyResult.success {
                        copiedPaths.append(destVendor.path)
                    } else {
                        errors.append("Copy \(vendor.lastPathComponent) → \(mapping.dest) failed")
                    }
                }

                // Also handle case where plugin bundles are directly in the type folder (no vendor subfolder)
                let directPlugins = (try? fm.contentsOfDirectory(
                    at: sourceFolder,
                    includingPropertiesForKeys: nil,
                    options: .skipsHiddenFiles)) ?? []
                for plugin in directPlugins {
                    let ext = plugin.pathExtension.lowercased()
                    guard ["component", "vst3", "vst", "aaxplugin"].contains(ext) else { continue }
                    let dest = URL(fileURLWithPath: mapping.dest).appendingPathComponent(plugin.lastPathComponent)
                    let copyScript = "echo '\(pwdEscaped)' | sudo -S cp -R '\(plugin.path)' '\(dest.path)'"
                    let copyResult = InstallEngine.runShell(copyScript)
                    if copyResult.success {
                        copiedPaths.append(dest.path)
                    } else {
                        errors.append("Copy \(plugin.lastPathComponent) failed")
                    }
                }
            }

            // Record installed files for rollback
            if let mission = self {
                let files = copiedPaths.map {
                    InstallRecord.InstalledFile(sourceName: URL(fileURLWithPath: $0).lastPathComponent,
                                               destinationPath: $0)
                }
                await MainActor.run { mission.installedFiles.append(contentsOf: files) }
            }

            if copiedPaths.isEmpty {
                return StepResult(success: false,
                                  note: errors.isEmpty ? "No plugin bundles found in ZIP" : errors.joined(separator: "; "))
            }
            let names = copiedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            return StepResult(success: true, note: "Installed: \(names)")
        }.value

        return result
    }

    // Copies a file from a read-only volume to a writable temp directory.
    // Also copies small sibling files (< 10 MB) so scripts that do relative
    // imports (e.g. `import utils`) can find their dependencies.
    // Large files (.pkg, .dmg, etc.) are intentionally skipped to avoid
    // copying gigabytes from a mounted installer image.
    nonisolated private func makeWritableCopy(of url: URL) -> URL? {
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
    nonisolated private func archPrefix(for url: URL) -> String {
        let info = InstallEngine.runProcess(path: "/usr/bin/file", arguments: [url.path])
        let out  = info.output.lowercased()
        // x86_64-only: contains "x86_64" but not "arm64" or "universal"
        if out.contains("x86_64") && !out.contains("arm64") && !out.contains("universal") {
            return "arch -x86_64 "
        }
        return ""
    }

    // Returns the nearest ancestor .app bundle containing `url`, or nil.
    nonisolated private func parentAppBundle(of url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if current.pathExtension.lowercased() == "app" { return current }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    // Runs a .app patch bundle through a tiered execution pipeline:
    //   Strategy 1 — InstallBuilder headless: arch-specific launcher + --mode unattended
    //   Strategy 2 — Generic headless: primary bundle executable via shell subprocess
    //                (no Launch Services → no Gatekeeper UI for any installer type)
    //   Strategy 3 — GUI with Gatekeeper pre-authorization: spctl --add before NSWorkspace,
    //                then drives the wizard automatically (clicks Next/Agree/Finish)
    // Strategies are tried in order; only reports failure after all are exhausted.
    // After any successful strategy, diffs plugin directories and PKG receipts to produce
    // an authoritative install record — format-agnostic, vendor-agnostic, name-agnostic.
    nonisolated private func runAppBundle(_ appURL: URL, adminPassword: String) async -> StepResult {
        let appName = appURL.deletingPathExtension().lastPathComponent
        let log = os.Logger(subsystem: "digital.interlinked.atlas", category: "titan-gatekeeper")

        // ── Writable copy for read-only mounted filesystems ───────────────────────────
        // /Volumes/ = read-only DMG mount via hdiutil attach.
        // /private/tmp/ = read-only ISO mount via hdiutil attach -mountrandom /tmp
        //   (/tmp is a symlink to /private/tmp; the resolved mount path always uses the
        //    /private/tmp/ prefix — not /tmp/).
        // xattr -cr cannot write to read-only filesystems, so copy to a writable temp
        // directory before any quarantine work. All subsequent operations use workingURL.
        let workingURL: URL
        var tempBundleDir: URL? = nil

        if appURL.path.hasPrefix("/Volumes/") || appURL.path.hasPrefix("/private/tmp/") {
            log.info("[ATLAS] .app on read-only filesystem: \(appURL.path, privacy: .public)")
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ATLAS_app_\(UUID().uuidString)")
            do {
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
                let dest = tmpDir.appendingPathComponent(appURL.lastPathComponent)
                try FileManager.default.copyItem(at: appURL, to: dest)
                workingURL = dest
                tempBundleDir = tmpDir
                log.info("[ATLAS] Writable copy created: \(workingURL.path, privacy: .public)")
            } catch {
                log.error("[ATLAS] Could not create writable copy (\(error.localizedDescription, privacy: .public))")
                return StepResult(
                    success: false,
                    note: "Could not create a working copy of \(appURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        } else {
            workingURL = appURL
        }

        // Clean up the temp copy when this function returns (success or failure)
        defer {
            if let dir = tempBundleDir {
                try? FileManager.default.removeItem(at: dir)
            }
        }

        // Strip quarantine from the working copy (writable) or the original path
        let xattrResult = InstallEngine.runProcess(path: "/usr/bin/xattr",
                                                   arguments: ["-cr", workingURL.path])
        if xattrResult.success {
            log.info("[ATLAS] Quarantine removed: \(workingURL.lastPathComponent, privacy: .public)")
        } else {
            log.warning("[ATLAS] Quarantine removal non-zero for \(workingURL.lastPathComponent, privacy: .public): \(xattrResult.output.prefix(120), privacy: .public)")
        }

        let macosDir = workingURL.appendingPathComponent("Contents/MacOS")

        // ── Pre-run install provenance snapshots ──────────────────────────────────────
        // FilesystemSnapshot matches the standard installFromMountPoint .patch pipeline:
        // it covers all plugin formats, /Applications, Application Support (vendor dirs
        // deep + new dirs shallow), LaunchAgents/Daemons, fonts, extensions, MIDI drivers,
        // and user-library equivalents — not just plugin directories.
        // PKGReceiptScanner captures receipts registered by any internal PKG the .app runs.
        // Both snapshots are taken once before any strategy executes so the diff is
        // attributed solely to this installer — no vendor names, no filename logic.
        let fsBefore       = FilesystemSnapshot.take()
        let receiptsBefore = PKGReceiptScanner.snapshotReceipts()
        let installStart   = Date()

        // Diffs the full watched filesystem scope and PKG receipts against pre-run
        // snapshots, appends results to the TitanMission record, and returns success.
        // Called exactly once at the first strategy that reports success.
        func recordInstall(note: String) async -> StepResult {
            let fsAfter     = FilesystemSnapshot.take()
            let changed     = FilesystemSnapshot.diff(before: fsBefore, after: fsAfter)
            let newFiles    = FilesystemSnapshot.buildInstalledFiles(changedPaths: changed)
            let newReceipts = PKGReceiptScanner.findNewReceipts(before: receiptsBefore, since: installStart)
            log.info("[ATLAS] Post-run record: \(newFiles.count, privacy: .public) file(s), \(newReceipts.count, privacy: .public) receipt(s) captured for \(appName, privacy: .public)")
            await MainActor.run {
                self.installedFiles.append(contentsOf: newFiles)
                self.installedPKGReceipts.append(contentsOf: newReceipts)
            }
            return StepResult(success: true, note: note)
        }

        // ── Strategy 1: InstallBuilder headless ───────────────────────────────────────
        // Detect arch-specific InstallBuilder launchers. Run with --mode unattended
        // so the installation completes without any visible window.
        // archPrefix returns "" (arm64/universal) or "arch -x86_64 " (Intel-only).
        // Priority list is arm64-first when the binary is not forced to x86.
        let isAppleSilicon = archPrefix(for: workingURL) == "arm64"
        let installBuilderPriority = isAppleSilicon
            ? ["osx-arm64", "osx-x86_64", "osx-x86", "installbuilder"]
            : ["osx-x86_64", "osx-x86", "osx-arm64", "installbuilder"]
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: macosDir.path) {
            let lowerContents = Dictionary(uniqueKeysWithValues: contents.map {
                ($0.lowercased(), $0)
            })
            for candidate in installBuilderPriority {
                guard let entry = lowerContents[candidate] else { continue }
                let launcher = macosDir.appendingPathComponent(entry)
                _ = InstallEngine.runProcess(path: "/bin/chmod", arguments: ["+x", launcher.path])
                let pwdEscaped = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
                let pwdLine = pwdEscaped.isEmpty ? "" : "echo '\(pwdEscaped)' | sudo -S "
                let script = "\(pwdLine)'\(launcher.path)' --mode unattended 2>&1"
                let r = InstallEngine.runShell(script)
                let ok = r.success || r.output.lowercased().contains("finish") || r.output.lowercased().contains("success")
                if ok {
                    return await recordInstall(note: "Patch applied (unattended)")
                }
                log.info("[ATLAS] InstallBuilder unattended failed for \(appName, privacy: .public) — trying generic headless")
                break
            }
        }

        // ── Strategy 2: Generic headless execution ────────────────────────────────────
        // Finds the primary bundle executable — the one matching the bundle name, or the
        // first no-extension binary that is not an InstallBuilder launcher (already tried).
        // Runs via shell subprocess (runShellWithEnv) — no Launch Services is invoked,
        // so Gatekeeper's UI dialog never fires regardless of signing status.
        let ibNames: Set<String> = ["osx-arm64", "osx-x86_64", "osx-x86", "installbuilder", "installbuilder.sh"]
        let execCandidates = (try? FileManager.default.contentsOfDirectory(
            at: macosDir, includingPropertiesForKeys: nil, options: [])) ?? []
        let primaryExec = execCandidates.first(where: {
            $0.lastPathComponent.lowercased() == appName.lowercased()
        }) ?? execCandidates.first(where: {
            $0.pathExtension.isEmpty && !ibNames.contains($0.lastPathComponent.lowercased())
        })
        if let exec = primaryExec {
            _ = InstallEngine.runProcess(path: "/bin/chmod", arguments: ["+x", exec.path])
            let dir = macosDir.path.replacingOccurrences(of: "'", with: "'\\''")
            let exe = exec.path.replacingOccurrences(of: "'", with: "'\\''")
            let pwd = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
            let prefix = archPrefix(for: exec)
            let sudoPrefix = pwd.isEmpty ? "" : "echo '\(pwd)' | sudo -S "
            // Attempt 2a: unattended mode — exits cleanly for installers that support it
            let r1 = InstallEngine.runShellWithEnv(
                "cd '\(dir)' && \(sudoPrefix)\(prefix)'\(exe)' --mode unattended 2>&1",
                env: ["ATLAS_PASSWORD": adminPassword], adminPassword: adminPassword)
            let out1 = r1.output.lowercased()
            if r1.success || out1.contains("finish") || out1.contains("success") || out1.contains("license") {
                log.info("[ATLAS] Generic headless (unattended) succeeded for \(appName, privacy: .public)")
                return await recordInstall(note: "Patch applied (headless)")
            }
            // Attempt 2b: bare execution — for installers that ignore --mode unattended
            let r2 = InstallEngine.runShellWithEnv(
                "cd '\(dir)' && \(sudoPrefix)\(prefix)'\(exe)' 2>&1",
                env: ["ATLAS_PASSWORD": adminPassword], adminPassword: adminPassword)
            let out2 = r2.output.lowercased()
            if r2.success || out2.contains("finish") || out2.contains("success") || out2.contains("license") {
                log.info("[ATLAS] Generic headless (bare) succeeded for \(appName, privacy: .public)")
                return await recordInstall(note: "Patch applied (headless)")
            }
            log.info("[ATLAS] Generic headless exhausted for \(appName, privacy: .public) — proceeding to GUI path")
        }

        // ── Strategy 3: GUI execution with Gatekeeper pre-authorization ───────────────
        // Mirrors InstallationManager.runPatchApp Step 2. spctl --assess first — the
        // exception is added only when actually needed (unsigned/unnotarized apps).
        // sudo -S with adminPassword — same elevation pattern as runPatchApp line 1765.
        // The per-item allow rule is written to /var/db/SystemPolicy on the writable
        // boot volume, independent of the source filesystem. Launch Services reads it
        // before presenting any dialog, so the app opens without user intervention.
        let escapedApp = workingURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let escapedPwd = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
        let gatekeeperOK = InstallEngine.runProcess(
            path: "/usr/sbin/spctl",
            arguments: ["--assess", "--type", "execute", workingURL.path]).success
        if !gatekeeperOK {
            log.info("[ATLAS] Establishing Gatekeeper exception for \(workingURL.lastPathComponent, privacy: .public)")
            let spctlResult = InstallEngine.runProcess(path: "/bin/bash", arguments: ["-c",
                "echo '\(escapedPwd)' | sudo -S /usr/sbin/spctl --add '\(escapedApp)'"])
            if spctlResult.success {
                log.info("[ATLAS] Gatekeeper exception added for \(workingURL.lastPathComponent, privacy: .public)")
            } else {
                log.warning("[ATLAS] Gatekeeper exception non-zero: \(spctlResult.output.prefix(120), privacy: .public)")
            }
        }

        // Launch via NSWorkspace so the app gets full GUI privileges
        await MainActor.run { NSWorkspace.shared.open(workingURL) }

        // Wait up to 30 s for the process to register
        _ = await MacUIAutomator.waitFor(timeout: 30) {
            MacUIAutomator.findApp(named: appName) != nil
        }

        // If the process still has not appeared, all strategies are exhausted.
        // spctl --assess distinguishes a genuine headless exit (app ran and finished
        // before we could poll it) from a failure to start at all.
        if MacUIAutomator.findApp(named: appName) == nil {
            log.info("[ATLAS] '\(appName, privacy: .public)' not found after GUI launch — running Gatekeeper assessment")
            let spctl = InstallEngine.runProcess(
                path: "/usr/sbin/spctl",
                arguments: ["--assess", "--type", "execute", workingURL.path])
            if spctl.success {
                log.info("[ATLAS] Gatekeeper assessment passed — headless exit, treating as success")
                return await recordInstall(note: "Patch applied")
            } else {
                log.warning("[ATLAS] All strategies exhausted for \(appName, privacy: .public): \(spctl.output.prefix(200), privacy: .public)")
                return StepResult(
                    success: false,
                    note: "\(appName) did not start after all execution strategies (headless, GUI with authorization). Check system logs for details.")
            }
        }

        // Start a per-patcher authorization watcher using the patcher's own PID as the guard.
        // This handles "wants to make changes" dialogs from GUI patchers that use
        // Authorization Services instead of (or in addition to) shell-level sudo.
        // The PID guard (kill -0 <appPID>) ensures the watcher stops the moment the
        // patcher process exits — ATLAS never fills auth dialogs from unrelated processes.
        let appPID = MacUIAutomator.findApp(named: appName)?.processIdentifier ?? 0
        let authWatcher: Process? = appPID > 0
            ? InstallEngine.startAuthWatcher(password: adminPassword, installerPID: appPID)
            : nil
        defer { authWatcher?.terminate() }

        // Wait up to 30 s for a visible window to appear
        var windowAppeared = false
        _ = await MacUIAutomator.waitFor(timeout: 30) {
            if MacUIAutomator.findApp(named: appName) == nil { return true }  // exited
            guard let app = MacUIAutomator.findApp(named: appName) else { return true }
            let ax = MacUIAutomator.axApp(for: app)
            windowAppeared = !MacUIAutomator.windows(of: ax).isEmpty
            return windowAppeared
        }

        // Exited while we were waiting for a window → headless success
        if MacUIAutomator.findApp(named: appName) == nil {
            return await recordInstall(note: "Patch applied (headless)")
        }

        if windowAppeared {
            // GUI installer wizard — drive it, then record what it installed
            let wizardResult = await driveInstallerWizard(appName: appName, timeout: 1800)
            if wizardResult.success {
                return await recordInstall(note: wizardResult.note)
            }
            return wizardResult
        }

        // No window after 30 s → running headlessly — wait up to 10 min for exit
        _ = await MacUIAutomator.waitFor(timeout: 600, interval: 3) {
            MacUIAutomator.findApp(named: appName) == nil
        }
        if MacUIAutomator.findApp(named: appName) != nil {
            await MacUIAutomator.quitApp(named: appName)
        }
        return await recordInstall(note: "Patch applied")
    }

    // Drives a wizard-style installer GUI through to completion.
    // Acquires GUIInstallerQueue so only one wizard runs at a time across all paths.
    // Delegates page detection, component selection, and button clicking to
    // MacUIAutomator.driveWizard — state-aware, Accessibility API only, no coordinates.
    nonisolated private func driveInstallerWizard(appName: String, timeout: TimeInterval = 1800) async -> StepResult {
        await GUIInstallerQueue.shared.acquire()
        defer { Task { await GUIInstallerQueue.shared.release() } }

        let ok = await MacUIAutomator.driveWizard(appName: appName, timeout: timeout)
        return StepResult(
            success: ok,
            note: ok ? "Installer completed" : "Installer wizard timed out after \(Int(timeout / 60)) min"
        )
    }

    private func runScript(url: URL, adminPassword: String) async -> StepResult {
        let sysLang = Locale.current.languageCode ?? "en"

        // Python scripts: run via python3 from their source directory.
        if url.pathExtension.lowercased() == "py" {
            let dir  = url.deletingLastPathComponent().path
                          .replacingOccurrences(of: "'", with: "'\\''")
            let file = url.lastPathComponent
                          .replacingOccurrences(of: "'", with: "'\\''")
            let home = NSHomeDirectory().replacingOccurrences(of: "'", with: "'\\''")
            let r = InstallEngine.runShellWithEnv(
                "env TERM=xterm-256color HOME='\(home)' sh -c \"cd '\(dir)' && python3 '\(file)'\"",
                env: ["SYS_LANG": sysLang,
                      "SUDO_ASKPASS": "",
                      "ATLAS_PASSWORD": adminPassword,
                      "TERM": "xterm-256color",
                      "HOME": NSHomeDirectory()],
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

        // Run the script IN PLACE — never copy to temp.
        // Scripts that use $BASH_SOURCE[0] or dirname "$0" to find sibling files
        // (e.g. BTCR/ license folders) will break if run from a temp copy because
        // the sibling directory no longer exists next to the script.
        let execURL = url
        _ = InstallEngine.runProcess(path: "/usr/bin/xattr", arguments: ["-cr", execURL.path])

        // Detect whether the script needs bash (shebang or bash-specific syntax).
        // /bin/sh ignores $BASH_SOURCE, so parent_path resolves to "" → wrong install dir.
        let scriptContent = (try? String(contentsOf: execURL, encoding: .utf8)) ?? ""
        let isBash = scriptContent.hasPrefix("#!/bin/bash") ||
                     scriptContent.hasPrefix("#!/usr/bin/env bash") ||
                     scriptContent.contains("BASH_SOURCE") ||
                     scriptContent.contains("declare -") ||
                     scriptContent.contains("local ")
        let shell = isBash ? "/bin/bash" : "/bin/sh"

        let dir  = execURL.deletingLastPathComponent().path
                          .replacingOccurrences(of: "'", with: "'\\''")
        let path = execURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let home = NSHomeDirectory().replacingOccurrences(of: "'", with: "'\\''")
        let pwd  = adminPassword.replacingOccurrences(of: "'", with: "'\\''")

        let env: [String: String] = [
            "SYS_LANG": sysLang,
            "SUDO_ASKPASS": "",
            "ATLAS_PASSWORD": adminPassword,
            "TERM": "xterm-256color",
            "HOME": NSHomeDirectory(),
        ]

        // Try without sudo first (some scripts don't need it)
        let r1 = InstallEngine.runShellWithEnv(
            "cd '\(dir)' && \(shell) '\(path)'",
            env: env, adminPassword: adminPassword
        )
        let out1 = r1.output.lowercased()
        if r1.success || out1.contains("install complete") || out1.contains("complete!") ||
           out1.contains("license") && (out1.contains("success") || out1.contains("done")) {
            return StepResult(success: true, note: "Script completed")
        }

        // Retry with sudo — runs the ENTIRE script as root so internal sudo calls work
        let r2 = InstallEngine.runShellWithEnv(
            "cd '\(dir)' && echo '\(pwd)' | sudo -S \(shell) '\(path)'",
            env: env, adminPassword: adminPassword
        )
        let out2 = r2.output.lowercased()
        let licenseOK = out2.contains("install complete") || out2.contains("complete!") ||
                        out2.contains("success") || out2.contains("license") ||
                        out2.contains("activated") || out2.contains("done")
        let success = r2.success || licenseOK
        return StepResult(success: success,
                          note: success ? "Script completed" : (r2.output.isEmpty ? r1.output : r2.output).prefix(300).description)
    }

    private func runBinary(url: URL, adminPassword: String) async -> StepResult {
        // .app bundles (GUI patchers): launch via NSWorkspace off main thread
        if url.pathExtension.lowercased() == "app" {
            return await runAppBundleOffMain(url, adminPassword: adminPassword)
        }

        // Binaries inside a .app bundle must run from within the bundle context —
        // copying to temp loses the payload directory structure InstallBuilder needs.
        if let appBundle = parentAppBundle(of: url) {
            return await runAppBundleOffMain(appBundle, adminPassword: adminPassword)
        }

        let urlPath = url.path
        let pwd = adminPassword

        // Run all blocking work off the main thread
        return await Task.detached(priority: .userInitiated) {
            let execURL = self.makeWritableCopy(of: url) ?? url

            _ = InstallEngine.runProcess(path: "/usr/bin/xattr", arguments: ["-cr", execURL.path])
            _ = InstallEngine.runProcess(path: "/bin/chmod", arguments: ["+x", execURL.path])
            _ = InstallEngine.runProcess(path: "/usr/bin/codesign",
                                         arguments: ["--force", "--deep", "--sign", "-", execURL.path])

            let prefix = self.archPrefix(for: execURL)
            let r = InstallEngine.runShellWithEnv(
                "\(prefix)'\(execURL.path)'",
                env: ["ATLAS_PASSWORD": pwd],
                adminPassword: pwd
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
        }.value
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

    // MARK: - Guaranteed file copy (destination resolved at plan time)

    /// Copy source to destination, creating the parent directory tree if needed.
    /// This is the execution path for vendor-profile license steps where the destination
    /// is fully resolved at plan-build time — no discovery happens here.
    private func copyFileStep(from source: URL, to destination: URL, adminPassword: String) async -> StepResult {
        let fm = FileManager.default
        let destDir = destination.deletingLastPathComponent()

        // Abort immediately if source doesn't exist (shouldn't happen — pre-copied to temp)
        guard fm.fileExists(atPath: source.path) else {
            return StepResult(success: false,
                              note: "⚠ License file detected but could not be installed.\nSource: \(source.path)\nReason: source file not accessible")
        }

        // Create destination directory if needed
        if !fm.fileExists(atPath: destDir.path) {
            do {
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
            } catch {
                let pwd = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
                let mk = InstallEngine.runProcess(
                    path: "/bin/sh",
                    arguments: ["-c", "echo '\(pwd)' | sudo -S mkdir -p '\(destDir.path)'"])
                guard mk.success || fm.fileExists(atPath: destDir.path) else {
                    return StepResult(success: false,
                                      note: "⚠ License file detected but could not be installed.\nDestination: \(destDir.path)\nReason: could not create directory")
                }
            }
        }

        // Skip if this exact file is already present (another install put it there)
        if fm.fileExists(atPath: destination.path) {
            return StepResult(success: true,
                              note: "License installed: \(destination.lastPathComponent)")
        }

        // Copy
        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            let pwd = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
            let src = source.path.replacingOccurrences(of: "'", with: "'\\''")
            let dst = destination.path.replacingOccurrences(of: "'", with: "'\\''")
            let cp = InstallEngine.runProcess(
                path: "/bin/sh",
                arguments: ["-c", "echo '\(pwd)' | sudo -S cp '\(src)' '\(dst)'"])
            guard cp.success else {
                return StepResult(success: false,
                                  note: "⚠ License file detected but could not be installed.\nSource: \(source.lastPathComponent)\nDestination: \(destDir.path)\nReason: \(error.localizedDescription)")
            }
        }

        // Verify the file physically exists before declaring success
        guard fm.fileExists(atPath: destination.path) else {
            return StepResult(success: false,
                              note: "⚠ License file detected but could not be installed.\nDestination: \(destination.path)\nReason: file not found after copy")
        }

        installedFiles.append(InstallRecord.InstalledFile(
            sourceName: source.lastPathComponent,
            destinationPath: destination.path))
        return StepResult(success: true,
                          note: "License installed: \(source.lastPathComponent)\nDestination: \(destDir.lastPathComponent)/")
    }

    // MARK: - Activation asset helpers

    /// Recursively scan the installer volume for license/activation files.
    ///
    /// Uses the system `find` command to locate license asset files anywhere inside the
    /// mounted volume. This is more reliable than Swift URL traversal because it is immune
    /// to pathExtension quirks on folder names like "v1.0.3 macOS BUBBiX" and correctly
    /// handles all directory nesting depths without Swift URL parsing edge cases.
    ///
    /// Searched extensions: .lcs, .lic, .license, .licence, .key
    /// Skipped directories: .app, .pkg, .mpkg, .component, .vst3, .vst, .aaxplugin, .dmg bundles
    private static func findActivationAssets(in mountPath: String) -> [URL] {
        // -prune skips descending into bundle directories, ! -name avoids dotfiles
        let script = """
        /usr/bin/find '\(mountPath)' \
          \\( -name '*.app' -o -name '*.pkg' -o -name '*.mpkg' -o -name '*.component' \
             -o -name '*.vst3' -o -name '*.vst' -o -name '*.aaxplugin' -o -name '*.dmg' \\) -prune \
          -o -type f \\( -name '*.lcs' -o -name '*.lic' -o -name '*.license' \
             -o -name '*.licence' -o -name '*.key' \\) -print
        """
        let result = InstallEngine.runShell(script)
        return result.output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    /// Post-PKG step: verify the license file reached its destination; copy it there if not.
    private func installLicenseAsset(licenseFile: URL, installerDir: URL, adminPassword: String) async -> StepResult {
        let fm = FileManager.default
        let fileName = licenseFile.lastPathComponent

        // 1. If already present anywhere under ~/Library/Application Support, we're done.
        let appSupport = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        if let found = findFile(named: fileName, under: appSupport) {
            return StepResult(success: true, note: "Already installed: \(found.path)")
        }

        // 2. Try to find the destination by parsing PKG postinstall scripts and installer scripts.
        if let destination = resolveActivationDestination(for: licenseFile, in: installerDir) {
            let destDir = destination.deletingLastPathComponent()

            // Create destination directory if needed (may require sudo for system paths)
            if !fm.fileExists(atPath: destDir.path) {
                do {
                    try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                } catch {
                    let pwdEscaped = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
                    let mk = InstallEngine.runProcess(
                        path: "/bin/sh",
                        arguments: ["-c", "echo '\(pwdEscaped)' | sudo -S mkdir -p '\(destDir.path)'"])
                    guard mk.success || fm.fileExists(atPath: destDir.path) else {
                        return StepResult(success: false, note: "Could not create directory: \(destDir.path)")
                    }
                }
            }

            // Copy the license file
            do {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: licenseFile, to: destination)
                installedFiles.append(InstallRecord.InstalledFile(
                    sourceName: fileName, destinationPath: destination.path))
                return StepResult(success: true, note: "Installed: \(destination.path)")
            } catch {
                let pwdEscaped = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
                let cp = InstallEngine.runProcess(
                    path: "/bin/sh",
                    arguments: ["-c", "echo '\(pwdEscaped)' | sudo -S cp '\(licenseFile.path)' '\(destination.path)'"])
                if cp.success {
                    installedFiles.append(InstallRecord.InstalledFile(
                        sourceName: fileName, destinationPath: destination.path))
                    return StepResult(success: true, note: "Installed (sudo): \(destination.path)")
                }
                return StepResult(success: false, note: "Copy failed: \(error.localizedDescription)")
            }
        }

        // 3. Could not determine destination — surface to user as a warning
        return StepResult(
            success: false,
            note: "Destination unknown — manually copy \"\(fileName)\" to its Application Support folder")
    }

    /// Walk a directory tree to find the first file with the given name.
    private func findFile(named name: String, under directory: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            return url
        }
        return nil
    }

    /// Attempt to determine where a license file should be installed.
    ///
    /// Resolution order:
    ///  1. Vendor profile (high-confidence; uses known destination for identified vendors)
    ///  2. PKG postinstall/preinstall scripts (recursive search handles both flat and distribution packages)
    ///  3. Shell scripts in the installer root
    private func resolveActivationDestination(for licenseFile: URL, in installerDir: URL) -> URL? {
        let fileName = licenseFile.lastPathComponent

        // ── 1. Vendor profile ──────────────────────────────────────────────
        if let vendorDir = vendorProfileDestination(in: installerDir) {
            return URL(fileURLWithPath: vendorDir).appendingPathComponent(fileName)
        }

        // ── 2. PKG postinstall scripts (recursive — handles both flat and distribution packages) ──
        //
        // Bug note: pkgutil --expand on a distribution package produces ONLY the Distribution XML
        // at the top level; component .pkg files are not further expanded into subdirectories.
        // We must also expand any .pkg files found inside the first-level expansion, and we
        // search recursively so we handle arbitrary nesting.
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: installerDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }

        let bundleExts: Set<String> = ["app", "mpkg", "component", "vst3", "vst", "aaxplugin", "dmg"]

        // Collect search dirs: root + plain immediate subdirectories
        var searchDirs: [URL] = [installerDir]
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            guard isDir, !bundleExts.contains(item.pathExtension.lowercased()) else { continue }
            searchDirs.append(item)
        }

        for searchDir in searchDirs {
            guard let dirItems = try? fm.contentsOfDirectory(
                at: searchDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for pkg in dirItems where pkg.pathExtension.lowercased() == "pkg" {
                if let dest = scanPKGForAppSupportPath(at: pkg, fileName: fileName) {
                    return dest
                }
            }
        }

        // ── 3. Shell scripts at the installer root and immediate subdirs ───
        let scriptExts: Set<String> = ["sh", "command", "bash", "zsh"]
        for searchDir in searchDirs {
            guard let dirItems = try? fm.contentsOfDirectory(
                at: searchDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for item in dirItems {
                let ext = item.pathExtension.lowercased()
                let name = item.lastPathComponent.lowercased()
                guard scriptExts.contains(ext) || name.contains("license") || name.contains("install") else { continue }
                if let content = try? String(contentsOf: item, encoding: .utf8),
                   let dir = extractAppSupportPath(from: content) {
                    return URL(fileURLWithPath: dir).appendingPathComponent(fileName)
                }
            }
        }

        return nil
    }

    // MARK: - Vendor profiles

    /// Called at plan-build time (volume guaranteed mounted) to resolve a known destination
    /// for identified vendors. Returns the absolute Application Support directory path, or nil.
    /// Detection reads PKG metadata — NOT filenames.
    private func vendorProfileDestinationAtPlanTime(in installerDir: URL) -> String? {
        if detectBabyAudio(in: installerDir) {
            return "\(NSHomeDirectory())/Library/Application Support/af854ba56b229a56c422472ee764eba8"
        }
        return nil
    }

    /// Called at step-execution time for the generic (non-vendor-profile) path.
    private func vendorProfileDestination(in installerDir: URL) -> String? {
        return vendorProfileDestinationAtPlanTime(in: installerDir)
    }

    /// Returns true when this installer is a Baby Audio product with high confidence.
    ///
    /// Detection uses three independent signals, in priority order:
    ///  1. Volume name (mount point last component) contains "baby" + "audio"
    ///  2. Source ISO / DMG filename contains "baby" + "audio" or "babyaudio"
    ///  3. PKG metadata (PackageInfo / Distribution XML) contains known Baby Audio tokens
    ///
    /// Signals 1 and 2 are checked first because Baby Audio consistently names their
    /// volume and ISO files "Baby Audio [Product] vX.X.X macOS". PKG identifiers have
    /// not proven reliable across all their releases so are used only as a fallback.
    private func detectBabyAudio(in installerDir: URL) -> Bool {
        // ── Signal 1: volume name ────────────────────────────────────────────
        let volName = installerDir.lastPathComponent.lowercased()
        if volName.contains("baby") && volName.contains("audio") { return true }

        // ── Signal 2: source file name (ISO / DMG) ───────────────────────────
        let srcName = sourceURL.deletingPathExtension().lastPathComponent.lowercased()
        if (srcName.contains("baby") && srcName.contains("audio")) ||
            srcName.contains("babyaudio") || srcName.contains("baby_audio") {
            return true
        }

        // ── Signal 3: PKG metadata ───────────────────────────────────────────
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: installerDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return false }

        let babyAudioTokens = ["com.babyaudio", "com.baby-audio", "baby audio", "babyaudio"]
        let bundleExts: Set<String> = ["app", "mpkg", "component", "vst3", "vst", "aaxplugin", "dmg"]

        var searchDirs: [URL] = [installerDir]
        for item in items {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            guard isDir, !bundleExts.contains(item.pathExtension.lowercased()) else { continue }
            searchDirs.append(item)
        }
        for searchDir in searchDirs {
            guard let dirItems = try? fm.contentsOfDirectory(
                at: searchDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            ) else { continue }
            for pkg in dirItems where pkg.pathExtension.lowercased() == "pkg" {
                if pkgContainsBabyAudioSignal(at: pkg, tokens: babyAudioTokens, fm: fm) {
                    return true
                }
            }
        }
        return false
    }

    /// Expand a PKG and recursively check PackageInfo / Distribution XML for Baby Audio tokens.
    private func pkgContainsBabyAudioSignal(at pkg: URL, tokens: [String], fm: FileManager) -> Bool {
        let tempDir = fm.temporaryDirectory.appendingPathComponent("atlas_ba_\(UUID().uuidString)")
        let expand = InstallEngine.runProcess(
            path: "/usr/sbin/pkgutil",
            arguments: ["--expand", pkg.path, tempDir.path])
        defer { try? fm.removeItem(at: tempDir) }
        guard expand.success else { return false }

        // Check metadata files at any depth in the expanded archive
        if let enumerator = fm.enumerator(at: tempDir, includingPropertiesForKeys: nil, options: []) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                guard name == "packageinfo" || name == "distribution" else { continue }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lower = content.lowercased()
                if tokens.contains(where: { lower.contains($0) }) { return true }
            }
        }

        // Distribution packages may embed component .pkg files — recurse one level
        if let inner = try? fm.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            for innerPkg in inner where innerPkg.pathExtension.lowercased() == "pkg" {
                if pkgContainsBabyAudioSignal(at: innerPkg, tokens: tokens, fm: fm) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - PKG script scanning

    /// Expand a PKG (flat or distribution) and search all postinstall/preinstall scripts
    /// at any depth for an Application Support path reference.
    ///
    /// pkgutil --expand on a flat package: produces Scripts/ at the root.
    /// pkgutil --expand on a distribution package: produces Distribution + embedded .pkg files.
    /// We handle both by recursing one level into any embedded component packages.
    private func scanPKGForAppSupportPath(at pkg: URL, fileName: String) -> URL? {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("atlas_scan_\(UUID().uuidString)")
        let expand = InstallEngine.runProcess(
            path: "/usr/sbin/pkgutil",
            arguments: ["--expand", pkg.path, tempDir.path])
        defer { try? fm.removeItem(at: tempDir) }
        guard expand.success else { return nil }

        // Search recursively for installer scripts in this expanded pkg
        if let dest = searchExpandedPKGForScripts(in: tempDir, fileName: fileName) {
            return dest
        }

        // Distribution packages: expand embedded .pkg component files one level deeper
        guard let inner = try? fm.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return nil }
        for innerPkg in inner where innerPkg.pathExtension.lowercased() == "pkg" {
            if let dest = scanPKGForAppSupportPath(at: innerPkg, fileName: fileName) {
                return dest
            }
        }
        return nil
    }

    private func searchExpandedPKGForScripts(in dir: URL, fileName: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: []) else { return nil }
        let scriptNames: Set<String> = ["postinstall", "preinstall", "install.sh"]
        for case let url as URL in enumerator {
            guard scriptNames.contains(url.lastPathComponent.lowercased()) else { continue }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if let dir = extractAppSupportPath(from: content) {
                return URL(fileURLWithPath: dir).appendingPathComponent(fileName)
            }
        }
        return nil
    }

    // MARK: - Path extraction

    /// Extract the first Application Support directory path referenced in a shell script.
    /// Handles common variable forms: ~, $HOME, $USER, $LOGNAME, /Users/username.
    /// Returns an absolute expanded path to the directory.
    private func extractAppSupportPath(from content: String) -> String? {
        // Matches ~/..., $HOME/..., $USER/..., /Users/$VAR/..., /Users/literal/...
        let pattern = #"(?:~|\$(?:HOME|USER|LOGNAME)|/Users/[^/\s"']+)/Library/Application[ ]Support/([^\s"'/\n\\]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsStr = content as NSString
        guard let match = regex.firstMatch(
            in: content, range: NSRange(location: 0, length: nsStr.length)),
              let range = Range(match.range, in: content)
        else { return nil }

        var path = String(content[range])
        let home = NSHomeDirectory()
        path = path.replacingOccurrences(of: "~", with: home)
        path = path.replacingOccurrences(of: "$HOME", with: home)
        path = path.replacingOccurrences(of: "$USER", with: home.components(separatedBy: "/").last ?? "")
        path = path.replacingOccurrences(of: "$LOGNAME", with: home.components(separatedBy: "/").last ?? "")
        // Replace any remaining /Users/$VARIABLE pattern
        if let varRegex = try? NSRegularExpression(pattern: #"/Users/\$[A-Za-z_]+"#) {
            path = varRegex.stringByReplacingMatches(
                in: path, range: NSRange(path.startIndex..., in: path),
                withTemplate: home)
        }
        return path
    }
}
