import Foundation
import os

struct RollbackResult {
    let success: Bool
    let removedFiles: [String]
    let failedFiles: [String]
    let detail: String
    var manifestPath: String? = nil   // path to JSON manifest used by Undo Uninstall
}

// Maps each original path to where it landed in the Trash, so restore can move it back.
struct TrashRecord: Codable {
    let originalPath: String
    let trashPath: String
}

struct RollbackEngine {

    private static let alog = os.Logger(subsystem: "digital.interlinked.atlas", category: "rollback")

    static var cancellationRequested = false

    static func cancelRollback() {
        alog.notice("[ATLAS-CANCEL] cancelRollback() called — setting cancellationRequested=true")
        cancellationRequested = true
    }

    // MARK: - Entry point

    static func rollback(record: InstallRecord,
                         otherRecords: [InstallRecord] = [],
                         logger: Logger,
                         onProgress: (@Sendable (Double, String) -> Void)? = nil) async -> RollbackResult {
        alog.notice("[ATLAS-ROLLBACK] ENTER rollback() — product=\(record.fileName, privacy: .public) receipts=\(record.pkgReceiptIDs.count) installedFiles=\(record.installedFiles.count) isMainThread=\(Thread.isMainThread)")
        cancellationRequested = false
        let rollbackStart = Date()
        await logger.log("--- Rollback: \(record.fileName) ---")

        guard let password = KeychainManager.loadPassword() else {
            await logger.log("No password found in Keychain")
            return RollbackResult(success: false, removedFiles: [], failedFiles: [],
                                 detail: "No password stored.")
        }

        var removed:      [String]      = []
        var failed:       [String]      = []
        var trashRecords: [TrashRecord] = []

        // ── Plan: Build deletion list from stored manifest (ownership-based) ──
        // InstallRecord is the single source of truth. No filesystem scanning,
        // no vendor inference, no receipt re-enumeration.
        // Every product owns ONLY the paths in its own InstallRecord.
        // Shared directories are protected: only this product's files are removed.

        onProgress?(0.10, "Building uninstall plan|Reading installation manifest")
        await logger.log("Manifest: \(record.installedFiles.count) installed file(s), \(record.runtimeCreatedPaths?.count ?? 0) runtime path(s)")
        alog.notice("[ATLAS-ROLLBACK] PLAN START — manifest installedFiles=\(record.installedFiles.count) runtimePaths=\(record.runtimeCreatedPaths?.count ?? 0) isMainThread=\(Thread.isMainThread)")

        // Compute all paths owned by OTHER installed products. Used to detect
        // shared directories and prevent removing another product's files.
        onProgress?(0.14, "Building uninstall plan|Checking shared ownership")
        var otherOwnedPaths = Set<String>()
        for other in otherRecords where other.id != record.id && other.status == .success {
            other.installedFiles.forEach { otherOwnedPaths.insert($0.destinationPath) }
            (other.runtimeCreatedPaths ?? []).forEach { otherOwnedPaths.insert($0) }
        }
        alog.notice("[ATLAS-ROLLBACK] otherOwnedPaths=\(otherOwnedPaths.count)")

        var candidates = Set<String>()
        var runtimeTrustedPaths = Set<String>()

        // Manifest path: add explicitly tracked files (license assets, ZIP-installed plugins, etc.)
        if !record.installedFiles.isEmpty {
            onProgress?(0.18, "Building uninstall plan|Assembling file list")
            for path in record.installedFiles.map(\.destinationPath) {
                guard !otherOwnedPaths.contains(path) else { continue }
                candidates.insert(path)
            }
        }

        // PKG receipt path: enumerate receipts via pkgutil.
        // Runs when receipts are recorded, regardless of whether installedFiles is also populated.
        // (TITAN missions record license assets in installedFiles AND PKG installs in pkgReceiptIDs —
        // both must be processed so uninstall removes plugins AND license files.)
        if !record.pkgReceiptIDs.isEmpty || record.installedFiles.isEmpty {
            // Always run receipt scan when receipts exist.
            // Also run as legacy fallback when installedFiles is empty (old records).
            if record.installedFiles.isEmpty {
                alog.notice("[ATLAS-ROLLBACK] LEGACY PATH — no stored manifest, enumerating receipts via pkgutil")
            }
            onProgress?(0.18, "Reading receipts|Enumerating PKG receipts")
            await logger.log("Scanning receipts...")
            let fnTask = Task.detached { PKGReceiptScanner.findReceiptsByName(record.fileName) }
            let aiTask = Task.detached { PKGReceiptScanner.snapshotReceipts() }
            let titanEntry   = TitanMemory.shared.lookup(name: record.fileName)
            let freshByName  = await fnTask.value
            let allInstalled = await aiTask.value
            let freshByPrefix: [String] = (titanEntry?.knownReceiptPrefixes ?? []).flatMap { prefix in
                allInstalled.filter { $0.hasPrefix(prefix) }
            }
            let allReceiptIDs = Array(Set(record.pkgReceiptIDs + freshByName + freshByPrefix))
            await logger.log("Phase 1: \(allReceiptIDs.count) receipt(s) to scan")
            let totalReceipts = allReceiptIDs.count
            for (receiptIndex, receiptID) in allReceiptIDs.enumerated() {
                onProgress?(0.18 + Double(receiptIndex) / Double(max(totalReceipts, 1)) * 0.10,
                            "Reading receipts|Receipt \(receiptIndex + 1) of \(totalReceipts): \(receiptID)")
                if cancellationRequested || Task.isCancelled {
                    cancellationRequested = true
                    await logger.log("Uninstall cancelled during receipt scan.")
                    return RollbackResult(success: false, removedFiles: [], failedFiles: [],
                                         detail: "Cancelled.")
                }
                let files = await receiptFilesWithTimeout(receiptID: receiptID, seconds: 10)
                if files.isEmpty {
                    let locTask = Task.detached { PKGReceiptScanner.installLocation(forReceipt: receiptID) }
                    let pnTask  = Task.detached { PKGReceiptScanner.pkgName(forReceipt: receiptID) }
                    let location = await locTask.value
                    let pkgName  = await pnTask.value
                    let sharedDirs: Set<String> = [
                        "/Library/Audio/Plug-Ins/Components", "/Library/Audio/Plug-Ins/VST3",
                        "/Library/Audio/Plug-Ins/VST", "/Library/Application Support/Avid/Audio/Plug-Ins",
                        "/Library/Audio/Plug-Ins", "/Library/Application Support",
                        "/Library/Audio/Presets", "/Library"
                    ]
                    if !location.isEmpty && location != "/" && !sharedDirs.contains(location) {
                        candidates.insert(location)
                    } else if let name = pkgName, !name.isEmpty {
                        for dir in ["/Library/Audio/Presets/\(name)",
                                    "/Library/Application Support/\(name)",
                                    NSHomeDirectory() + "/Library/Audio/Presets/\(name)"]
                        where FileManager.default.fileExists(atPath: dir) {
                            candidates.insert(dir)
                        }
                    }
                } else {
                    files.forEach { candidates.insert($0) }
                }
            }
            await logger.log("Receipt scan complete — \(candidates.count) raw candidate(s)")
        }

        // Runtime-created directories (from filesystem diff at install time)
        for path in (record.runtimeCreatedPaths ?? []) {
            guard !otherOwnedPaths.contains(path) else { continue }
            let prefix = path.hasSuffix("/") ? path : path + "/"
            if otherOwnedPaths.contains(where: { $0.hasPrefix(prefix) }) {
                await logger.log("Shared container — contents only: \(URL(fileURLWithPath: path).lastPathComponent)")
            } else {
                candidates.insert(path)
                runtimeTrustedPaths.insert(path)
            }
        }

        if cancellationRequested || Task.isCancelled {
            cancellationRequested = true
            await logger.log("Uninstall cancelled during preparation.")
            return RollbackResult(success: false, removedFiles: [], failedFiles: [], detail: "Cancelled.")
        }

        // ── Collapse files inside plugin bundles (in-memory, no I/O) ─────────
        // Replaces individual files inside .vst3/.component/.aaxplugin etc.
        // with the bundle root so we trash the bundle as a single item.
        onProgress?(0.24, "Building uninstall plan|Collapsing plugin bundles")
        let afterBundles = collapseIntoBundles(Array(candidates))
        // Trust bundle roots — bypass Phase 3 untracked-items safety check.
        let knownBundleExts: Set<String> = [
            "component", "vst3", "vst", "aaxplugin", "app",
            "framework", "plugin", "kext", "appex", "bundle"
        ]
        for path in afterBundles where knownBundleExts.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()) {
            runtimeTrustedPaths.insert(path)
        }

