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

        // ── Pre-flight: receipt collision check ───────────────────────────────
        // If any stored receipt ID is also claimed by another live product, ATLAS
        // cannot know which product owns the associated files. Halt immediately.
        if !record.pkgReceiptIDs.isEmpty {
            let liveOthers = otherRecords.filter { $0.id != record.id && $0.status == .success }
            for other in liveOthers {
                if let collidingID = record.pkgReceiptIDs.first(where: { other.pkgReceiptIDs.contains($0) }) {
                    let selfName  = URL(fileURLWithPath: record.fileName).deletingPathExtension().lastPathComponent
                    let otherName = URL(fileURLWithPath: other.fileName).deletingPathExtension().lastPathComponent
                    let msg = "Cannot safely uninstall \"\(selfName)\" — receipt ID \"\(collidingID)\" is also claimed by \"\(otherName)\". Uninstall both products together or resolve the conflict manually."
                    await logger.log("⛔ \(msg)")
                    alog.notice("[ATLAS-ROLLBACK] PRE-FLIGHT HALT — receipt collision: \(collidingID, privacy: .public) shared with \(otherName, privacy: .public)")
                    return RollbackResult(success: false, removedFiles: [], failedFiles: [], detail: msg)
                }
            }
        }

        // Pre-flight: destination path collision check
        // If any tracked installed file path is also in another live record, halt.
        if !record.installedFiles.isEmpty {
            let myPaths = Set(record.installedFiles.map(\.destinationPath))
            let liveOthers = otherRecords.filter { $0.id != record.id && $0.status == .success }
            for other in liveOthers {
                let otherPaths = other.installedFiles.map(\.destinationPath)
                if let collidingPath = myPaths.first(where: { otherPaths.contains($0) }) {
                    let selfName  = URL(fileURLWithPath: record.fileName).deletingPathExtension().lastPathComponent
                    let otherName = URL(fileURLWithPath: other.fileName).deletingPathExtension().lastPathComponent
                    let msg = "Cannot safely uninstall \"\(selfName)\" — destination path \"\(collidingPath)\" is also claimed by \"\(otherName)\". Resolve the conflict manually."
                    await logger.log("⛔ \(msg)")
                    alog.notice("[ATLAS-ROLLBACK] PRE-FLIGHT HALT — path collision: \(collidingPath, privacy: .public) shared with \(otherName, privacy: .public)")
                    return RollbackResult(success: false, removedFiles: [], failedFiles: [], detail: msg)
                }
            }
        }

        var candidates = Set<String>()
        var runtimeTrustedPaths = Set<String>()

        // positivelyOwnedPaths: the exact set of paths that satisfy the ownership invariant.
        // Rule A: explicitly listed in this record's installedFiles.
        // Rule B: returned by pkgutil for a receipt ID stored in this record's pkgReceiptIDs.
        // Nothing else qualifies. Built incrementally alongside candidates below.
        var positivelyOwnedPaths = Set<String>()

        // Disabled format files in ATLAS storage — include them as uninstall candidates.
        // These are stored at disabledStoragePath (not the original system path, which is empty).
        // We record the originalPath in TrashRecord so recovery knows where to restore them.
        if let disabledEntries = record.disabledFormats, !disabledEntries.isEmpty {
            await logger.log("Disabled formats: \(disabledEntries.count) — including in uninstall")
            for entry in disabledEntries {
                candidates.insert(entry.disabledStoragePath)
                positivelyOwnedPaths.insert(entry.disabledStoragePath)
            }
        }

        // Manifest path: add explicitly tracked files (license assets, ZIP-installed plugins, etc.)
        if !record.installedFiles.isEmpty {
            onProgress?(0.18, "Building uninstall plan|Assembling file list")
            for path in record.installedFiles.map(\.destinationPath) {
                guard !otherOwnedPaths.contains(path) else { continue }
                candidates.insert(path)
                positivelyOwnedPaths.insert(path)
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

            // Heuristic receipts (name-matched, prefix-matched) are diagnostic only.
            // They do NOT authorize deletion — only record.pkgReceiptIDs does (rule B).
            // Cross-record filter retained for logging accuracy.
            let otherReceiptIDs = Set(otherRecords
                .filter { $0.id != record.id && $0.status == .success }
                .flatMap(\.pkgReceiptIDs))
            let safeByName   = freshByName.filter   { !otherReceiptIDs.contains($0) }
            let safeByPrefix = freshByPrefix.filter { !otherReceiptIDs.contains($0) }
            let heuristicIDs = Set(safeByName + safeByPrefix).subtracting(record.pkgReceiptIDs)
            if !heuristicIDs.isEmpty {
                await logger.log("ℹ Heuristic receipts found (not used for deletion): \(heuristicIDs.sorted().joined(separator: ", "))")
            }

            // Only stored receipt IDs authorize deletion.
            let allReceiptIDs = Array(Set(record.pkgReceiptIDs))
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
                        positivelyOwnedPaths.insert(location)
                    } else if let name = pkgName, !name.isEmpty {
                        for dir in ["/Library/Audio/Presets/\(name)",
                                    "/Library/Application Support/\(name)",
                                    NSHomeDirectory() + "/Library/Audio/Presets/\(name)"]
                        where FileManager.default.fileExists(atPath: dir) {
                            candidates.insert(dir)
                            positivelyOwnedPaths.insert(dir)
                        }
                    }
                } else {
                    for f in files where !otherOwnedPaths.contains(f) {
                        candidates.insert(f)
                        positivelyOwnedPaths.insert(f)
                    }
                }
            }
            await logger.log("Receipt scan complete — \(candidates.count) raw candidate(s)")
        }

        // Runtime-created paths (filesystem diff at install time) — diagnostic and deferred cleanup only.
        // These paths are NOT independently authorized for deletion.
        // Files: only deletable via installedFiles or pkgReceiptIDs (already in candidates above).
        // Directories: deferred — Phase 6 cleanupEmptyDirs removes them if empty after file deletion.
        // Owning files inside a directory does NOT authorize deleting the directory itself.
        for path in (record.runtimeCreatedPaths ?? []) {
            let name = URL(fileURLWithPath: path).lastPathComponent
            guard !otherOwnedPaths.contains(path) else { continue }
            guard !isProtectedPath(path, productFileName: record.fileName) else {
                alog.notice("[ATLAS-ROLLBACK] runtimeCreatedPath skipped (protected namespace): \(path, privacy: .public)")
                continue
            }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                await logger.log("ℹ Runtime-created directory deferred to Phase 6 cleanup: \(name)")
                alog.notice("[ATLAS-ROLLBACK] runtimeCreatedPath directory deferred: \(path, privacy: .public)")
            } else {
                // File paths require positive ownership to be deleted.
                // If already in candidates via installedFiles or receipt path, this is a no-op.
                // If not in positivelyOwnedPaths, timing evidence alone does not authorize deletion.
                if !positivelyOwnedPaths.contains(path) {
                    await logger.log("⚠ Runtime-created file excluded (no positive ownership evidence): \(name)")
                    alog.notice("[ATLAS-ROLLBACK] runtimeCreatedPath file excluded: \(path, privacy: .public)")
                }
                // Already in candidates if positively owned; no action needed either way.
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
        let ownedPaths   = Set(afterBundles)
        // Trust bundle roots — bypass Phase 3 untracked-items safety check.
        let knownBundleExts: Set<String> = [
            "component", "vst3", "vst", "aaxplugin", "app",
            "framework", "plugin", "kext", "appex", "bundle"
        ]
        for path in afterBundles where knownBundleExts.contains(
            URL(fileURLWithPath: path).pathExtension.lowercased()) {
            runtimeTrustedPaths.insert(path)
        }

        // Compute the bundle-collapsed form of positively-owned paths only.
        // collapseByDirectory uses this to require every real directory item to be
        // positively owned before promoting the directory to a single candidate.
        let positivelyOwnedBundles = Set(collapseIntoBundles(Array(positivelyOwnedPaths)))

        let afterDirs = collapseByDirectory(afterBundles, positivelyOwned: positivelyOwnedBundles)
        if afterDirs.count < afterBundles.count {
            await logger.log("Folder collapse: \(afterBundles.count) → \(afterDirs.count) item(s)")
        }

        // Directories produced by collapseByDirectory were verified as fully owned
        // during collapse — every meaningful item in them belongs to this installation.
        // Add them to runtimeTrustedPaths so Phase 3 does not re-check against the
        // pre-collapse ownedPaths (which holds individual files, not collapsed dirs).
        let afterBundlesSet = Set(afterBundles)
        for path in afterDirs where !afterBundlesSet.contains(path) {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue { runtimeTrustedPaths.insert(path) }
        }

        let sorted = sortByPriority(afterDirs)
        let previewNames = sorted.prefix(5).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
        await logger.log("Uninstall plan: \(sorted.count) item(s) — \(previewNames)\(sorted.count > 5 ? "…" : "")")
        alog.notice("[ATLAS-ROLLBACK] PLAN COMPLETE — \(sorted.count) item(s) elapsed=\(String(format: "%.1f", Date().timeIntervalSince(rollbackStart)))s")
        await logger.log("Moving files to Trash...")
        onProgress?(0.28, "Moving to Trash|Preparing \(sorted.count) item\(sorted.count == 1 ? "" : "s")")

        // ── Phase 3: Move each item to Trash ──────────────────────────────────
        // ALL items — bundles, directories, and loose files — go into one named
        // ATLAS Uninstall Package folder in Trash. This keeps the user's Trash clean,
        // makes the uninstall atomic from the user's perspective, and gives recovery
        // a single well-known location to read from. If the package folder cannot be
        // created, each item falls back to individual trashItem() calls.
        // All ownership decisions, guards, and safety checks are unchanged.
        let productLabel = URL(fileURLWithPath: record.fileName).deletingPathExtension().lastPathComponent
        let packageFolder = createUninstallPackage(productLabel: productLabel,
                                                   fileName: record.fileName,
                                                   password: password)
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
                // Fail closed: if directory contents cannot be read for any reason,
                // skip deletion rather than assuming it is safe to proceed.
                guard let dirContents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
                    await logger.log("⚠ Skipped directory (contents unreadable — cannot verify ownership): \(name)")
                    alog.notice("[ATLAS-ROLLBACK] Phase3 skip — contentsOfDirectory failed for: \(path, privacy: .public)")
                    onProgress?(pct, "")
                    continue
                }
                let untrackedItems = dirContents.filter { item in
                    guard !fsMetadata.contains(item) else { return false }
                    let full = (path as NSString).appendingPathComponent(item)
                    return !ownedPaths.contains(full)
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

            // Defense-in-depth: block ATLAS/Apple/unrelated-vendor namespace files
            // even if they survived upstream filters (e.g. from runtimeCreatedPaths).
            if isProtectedPath(path, productFileName: record.fileName) {
                await logger.log("⚠ Skipped (protected namespace): \(name)")
                alog.notice("[ATLAS-ROLLBACK] Phase3 PROTECTED skip: \(path, privacy: .public)")
                onProgress?(pct, "")
                continue
            }

            await logger.log("Trashing \(name)...")
            alog.notice("[ATLAS-ROLLBACK] Phase3 item \(i + 1)/\(totalItems) START: \(path, privacy: .public)")
            onProgress?(pct, "Moving to Trash|\(name) (\(i + 1) of \(totalItems))")

            let trashStart = Date()
            let (result, trashPath) = await moveIntoPackage(path: path,
                                                            packageFolder: packageFolder,
                                                            password: password)
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
                await logger.log("⚠ Skipped (timeout exceeded): \(name)")
            case .failed:
                alog.notice("[ATLAS-ROLLBACK] Phase3 item \(i + 1)/\(totalItems) FAILED: \(path, privacy: .public)")
                await logger.log("✗ Could not trash: \(name)")
                failed.append(path)
            }

            onProgress?(pct, "Moving to Trash|\(name) (\(i + 1) of \(totalItems))")
        }

        // Fix ownership so the package folder appears under the user's account in Finder Trash.
        if let pkg = packageFolder {
            let userName = NSUserName()
            _ = await runWithPassword(password: password,
                                      arguments: ["/usr/sbin/chown", "-R", userName, pkg])
        }

        // Write README after chown and after trashRecords is final — reflects actual completed state.
        if let pkg = packageFolder {
            writeUninstallReadme(to: pkg,
                                 productLabel: productLabel,
                                 trashRecords: trashRecords,
                                 failedPaths: failed)
        }

        if alreadyGoneCount > 0 {
            await logger.log("Skipped \(alreadyGoneCount) already-removed path(s)")
        }

        // ── Phase 3b: Back up PKG receipt files into the uninstall package ────
        // Copies /var/db/receipts/PKGID.{plist,bom} into the package folder and
        // records TrashRecords so restore() can move them back to /var/db/receipts/.
        // This runs after the README is written (receipt paths are internal, not
        // user-facing) but before the manifest, so recovery sees them.
        // pkgutil --forget in Phase 5 is unchanged — it remains the primary removal
        // mechanism; this step only preserves the files so recovery can undo it.
        if let pkg = packageFolder, !record.pkgReceiptIDs.isEmpty {
            let receiptDir = "/var/db/receipts"
            var backedUpCount = 0
            for id in record.pkgReceiptIDs {
                for ext in ["plist", "bom"] {
                    let src = "\(receiptDir)/\(id).\(ext)"
                    let dst = "\(pkg)/\(id).\(ext)"
                    let cp = await runWithPassword(password: password,
                                                  arguments: ["/bin/cp", src, dst])
                    if cp.success {
                        trashRecords.append(TrashRecord(originalPath: src, trashPath: dst))
                        backedUpCount += 1
                    }
                }
            }
            if backedUpCount > 0 {
                await logger.log("Backed up \(backedUpCount) receipt file(s) for recovery")
            }
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
            // Safety: do not forget a receipt that is also claimed by another live record.
            // Forgetting removes the pkgutil ownership record; doing so for a shared ID
            // would corrupt the other product's uninstall.
            if let claimant = otherRecords.first(where: { $0.id != record.id && $0.status == .success && $0.pkgReceiptIDs.contains(id) }) {
                let claimantName = URL(fileURLWithPath: claimant.fileName).deletingPathExtension().lastPathComponent
                await logger.log("⚠ Skipped forget — receipt \(id) also claimed by \"\(claimantName)\"")
                alog.notice("[ATLAS-ROLLBACK] Phase5 skip forget — \(id, privacy: .public) claimed by \(claimantName, privacy: .public)")
                continue
            }
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
                // Path already exists on disk. This happens when a child of this
                // directory was restored first and mkdir -p recreated the parent shell.
                // If the Trash item is also a directory, merge its top-level contents
                // into the existing directory so nothing is silently abandoned.
                var trashIsDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: record.trashPath, isDirectory: &trashIsDir),
                   trashIsDir.boolValue {
                    let items = (try? FileManager.default.contentsOfDirectory(atPath: record.trashPath)) ?? []
                    for item in items {
                        let src = (record.trashPath as NSString).appendingPathComponent(item)
                        let dst = (record.originalPath as NSString).appendingPathComponent(item)
                        guard !FileManager.default.fileExists(atPath: dst) else { continue }
                        if (try? FileManager.default.moveItem(atPath: src, toPath: dst)) == nil {
                            _ = await runWithPassword(password: password, arguments: ["/bin/mv", src, dst])
                        }
                    }
                    await logger.log("✓ Merged: \(URL(fileURLWithPath: record.originalPath).lastPathComponent)")
                }
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

        // ── Post-restore cleanup: remove ATLAS Uninstall Package if complete ──
        // Identifies package roots referenced by this manifest. Removes the package
        // folder only when no Trash items from this manifest remain inside it —
        // meaning every item was either restored or is no longer present in Trash.
        // Partial recoveries leave the package intact for a future retry.
        var packageRoots = Set<String>()
        for rec in records {
            if let root = uninstallPackageRoot(from: rec.trashPath) {
                packageRoots.insert(root)
            }
        }
        for root in packageRoots {
            let anyRemaining = records.contains { rec in
                guard let recRoot = uninstallPackageRoot(from: rec.trashPath) else { return false }
                return recRoot == root && FileManager.default.fileExists(atPath: rec.trashPath)
            }
            if !anyRemaining {
                try? FileManager.default.removeItem(atPath: root)
                await logger.log("Removed ATLAS Uninstall Package (recovery complete)")
            }
        }

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

    // Returns true for paths that must never be deleted regardless of what the
    // installation record says. Covers ATLAS's own files, Apple-namespaced plists,
    // and preference files belonging to a different vendor than the product being
    // uninstalled (detected by requiring at least one product-name token in the filename).
    private static func isProtectedPath(_ path: String, productFileName: String) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()

        // ATLAS self-protection
        if filename.hasPrefix("com.atlas.atlas") { return true }
        // System process plists that appear in ~/Library/Preferences during installs
        if filename.hasPrefix("contextstoreagent") { return true }
        // Apple-namespaced plists
        if filename.hasPrefix("com.apple.") { return true }

        // For preference files: require at least one product-name token in the filename
        // so that unrelated-vendor plists captured by the filesystem diff are blocked.
        let prefDir = (NSHomeDirectory() + "/Library/Preferences/").lowercased()
        if path.lowercased().hasPrefix(prefDir) {
            let tokens = productFileName
                .replacingOccurrences(of: ".pkg", with: "")
                .replacingOccurrences(of: ".dmg", with: "")
                .replacingOccurrences(of: ".iso", with: "")
                .components(separatedBy: CharacterSet(charactersIn: " _-."))
                .map { $0.lowercased() }
                .filter { $0.count >= 4 }
            // If no product token appears in the preference filename, it belongs to
            // a different vendor and must not be deleted.
            if !tokens.isEmpty && !tokens.contains(where: { filename.contains($0) }) {
                return true
            }
        }
        return false
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

    // macOS-generated filesystem metadata — never installed by any product, never user content.
    // Excluded from directory ownership and emptiness checks so these artifacts do not
    // prevent ATLAS from removing product-specific directories it fully owns.
    private static let fsMetadata: Set<String> = [".DS_Store", ".localized"]

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

    // positivelyOwned: the bundle-collapsed set of paths that satisfy the ownership invariant
    // (installedFiles or pkgReceiptIDs receipts). A directory may only be promoted to a single
    // deletion candidate when every real non-metadata item in it is in this set. Count-matching
    // alone is not sufficient — identity of each item must be verified.
    private static func collapseByDirectory(_ paths: [String], positivelyOwned: Set<String>) -> [String] {
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
                let directItems = allItems.filter { !fsMetadata.contains($0) }
                // Ownership invariant: every real item in the directory must be positively owned.
                // Count-matching alone is not sufficient — identity of each item is verified.
                let fullyOwned = !directItems.isEmpty && directItems.allSatisfy { item in
                    positivelyOwned.contains((parent as NSString).appendingPathComponent(item))
                }
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

    // Groups individually approved loose files into a single ATLAS Trash container folder.
    // All ownership decisions were made before calling this — this is presentation routing only.
    // Creates the ATLAS Uninstall Package folder in ~/.Trash/ and writes READ THIS.txt.
    // Returns the package folder path on success, nil on failure (callers fall back to trashItem).
    private static func createUninstallPackage(productLabel: String,
                                               fileName: String,
                                               password: String) -> String? {
        let trashDir = NSHomeDirectory() + "/.Trash"
        let safeName = productLabel
            .replacingOccurrences(of: "[^a-zA-Z0-9 _\\-]", with: "_", options: .regularExpression)
            .prefix(40)
        let uuid8 = UUID().uuidString.prefix(8)
        let pkg = uniqueTrashPath(
            for: "\(trashDir)/ATLAS — \(safeName) — Uninstall Package — \(uuid8)",
            in: trashDir)

        guard (try? FileManager.default.createDirectory(atPath: pkg,
                                                        withIntermediateDirectories: true)) != nil else {
            return nil
        }

        return pkg
    }

    // Writes READ THIS.txt into the ATLAS Uninstall Package after the uninstall completes.
    // Called once, after chown, so the folder is user-owned and trashRecords is final.
    private static func writeUninstallReadme(to pkg: String,
                                             productLabel: String,
                                             trashRecords: [TrashRecord],
                                             failedPaths: [String]) {
        let packageID = URL(fileURLWithPath: pkg).lastPathComponent
            .components(separatedBy: " — ").last ?? pkg

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        let dateString = formatter.string(from: Date())

        let inventoryLines = trashRecords
            .map { "  \($0.originalPath)" }
            .sorted()
            .joined(separator: "\n")

        var failedSection = ""
        if !failedPaths.isEmpty {
            let failedLines = failedPaths.sorted().map { "  \($0)" }.joined(separator: "\n")
            failedSection = """


            Items that could not be moved (\(failedPaths.count)):
            \(failedLines)
            """
        }

        let readmeText = """
            --------------------------------

            ATLAS Uninstall Recovery Package

            Product:
            \(productLabel)

            Uninstall Date:
            \(dateString)

            Uninstall Package ID:
            \(packageID)

            Items successfully moved (\(trashRecords.count)):
            \(inventoryLines)\(failedSection)

            This folder contains files removed during the ATLAS uninstall process.

            ATLAS organized these files into this recovery package so they can be restored using:

            ATLAS → History → Undo Uninstall

            IMPORTANT:
            Do not rename, move, edit, or modify files inside this folder if you want ATLAS recovery to remain available.

            You may permanently delete this entire folder if you no longer need recovery.

            Created by ATLAS.

            --------------------------------
            """
        try? readmeText.write(toFile: pkg + "/READ THIS.txt", atomically: true, encoding: .utf8)
    }

    // Moves a single item into the ATLAS Uninstall Package folder.
    // If packageFolder is nil (creation failed), falls back to trashItem().
    // Handles name conflicts inside the package folder with a timestamp suffix.
    private static func moveIntoPackage(path: String,
                                        packageFolder: String?,
                                        password: String) async -> (RemoveResult, String?) {
        guard let pkg = packageFolder else {
            let (r, tp) = await trashItem(path: path, password: password, seconds: itemTimeout(path))
            return (r, tp)
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let dest = uniqueTrashPath(for: "\(pkg)/\(name)", in: pkg)

        let mv = await runWithPassword(password: password, arguments: ["/bin/mv", path, dest])
        if mv.success {
            return (.done, dest)
        }
        // Fallback: try user-space move
        if (try? FileManager.default.moveItem(atPath: path, toPath: dest)) != nil {
            return (.done, dest)
        }
        return (.failed, nil)
    }

    // Extracts the ATLAS Uninstall Package root from a trashPath.
    // Package items sit directly inside the package folder:
    //   ~/.Trash/ATLAS — Product — Uninstall Package — UUID/itemname
    // Returns nil for paths not inside a recognized package (e.g. fallback trashItem paths).
    private static func uninstallPackageRoot(from trashPath: String) -> String? {
        guard trashPath.contains("/ATLAS — ") && trashPath.contains(" — Uninstall Package — ") else {
            return nil
        }
        // The package root is the parent directory of the item path.
        let parent = URL(fileURLWithPath: trashPath).deletingLastPathComponent().path
        // Verify it looks like ~/.Trash/ATLAS — … — Uninstall Package — UUID
        guard URL(fileURLWithPath: parent).lastPathComponent.hasPrefix("ATLAS — ") else { return nil }
        return parent
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
                else {
                    let raw = "\(location)/\(p)"
                    abs = raw.hasPrefix("/") ? raw : "/\(raw)"
                }
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
            // Treat a failed directory read as unreadable, not empty.
            // Never call hardRemove if we cannot confirm the directory is actually empty.
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else {
                alog.notice("[ATLAS-ROLLBACK] cleanupEmptyDirs: cannot read directory, skipping: \(dir, privacy: .public)")
                continue
            }
            if contents.filter({ !fsMetadata.contains($0) }).isEmpty {
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