        let afterDirs = collapseByDirectory(afterBundles)
        if afterDirs.count < afterBundles.count {
            await logger.log("Folder collapse: \(afterBundles.count) → \(afterDirs.count) item(s)")
            let priorPaths = Set(afterBundles)
            for path in afterDirs where !priorPaths.contains(path) {
                runtimeTrustedPaths.insert(path)
            }
        }
        let sorted = sortByPriority(afterDirs)
        let previewNames = sorted.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        await logger.log("Uninstall plan: \(sorted.count) item(s) — \(previewNames)\(sorted.count > 5 ? "…" : "")")
        alog.notice("[ATLAS-ROLLBACK] PLAN COMPLETE — \(sorted.count) item(s) elapsed=\(String(format: "%.1f", Date().timeIntervalSince(rollbackStart)))s")
        await logger.log("Moving files to Trash...")
        onProgress?(0.28, "Moving to Trash|Preparing \(sorted.count) item\(sorted.count == 1 ? "" : "s")")

        // ── Phase 3: Move each item to Trash ──────────────────────────────────
        var alreadyGoneCount = 0

        let totalItems = sorted.count
        for (i, path) in sorted.enumerated() {
            if cancellationRequested || Task.isCancelled {
                cancellationRequested = true
                await logger.log("Uninstall cancelled by user.")
                break
            }
            let name = URL(fileURLWithPath: path).lastPathComponent
            let pct  = 0.3 + Double(i + 1) / Double(max(totalItems, 1)) * 0.6

            guard FileManager.default.fileExists(atPath: path) else {
                alreadyGoneCount += 1
                removed.append(path)
                onProgress?(pct, "Removing (\(i + 1) of \(totalItems))…")
                continue
            }

            if isSystemPath(path) {
                await logger.log("⚠ Skipped (system path): \(name)")
                onProgress?(pct, "Removing (\(i + 1) of \(totalItems))…")
                continue
            }

            // Safety: never trash a plain directory that contains files not in our tracked set.
            // This prevents wiping shared folders (e.g. /Library/Application Support/Avid/Audio/Plug-Ins)
            // that happen to be listed in a PKG receipt but also contain other apps' files.
            // EXCEPTION: paths in runtimeTrustedPaths are bypassed — they were recorded at
            // install time as "this entire directory was created fresh by this install."
            // Vendor preference files (also in runtimeTrustedPaths) are also exempt.
            let pathExt = URL(fileURLWithPath: path).pathExtension.lowercased()
            let knownBundleExts: Set<String> = ["component","vst3","vst","aaxplugin","app","framework","plugin","kext","appex","bundle"]
            var pathIsDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &pathIsDir)
            if pathIsDir.boolValue && !knownBundleExts.contains(pathExt) && !runtimeTrustedPaths.contains(path) {
                let dirContents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                let untrackedItems = dirContents.filter { item in
                    let full = (path as NSString).appendingPathComponent(item)
                    return !sorted.contains(full)
                }
                if !untrackedItems.isEmpty {
                    await logger.log("⚠ Skipped directory (contains \(untrackedItems.count) untracked item(s)): \(name)")
                    onProgress?(pct, "")
                    continue
                }
            }

            if path.contains("/LaunchAgents/") || path.contains("/LaunchDaemons/") {
                _ = await runWithPassword(password: password,
                                         arguments: ["/bin/launchctl", "unload", path])
            }

            await logger.log("Trashing \(name)...")
            alog.notice("[ATLAS-ROLLBACK] Phase3 item \(i + 1)/\(totalItems) START: \(path, privacy: .public)")
            onProgress?(pct, "Moving to Trash|\(name) (\(i + 1) of \(totalItems))")

            let t = itemTimeout(path)
            let trashStart = Date()
            let (result, trashPath) = await trashItem(path: path, password: password, seconds: t)
            let trashElapsed = Date().timeIntervalSince(trashStart)
            switch result {
            case .done:
                alog.notice("[ATLAS-ROLLBACK] Phase3 item \(i + 1)/\(totalItems) DONE: \(String(format: "%.1f", trashElapsed))s \(path, privacy: .public)")
                await logger.log("✓ \(name) → Trash [\(String(format: "%.1f", trashElapsed))s]")
                removed.append(path)
                if let tp = trashPath {
                    trashRecords.append(TrashRecord(originalPath: path, trashPath: tp))
                }
            case .skipped:
                alog.notice("[ATLAS-ROLLBACK] Phase3 item \(i + 1)/\(totalItems) SKIPPED (timeout): \(path, privacy: .public)")
                await logger.log("⚠ Skipped (timeout \(String(format: "%.0f", t))s exceeded): \(name)")
            case .failed:
                alog.notice("[ATLAS-ROLLBACK] Phase3 item \(i + 1)/\(totalItems) FAILED: \(path, privacy: .public)")
                await logger.log("✗ Could not trash: \(name)")
                failed.append(path)
            }

            onProgress?(pct, "Moving to Trash|\(name) (\(i + 1) of \(totalItems))")
        }

        if alreadyGoneCount > 0 {
            await logger.log("Skipped \(alreadyGoneCount) already-removed path(s)")
        }

        // ── Phase 4: Write manifest so Undo Uninstall knows Trash paths ───────
        let manifestPath = writeTrashManifest(trashRecords, for: record.fileName)

        // ── Phase 5: Forget PKG receipts ─────────────────────────────────────
        var forgotCount = 0
        let receiptIDsToForget = record.pkgReceiptIDs
        alog.notice("[ATLAS-ROLLBACK] Phase5 START — forgetting \(receiptIDsToForget.count) receipt(s), elapsed=\(String(format: "%.1f", Date().timeIntervalSince(rollbackStart)))s")
        await logger.log("Removing receipts...")
        onProgress?(0.9, "Removing receipts|Forgetting \(receiptIDsToForget.count) receipt(s)")
        for (forgetIndex, id) in receiptIDsToForget.enumerated() {
            if cancellationRequested || Task.isCancelled {
                cancellationRequested = true
                await logger.log("Uninstall cancelled during receipt removal.")
                break
            }
            alog.notice("[ATLAS-ROLLBACK] Phase5 forget \(forgetIndex + 1)/\(receiptIDsToForget.count): \(id, privacy: .public)")
            // PKGReceiptScanner.forgetReceipt uses sudo + Thread.sleep — background thread.
            let forgot = await Task.detached { PKGReceiptScanner.forgetReceipt(id, password: password) }.value
            alog.notice("[ATLAS-ROLLBACK] Phase5 forget \(id, privacy: .public) result: \(forgot ? 1 : 0)")
            await logger.log("\(forgot ? "✓" : "✗") \(id)")
            if forgot { forgotCount += 1 }
            else { await logger.log("⚠ Could not clear receipt: \(id)") }
            onProgress?(0.9 + Double(forgetIndex + 1) / Double(max(receiptIDsToForget.count, 1)) * 0.07,
                        "Removing receipts|Receipt \(forgetIndex + 1) of \(receiptIDsToForget.count)")
        }
        if forgotCount > 0 { await logger.log("✓ Cleared \(forgotCount) receipt(s)") }

        // ── Phase 6: Clean up empty parent directories ────────────────────────
        alog.notice("[ATLAS-ROLLBACK] Phase6 START — cleanup empty dirs, elapsed=\(String(format: "%.1f", Date().timeIntervalSince(rollbackStart)))s")
        onProgress?(0.97, "Cleaning up|Removing empty directories")
        let emptyDirs = await cleanupEmptyDirs(from: removed, password: password)
        if !emptyDirs.isEmpty {
            await logger.log("Cleaned \(emptyDirs.count) empty folder(s)")
            removed += emptyDirs
        }

        // ── Phase 7: Remove /etc/hosts entries added by TITAN CORE™ ──────────
        // ATLAS only removes the exact lines it added — NEVER touches any other
        // hosts entries. System hosts entries are completely safe.
        if let hostsEntries = record.addedHostsEntries, !hostsEntries.isEmpty {
            let removedDomains = removeHostsEntries(hostsEntries, password: password)
            if !removedDomains.isEmpty {
                await logger.log("✓ Removed \(removedDomains.count) hosts block(s): \(removedDomains.joined(separator: ", "))")
            }
        }

        // ── Summary ──────────────────────────────────────────────────────────
        let uniqueRemoved = Array(Set(removed))
        let uniqueFailed  = Array(Set(failed))
        let totalElapsed  = Date().timeIntervalSince(rollbackStart)

        if cancellationRequested {
            onProgress?(1.0, "Cancelled — \(uniqueRemoved.count) of \(sorted.count) item\(sorted.count == 1 ? "" : "s") removed")
            await logger.log("Cancelled — partial uninstall: trashed \(uniqueRemoved.count) item(s)")
        } else {
            onProgress?(1.0, "Completed")
            await logger.log("Completed — total \(String(format: "%.1f", totalElapsed))s — trashed: \(uniqueRemoved.count), failed: \(uniqueFailed.count)")
        }

        let detail: String
        if uniqueFailed.isEmpty {
            detail = "Moved \(uniqueRemoved.count) item(s) to Trash."
        } else if uniqueRemoved.isEmpty {
            detail = "Could not move any files to Trash."
        } else {
            detail = "Moved \(uniqueRemoved.count) to Trash; \(uniqueFailed.count) could not be moved."
        }

        return RollbackResult(
            success: !uniqueRemoved.isEmpty || !(record.addedHostsEntries?.isEmpty ?? true),
            removedFiles: uniqueRemoved,
            failedFiles: uniqueFailed,
            detail: detail,
            manifestPath: manifestPath
        )
    }

    // MARK: - Hosts removal (TITAN CORE™ rollback, PRO only)

    // Removes ONLY lines ATLAS added — matched by exact "127.0.0.1 <domain>" or the legacy
    // "127.0.0.1 <domain> # added by ATLAS" form from older builds. Never touches other lines.
    @discardableResult
    static func removeHostsEntries(_ domains: [String], password: String) -> [String] {
        guard !domains.isEmpty else { return [] }
        guard let hostsRaw = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) else {
            return []
        }

        var removedDomains: [String] = []
        let lines = hostsRaw.components(separatedBy: "\n")
        var newLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var shouldRemove = false

            for domain in domains {
                // Match: "127.0.0.1 domain" with optional "# added by ATLAS" marker
                // Only remove lines that are EXACTLY the block we added — nothing else
                let isAtlasMarked = trimmed == "127.0.0.1 \(domain) # added by ATLAS"
                let isPlainBlock  = trimmed == "127.0.0.1 \(domain)"
                if isAtlasMarked || isPlainBlock {
                    shouldRemove = true
                    if !removedDomains.contains(domain) { removedDomains.append(domain) }
                    break
                }
            }

            if !shouldRemove { newLines.append(line) }
        }

        guard !removedDomains.isEmpty else { return [] }

        // Write back using a temp file + sudo mv — never truncates original if write fails
        let newContent = newLines.joined(separator: "\n")
        let tmpPath = "/tmp/atlas_hosts_\(UUID().uuidString)"
        do {
            try newContent.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        } catch { return [] }

        let pwd = password.replacingOccurrences(of: "'", with: "'\\''")
        let script = "echo '\(pwd)' | sudo -S cp '\(tmpPath)' /etc/hosts && rm -f '\(tmpPath)'"
        _ = InstallEngine.runShell(script)

        return removedDomains
    }

    // MARK: - Recover (moves files back from Trash to their original locations)

    static func restore(from manifestPath: String,
                        logger: Logger) async -> Bool {
        guard let data    = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let records = try? JSONDecoder().decode([TrashRecord].self, from: data),
              !records.isEmpty else {
            await logger.log("No recovery manifest found at \(manifestPath)")
            return false
        }

        guard let password = KeychainManager.loadPassword() else {
            await logger.log("No password found — cannot restore")
            return false
        }

        await logger.log("Recovering \(records.count) file(s) from Trash...")
        var restoredCount = 0

        for record in records {
            guard FileManager.default.fileExists(atPath: record.trashPath) else {
                await logger.log("⚠ No longer in Trash: \(URL(fileURLWithPath: record.originalPath).lastPathComponent)")
                continue
            }
            guard !FileManager.default.fileExists(atPath: record.originalPath) else {
                restoredCount += 1
                continue
            }

            let parentDir = URL(fileURLWithPath: record.originalPath).deletingLastPathComponent().path
            _ = await runWithPassword(password: password, arguments: ["/bin/mkdir", "-p", parentDir])

            // Try user-space move first, fall back to sudo
            if (try? FileManager.default.moveItem(atPath: record.trashPath,
                                                  toPath: record.originalPath)) != nil {
                restoredCount += 1
                await logger.log("✓ Recovered: \(URL(fileURLWithPath: record.originalPath).lastPathComponent)")
            } else {
                let r = await runWithPassword(password: password,
                                             arguments: ["/bin/mv", record.trashPath, record.originalPath])
                if r.success {
                    restoredCount += 1
                    await logger.log("✓ Recovered: \(URL(fileURLWithPath: record.originalPath).lastPathComponent)")
                } else {
                    await logger.log("✗ Could not recover: \(URL(fileURLWithPath: record.originalPath).lastPathComponent)")
                }
            }
        }

        await logger.log("Recovery complete — \(restoredCount)/\(records.count) file(s) recovered")
        return restoredCount > 0
    }

    // MARK: - System path guard

    // Paths that are macOS system/administrative directories.
    // Files here are never touched regardless of what a PKG receipt lists.
    private static let systemRoots: [String] = [
        "/",              // root filesystem — never trash
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/private/etc",
        "/private/var/db/receipts",   // receipt database — never delete directly
        "/Library/CoreServices",
        "/Library/SystemExtensions",
        "/Library/SystemMigration",
        "/Library/Security",
        "/Library/Apple",
        "/Library/Frameworks/Python.framework",
        "/Library/Frameworks/Ruby.framework",
        "/Library/Preferences/SystemConfiguration",
    ]

    // App Support directory names that must never be touched regardless of vendor token matching.
    // These belong to browsers, editors, and OS services — not audio plugins.
    private static let appSupportExclusions: Set<String> = [
        "code", "cursor", "visual studio code", "vscode",
        "chrome", "google chrome", "chromium",
        "firefox", "mozilla", "safari",
        "electron", "slack", "discord", "zoom", "teams", "notion",
        "dropbox", "onedrive", "google drive", "box",
        "1password", "bitwarden", "keybase",
        "iterm2", "terminal", "iterm",
        "xcode", "simulator", "instruments",
        "com.apple", "apple",
    ]

    private static func isSystemPath(_ path: String) -> Bool {
        systemRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    // Derives a short vendor/product name from a filename like
    // MARK: - Trash manifest

    // Writes a JSON file recording where each item landed in the Trash.
    // Returns the path to the manifest, or nil if writing failed.
    @discardableResult
    private static func writeTrashManifest(_ records: [TrashRecord],
                                           for fileName: String) -> String? {
        guard !records.isEmpty else { return nil }
        let safe = fileName
            .replacingOccurrences(of: "[^a-zA-Z0-9_\\-]", with: "_",
                                  options: .regularExpression)
            .prefix(40)
        let ts  = Int(Date().timeIntervalSince1970)
        let dir = NSHomeDirectory() + "/Library/Application Support/ATLAS/Manifests"
        let path = "\(dir)/\(ts)_\(safe).json"
        do {
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(records)
            try data.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    // MARK: - Bundle collapsing

    private static let bundleExts: Set<String> = [
        "component", "vst3", "vst", "aaxplugin", "app",
        "framework", "plugin", "kext", "appex", "bundle",
    ]

    private static func bundleRoot(for path: String) -> String {
        // Walk all the way to root and return the OUTERMOST bundle ancestor.
        // This ensures nested bundles (e.g. __Pace_Eden.bundle inside Serum2.aaxplugin)
        // collapse into the outermost bundle and get trashed as one unit.
        var url = URL(fileURLWithPath: path)
        var outermost: String? = nil
        while url.path != "/" {
            if bundleExts.contains(url.pathExtension.lowercased()) { outermost = url.path }
            url = url.deletingLastPathComponent()
        }
        return outermost ?? path
    }

    private static func collapseIntoBundles(_ paths: [String]) -> [String] {
        var roots      = Set<String>()
        var standalone = [String]()

        for path in paths {
            let root = bundleRoot(for: path)
            if root != path || bundleExts.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
                roots.insert(root)
            } else {
                standalone.append(path)
            }
        }

        let filtered = standalone.filter { p in
            !roots.contains(where: { p == $0 || p.hasPrefix($0 + "/") })
        }

        return Array(roots) + filtered
    }

    // Directories that are aggregate containers — their direct children are
    // always vendor-owned roots (e.g. /Library/Application Support/Avid).
    // We must never collapse a candidate list into one of those children.
    private static var aggregateDirs: Set<String> {
        let home = NSHomeDirectory()
        return [
            "/Library",
            "/Library/Application Support",
            "/Library/Audio/Plug-Ins",
            "/Library/Audio/Presets",
            "/Library/Audio/Sounds",
            "/Library/Audio/MIDI Drivers",
            "/Library/Application Support/Avid",   // Avid sub-tree is itself an aggregate
            "/Applications",
            home + "/Library/Application Support",
            home + "/Library/Audio/Plug-Ins",
            home + "/Library/Audio/Presets",
            home + "/Documents",
            home + "/Music",
        ]
    }

    private static func collapseByDirectory(_ paths: [String]) -> [String] {
        let protected  = protectedDirs
        let aggregates = aggregateDirs
        var current    = Set(paths)
        var changed    = true
        var iteration  = 0

        while changed {
            changed = false
            iteration += 1
            alog.notice("[ATLAS-ROLLBACK] collapseByDirectory iteration=\(iteration) candidates=\(current.count)")
            var byParent: [String: [String]] = [:]
            var keep = Set<String>()

            for path in current {
                let parent      = URL(fileURLWithPath: path).deletingLastPathComponent().path
                let grandparent = URL(fileURLWithPath: parent).deletingLastPathComponent().path
                // Never collapse into a protected dir, or into a direct child of an
                // aggregate dir (those are vendor-owned roots we cannot bulk-delete).
                let isVendorRoot = aggregates.contains(grandparent) || aggregates.contains(parent)
                if parent == "/" || protected.contains(parent) || protected.contains(path) || isVendorRoot {
                    keep.insert(path)
                } else {
                    byParent[parent, default: []].append(path)
                }
            }

            var next = keep
            for (parent, children) in byParent {
                let allItems   = (try? FileManager.default.contentsOfDirectory(atPath: parent)) ?? []
                let totalInDir = allItems.count
                // Only collapse if ATLAS tracked every item in the directory — a single
                // untracked file means user data or another app's data could be in there.
                let fullyOwned = totalInDir > 0 && children.count >= totalInDir
                let parentIsVendorRoot = aggregates.contains(
                    URL(fileURLWithPath: parent).deletingLastPathComponent().path
                ) || aggregates.contains(parent)

                if !protected.contains(parent) && !parentIsVendorRoot && fullyOwned {
                    next.insert(parent)
                    changed = true
                } else {
                    children.forEach { next.insert($0) }
                }
            }
            current = next
        }

        return Array(current)
    }

    // MARK: - Priority sort

    private static func priorityScore(_ path: String) -> Int {
        let ext   = URL(fileURLWithPath: path).pathExtension.lowercased()
        let lower = path.lowercased()

        switch ext {
        case "component":  return 0
        case "vst3":       return 1
        case "vst":        return 2
        case "aaxplugin":  return 3
        case "app":        return 4
        case "kext":       return 5
        default: break
        }

        if lower.hasPrefix("/library/audio")               { return 6  }
        if lower.hasPrefix("/library/application support") { return 7  }
        if lower.hasPrefix("/library/extensions")          { return 8  }
        if lower.hasPrefix("/library/launch")              { return 9  }
        if lower.hasPrefix("/library")                     { return 10 }
        if lower.contains("/library/audio")                { return 11 }
        if lower.contains("/library/application support")  { return 12 }
        if lower.contains("/library/preferences")          { return 13 }
        if lower.contains("/library/launch")               { return 14 }
        if lower.contains("/library")                      { return 15 }
        return 16
    }

    private static func sortByPriority(_ paths: [String]) -> [String] {
        paths.sorted { priorityScore($0) < priorityScore($1) }
    }

    // MARK: - Timed trash

    private enum RemoveResult { case done, failed, skipped }

    private static func itemTimeout(_ path: String) -> Double {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        switch ext {
        case "app":                          return 30
        case "component", "vst3", "vst",
             "aaxplugin", "kext", "bundle":  return 15
        default:
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return isDir.boolValue ? 20 : 6
        }
    }

    // Moves an item to the macOS Trash. Returns (result, actualTrashPath).
    // User-space paths use FileManager.trashItem; system paths use sudo mv → ~/.Trash/
    // followed by sudo chown so the user owns the item in Trash (Finder shows it correctly).
    private static func trashItem(path: String,
                                  password: String,
                                  seconds: Double) async -> (RemoveResult, String?) {
        let url = URL(fileURLWithPath: path)

        // User-space: FileManager.trashItem handles this natively
        var resultURL: NSURL? = nil
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultURL)
            return (.done, resultURL?.path)
        } catch {
            // Fall through to sudo path for root-owned / system files
        }

        // System-space: sudo mv to ~/.Trash/ (same volume — effectively instant)
        let trashDir = NSHomeDirectory() + "/.Trash"
        let dest     = uniqueTrashPath(for: path, in: trashDir)

        let mv = await runWithPassword(password: password,
                                      arguments: ["/bin/mv", path, dest])
        guard mv.success else { return (.failed, nil) }

        // Fix ownership so the item appears under the user's account in Finder Trash
        // and can be emptied without an admin prompt.
        let userName = NSUserName()
        _ = await runWithPassword(password: password,
                                  arguments: ["/usr/sbin/chown", "-R", userName, dest])

        return (.done, dest)
    }

    // Generates a unique destination path in trashDir to avoid overwriting existing items.
    private static func uniqueTrashPath(for path: String, in trashDir: String) -> String {
        let url  = URL(fileURLWithPath: path)
        let base = url.deletingPathExtension().lastPathComponent
        let ext  = url.pathExtension
        let fm   = FileManager.default

        var candidate = ext.isEmpty ? "\(trashDir)/\(base)" : "\(trashDir)/\(base).\(ext)"
        var counter   = 1
        while fm.fileExists(atPath: candidate) {
            candidate = ext.isEmpty
                ? "\(trashDir)/\(base) \(counter)"
                : "\(trashDir)/\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }

    // MARK: - Receipt file enumeration with timeout

    private static var protectedAncestors: Set<String> {
        let home = NSHomeDirectory()
        return [
            "/Library", "/Library/Application Support",
            "/Library/Audio", "/Library/Audio/Plug-Ins",
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3",
            "/Library/Audio/Plug-Ins/VST",
            "/Library/Extensions", "/Library/LaunchAgents", "/Library/LaunchDaemons",
            "/usr", "/usr/local", "/usr/local/lib", "/usr/local/bin",
            "/private", "/private/var",
            home, home + "/Library",
            home + "/Library/Application Support",
            home + "/Library/Audio", home + "/Library/Audio/Plug-Ins",
            home + "/Library/Preferences", home + "/Library/LaunchAgents",
        ]
    }

    private static func receiptFilesWithTimeout(receiptID: String,
                                                seconds: Double) async -> [String] {
        let process = Process()
        let pipe    = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments     = ["--files", receiptID]
        process.standardOutput = pipe
        process.standardError  = Pipe()
        guard (try? process.run()) != nil else { return [] }
        // Close our copy of the write end so readDataToEndOfFile() sees EOF when the process exits.
        // Without this, the Pipe object keeps the write fd open and readDataToEndOfFile blocks forever.
        pipe.fileHandleForWriting.closeFile()

        // Read pipe in a detached task so large receipts (10k+ files) never fill
        // the pipe buffer and deadlock the process before it can exit.
        let pipeReadTask = Task.detached { pipe.fileHandleForReading.readDataToEndOfFile() }

        let deadline = Date().addingTimeInterval(seconds)
        var cancelledMidway = false
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if cancellationRequested || Task.isCancelled {
                cancellationRequested = true
                cancelledMidway = true
                break
            }
        }
        if process.isRunning { process.terminate() }
        let outputData = await pipeReadTask.value
        _ = cancelledMidway  // used below via process.isRunning path

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let lineCount = output.components(separatedBy: "\n").filter { !$0.isEmpty }.count
        alog.notice("[ATLAS-RFWT] pipe read done for \(receiptID, privacy: .public) (\(outputData.count) bytes, \(lineCount) lines) — dispatching installLocation")
        // PKGReceiptScanner.installLocation calls runProcess which uses Thread.sleep.
        // Run it on a background thread so the main thread (and Cancel button) stay live.
        let location = await Task.detached { PKGReceiptScanner.installLocation(forReceipt: receiptID) }.value
        alog.notice("[ATLAS-RFWT] installLocation done for \(receiptID, privacy: .public): '\(location, privacy: .public)'")
        let anchors  = protectedAncestors

        // Bundle extensions that are directories but should be treated as files
        let bundleExts: Set<String> = [
            "component", "vst3", "vst", "aaxplugin", "app",
            "framework", "plugin", "kext", "appex", "bundle"
        ]
        let fm = FileManager.default
        let rawLines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        alog.notice("[ATLAS-RFWT] path filter ENTER — \(rawLines.count) raw lines from pkgutil, receipt=\(receiptID, privacy: .public)")
        let filterStart = Date()

        let result = rawLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .compactMap { p -> String? in
                let abs: String
                if p.hasPrefix("/") { abs = p }
                else if location == "/" { abs = "/\(p)" }
                else { abs = "\(location)/\(p)" }
                guard !anchors.contains(abs) else { return nil }
                // Drop plain directory entries — only keep files and bundle packages.
                // pkgutil --files includes directory entries; trashing a plain directory
                // would wipe all other apps' files that happen to live there.
                let ext = URL(fileURLWithPath: abs).pathExtension.lowercased()
                var isDir: ObjCBool = false
                fm.fileExists(atPath: abs, isDirectory: &isDir)
                if isDir.boolValue && !bundleExts.contains(ext) {
                    return nil  // plain directory — skip it, we'll trash its tracked contents individually
                }
                return abs
            }

        alog.notice("[ATLAS-RFWT] path filter EXIT — \(String(format: "%.1f", Date().timeIntervalSince(filterStart)))s \(rawLines.count) raw → \(result.count) file paths, receipt=\(receiptID, privacy: .public)")
        return result
    }

    // MARK: - Empty directory cleanup (permanent — empty dirs have no data)

    private static var protectedDirs: Set<String> {
        let home = NSHomeDirectory()
        return [
            "/Applications", "/Library", "/Library/Audio",
            "/Library/Audio/Plug-Ins", "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3", "/Library/Audio/Plug-Ins/VST",
            "/Library/Application Support", "/Library/LaunchAgents",
            "/Library/LaunchDaemons", "/Library/Extensions",
            home, home + "/Library",
            home + "/Library/Application Support",
            home + "/Library/Audio", home + "/Library/Audio/Plug-Ins",
            home + "/Library/Preferences", home + "/Library/LaunchAgents",
            home + "/Library/Audio/Presets",
        ]
    }

    @discardableResult
    private static func cleanupEmptyDirs(from removedPaths: [String],
                                         password: String) async -> [String] {
        var parents    = Set<String>()
        let protected  = protectedDirs
        let aggregates = aggregateDirs

        for path in removedPaths {
            var url = URL(fileURLWithPath: path).deletingLastPathComponent()
            for _ in 0..<5 {
                let p           = url.path
                let grandparent = url.deletingLastPathComponent().path
                if protected.contains(p) || p == "/" { break }
                if aggregates.contains(p) { break }
                // Add p before checking grandparent so vendor roots directly inside
                // aggregate dirs (e.g. /Library/Application Support/iZotope/) are
                // included — their emptiness check is the correct guard, not this one.
                parents.insert(p)
                if aggregates.contains(grandparent) { break }
                url = url.deletingLastPathComponent()
            }
        }

        var cleaned: [String] = []
        for dir in parents.sorted(by: { $0.count > $1.count }) {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            if contents.isEmpty {
                if case .done = await hardRemove(path: dir, password: password, seconds: 4) {
                    cleaned.append(dir)
                }
            }
        }
        return cleaned
    }

    // Permanent delete — only used for empty directories where there is nothing to preserve.
    private static func hardRemove(path: String,
                                   password: String,
                                   seconds: Double) async -> RemoveResult {
        if (try? FileManager.default.removeItem(atPath: path)) != nil { return .done }

        let process   = Process()
        let inputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments     = ["-S", "/bin/rm", "-rf", path]
        process.standardInput  = inputPipe
        process.standardOutput = Pipe()
        process.standardError  = Pipe()

        guard (try? process.run()) != nil else { return .failed }
        inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
        inputPipe.fileHandleForWriting.closeFile()

        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if process.isRunning { process.terminate(); return .skipped }
        return process.terminationStatus == 0 ? .done : .failed
    }

    // MARK: - Shared process helper

    // Timeout: 30s covers large sudo mv operations. Polls cancellation flag so Cancel
    // stops the next pending operation rather than waiting for a hung process forever.
    @discardableResult
    private static func runWithPassword(password: String,
                                        arguments: [String],
                                        timeout: TimeInterval = 30) async -> (success: Bool, output: String) {
        let process    = Process()
        let inputPipe  = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments     = ["-S"] + arguments
        process.standardInput  = inputPipe
        process.standardOutput = outputPipe
        process.standardError  = outputPipe

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            // Close our copy of the output pipe write end so readDataToEndOfFile() sees EOF on process exit.
            outputPipe.fileHandleForWriting.closeFile()
        } catch {
            return (false, error.localizedDescription)
        }

        let pipeReadTask = Task.detached { outputPipe.fileHandleForReading.readDataToEndOfFile() }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        var cancelledMidway = false
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if cancellationRequested || Task.isCancelled {
                cancellationRequested = true
                cancelledMidway = true
                break
            }
        }
        if process.isRunning {
            timedOut = !cancelledMidway
            process.terminate()
        }
        let outputData = await pipeReadTask.value

        let exitCode = process.terminationStatus
        let out = String(data: outputData, encoding: .utf8) ?? ""
        return (exitCode == 0 && !timedOut, out)
    }

    // Extracts short vendor/product tokens from PKG receipt IDs and file names.
    // e.g. "com.oeksound.soothe2.au" → ["oeksound", "soothe2"]
    //      "com.fabfilter.pro-q-3"   → ["fabfilter", "pro-q-3"]
    // Tokens < 4 chars or that are generic macOS terms are excluded.
    // Used to locate vendor preference and cache files for uninstall.
    private static func vendorTokensFromReceipts(_ ids: [String]) -> Set<String> {
        let blocklist: Set<String> = [
            "com","net","org","io","app","pkg","audio","plug","ins","vst3","vst",
            "aax","macos","osx","mac","flare","xcode","xcodecheck","check","content",
            "user","plugin","common","support","data","install","setup","trial","demo",
            "library","framework","kext","bundle","extension","agent","helper","code",
        ]
        var tokens = Set<String>()

        func addToken(_ raw: String) {
            let lower = raw.lowercased()
            guard lower.count >= 5,                     // min 5 to avoid short common words
                  lower.first?.isLetter == true,
                  !blocklist.contains(lower) else { return }
            let withoutFirst = lower.dropFirst()
            if withoutFirst.allSatisfy({ $0.isNumber || $0 == "." }) { return }
            tokens.insert(lower)
        }

        for id in ids {
            let stripped = id
                .replacingOccurrences(of: "com.", with: "")
                .replacingOccurrences(of: "net.", with: "")
                .replacingOccurrences(of: "org.", with: "")
            let parts = stripped.components(separatedBy: CharacterSet(charactersIn: ".-_ "))
            for part in parts {
                addToken(part)

                // If a part is a long concatenated string like "oeksoundsoothe2v1",
                // extract letter-run segments and ALSO emit prefix substrings at
                // increasing lengths (5..12). This ensures "oeksound" is produced
                // from "oeksoundsoothe2v1" without needing bidirectional matching.
                let lower = part.lowercased()
                if lower.count > 10 {
                    var start = lower.startIndex
                    var i = lower.startIndex
                    while i <= lower.endIndex {
                        let atEnd = (i == lower.endIndex)
                        let isLetter = !atEnd && lower[i].isLetter
                        if !isLetter {
                            let run = String(lower[start..<i])
                            if run.count >= 5 {
                                addToken(run)
                                // Emit prefix slices so "oeksound" comes out of "oeksoundsoothe"
                                for len in stride(from: 5, through: min(run.count, 12), by: 1) {
                                    let prefixEnd = run.index(run.startIndex, offsetBy: len)
                                    addToken(String(run[run.startIndex..<prefixEnd]))
                                }
                            }
                            i = atEnd ? lower.endIndex : lower.index(after: i)
                            start = i
                        } else {
                            i = lower.index(after: i)
                        }
                    }
                }
            }
        }
        return tokens
    }
}
