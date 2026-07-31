import Foundation

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

    static var cancellationRequested = false

    static func cancelRollback() {
        cancellationRequested = true
    }

    // MARK: - Entry point

    static func rollback(record: InstallRecord,
                         otherRecords: [InstallRecord] = [],
                         logger: Logger,
                         onProgress: (@Sendable (Double, String) -> Void)? = nil) async -> RollbackResult {
        cancellationRequested = false
        await logger.log("--- Rollback: \(record.fileName) ---")

        guard let password = KeychainManager.loadPassword() else {
            await logger.log("No password found in Keychain")
            return RollbackResult(success: false, removedFiles: [], failedFiles: [],
                                 detail: "No password stored.")
        }

        var removed:      [String]      = []
        var failed:       [String]      = []
        var trashRecords: [TrashRecord] = []

        // ── Phase 1: Collect candidate paths (tracked files + PKG receipts only) ──
        // ATLAS only removes what it recorded at install time — nothing else.
        await logger.log("Scanning receipts...")
        var candidates: [String] = []
        candidates += record.installedFiles.map(\.destinationPath)

        // Supplement stored receipt IDs with fresh scans — catches any receipts that
        // weren't flushed to disk when we recorded them at install time.
        let freshByName = PKGReceiptScanner.findReceiptsByName(record.fileName)

        // Also use TITAN MEMORY™ known receipt prefixes for confirmed products
        let titanEntry  = TitanMemory.shared.lookup(name: record.fileName)
        let allInstalled = PKGReceiptScanner.snapshotReceipts()
        let freshByPrefix: [String] = (titanEntry?.knownReceiptPrefixes ?? []).flatMap { prefix in
            allInstalled.filter { $0.hasPrefix(prefix) }
        }

        let allReceiptIDs = Array(Set(record.pkgReceiptIDs + freshByName + freshByPrefix))
        if allReceiptIDs.count > record.pkgReceiptIDs.count {
            await logger.log("Supplemented \(record.pkgReceiptIDs.count) stored receipts with \(allReceiptIDs.count - record.pkgReceiptIDs.count) additional found by name")
        }

        for receiptID in allReceiptIDs {
            // Check cancellation between each receipt so Cancel is responsive during Preparing
            if cancellationRequested {
                await logger.log("Uninstall cancelled during receipt scan.")
                return RollbackResult(success: false, removedFiles: [], failedFiles: [],
                                     detail: "Cancelled.")
            }
            let files = receiptFilesWithTimeout(receiptID: receiptID, seconds: 10)
            await logger.log("Receipt \(receiptID): \(files.count) paths")
            if files.isEmpty {
                // Timeout or no files — fall back to the PKG install location.
                // Packages like Serum 2 Presets have 10k+ files; pkgutil --files
                // takes too long. Use pkgutil --pkg-info to get the vendor directory.
                let location = PKGReceiptScanner.installLocation(forReceipt: receiptID)
                let pkgName  = PKGReceiptScanner.pkgName(forReceipt: receiptID)
                // Only add if this resolves to a vendor-specific directory (not a
                // shared container like /Library/Audio/Plug-Ins).
                let sharedDirs: Set<String> = [
                    "/Library/Audio/Plug-Ins/Components",
                    "/Library/Audio/Plug-Ins/VST3",
                    "/Library/Audio/Plug-Ins/VST",
                    "/Library/Application Support/Avid/Audio/Plug-Ins",
                    "/Library/Audio/Plug-Ins",
                    "/Library/Application Support",
                    "/Library/Audio/Presets",
                    "/Library"
                ]
                if !location.isEmpty && location != "/" && !sharedDirs.contains(location) {
                    await logger.log("Receipt \(receiptID): timed out — using install location: \(location)")
                    candidates.append(location)
                } else if let name = pkgName, !name.isEmpty {
                    // Try to find a vendor directory matching the package name
                    let vendorDirs = [
                        "/Library/Audio/Presets/\(name)",
                        "/Library/Application Support/\(name)",
                        NSHomeDirectory() + "/Library/Audio/Presets/\(name)",
                    ]
                    for dir in vendorDirs where FileManager.default.fileExists(atPath: dir) {
                        await logger.log("Receipt \(receiptID): adding vendor dir: \(dir)")
                        candidates.append(dir)
                    }
                }
            } else {
                candidates += files
            }
        }

        if cancellationRequested {
            await logger.log("Uninstall cancelled during preparation.")
            return RollbackResult(success: false, removedFiles: [], failedFiles: [], detail: "Cancelled.")
        }

        // ── Phase 1b: Runtime-created paths (precise, snapshot-based) ────────
        // These are folders that appeared in Library dirs DURING the install
        // (not in any PKG receipt) — recorded at install time via filesystem diff.
        // These are trusted completely — the whole point of recording them is we KNOW
        // the vendor created this directory fresh during the install. The untracked-items
        // safety check (Phase 3) is bypassed for these paths.
        var runtimeTrustedPaths = Set<String>()
        if let runtimePaths = record.runtimeCreatedPaths, !runtimePaths.isEmpty {
            let otherClaimedPaths: Set<String> = otherRecords.reduce(into: []) { set, other in
                guard other.id != record.id, other.status == .success else { return }
                (other.runtimeCreatedPaths ?? []).forEach { set.insert($0) }
                other.installedFiles.forEach { set.insert($0.destinationPath) }
            }
            for path in runtimePaths {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                if otherClaimedPaths.contains(path) {
                    await logger.log("Skipping shared path (owned by another product): \(path)")
                    continue
                }
                candidates.append(path)
                runtimeTrustedPaths.insert(path)
                await logger.log("Runtime-created path: \(path)")
            }
        }

        if cancellationRequested {
            await logger.log("Uninstall cancelled during preparation.")
            return RollbackResult(success: false, removedFiles: [], failedFiles: [], detail: "Cancelled.")
        }

        // ── Phase 1c: Vendor plist + preferences files ────────────────────────
        // Extract vendor name(s) from PKG receipt IDs (e.g. "com.oeksound.soothe2.au"
        // → vendor "oeksound") and scan known preference locations for matching files.
        // Only includes files whose modification date is on or after the install date,
        // so we never touch pre-existing preference files from an older install.
        // ATLAS never adds a path here unless its name contains the vendor token.
        let vendorTokens = vendorTokensFromReceipts(record.pkgReceiptIDs +
                                                     (record.installedFiles.map {
                                                         URL(fileURLWithPath: $0.destinationPath)
                                                             .deletingPathExtension().lastPathComponent
                                                     }))
        if !vendorTokens.isEmpty {
            let home = NSHomeDirectory()
            // Scan preferences + caches for vendor-named files
            let prefDirs = [
                home + "/Library/Preferences",
                "/Library/Preferences",
                home + "/Library/Caches",
            ]
            let fm = FileManager.default
            for dir in prefDirs {
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for entry in entries {
                    let lower = entry.lowercased()
                    // Bidirectional match: token may be a substring of the name, or vice versa.
                    // e.g. token "oeksoundsoothe" matches directory "oeksound" via token.contains(lower)
                    guard vendorTokens.contains(where: { lower.contains($0) }) else { continue }
                    let full = "\(dir)/\(entry)"
                    guard !candidates.contains(full) else { continue }
                    // Only include if created/modified at or after install date
                    if let attrs = try? fm.attributesOfItem(atPath: full),
                       let mod = attrs[.modificationDate] as? Date,
                       mod >= record.date.addingTimeInterval(-60) {   // 60s grace for clock skew
                        candidates.append(full)
                        runtimeTrustedPaths.insert(full)   // pref files trusted — vendor-named
                        await logger.log("Vendor pref/cache: \(full)")
                    }
                }
            }

            // Scan Application Support for vendor-named directories.
            // Many audio plugins create /Library/Application Support/<Vendor>/ at install time
            // but PKG receipts don't list it, and some PKG installers set directory timestamps
            // to epoch-0 (Dec 31 1969), so a date guard would incorrectly skip them.
            // Safe because tokens are derived exclusively from this install's receipt IDs.
            let appSupportDirs = [
                "/Library/Application Support",
                home + "/Library/Application Support",
            ]
            for dir in appSupportDirs {
                guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for entry in entries {
                    let lower = entry.lowercased()
                    // Never touch known browser/editor/OS app support directories
                    guard !appSupportExclusions.contains(where: { lower == $0 || lower.hasPrefix($0) }) else { continue }
                    guard vendorTokens.contains(where: { lower.contains($0) }) else { continue }
                    let full = "\(dir)/\(entry)"
                    guard !candidates.contains(full) else { continue }
                    var isDir: ObjCBool = false
                    fm.fileExists(atPath: full, isDirectory: &isDir)
                    guard isDir.boolValue else { continue }
                    candidates.append(full)
                    runtimeTrustedPaths.insert(full)
                    await logger.log("Vendor Application Support dir: \(full)")
                }
            }
        }

        // ── Phase 2: Collapse bundles, then by directory ──────────────────────
        await logger.log("Finding installed files...")
        await logger.log("Candidates before collapse: \(Array(Set(candidates)).count)")
        let afterBundles = collapseIntoBundles(Array(Set(candidates)))
        let collapsed    = collapseByDirectory(afterBundles)
        let sorted       = sortByPriority(collapsed)

        await logger.log("Final trash list (\(sorted.count) item(s)):")
        for p in sorted { await logger.log("  → \(p)") }
        await logger.log("Moving files to Trash...")
        onProgress?(0.0, "")

        // ── Phase 3: Move each item to Trash ──────────────────────────────────
        var alreadyGoneCount = 0

        for (i, path) in sorted.enumerated() {
            if cancellationRequested {
                await logger.log("Uninstall cancelled by user.")
                break
            }
            let name = URL(fileURLWithPath: path).lastPathComponent
            let pct  = Double(i + 1) / Double(sorted.count)

            guard FileManager.default.fileExists(atPath: path) else {
                alreadyGoneCount += 1
                removed.append(path)
                onProgress?(pct, "")
                continue
            }

            if isSystemPath(path) {
                await logger.log("⚠ Skipped (system path): \(name)")
                onProgress?(pct, "")
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
                _ = runWithPassword(password: password,
                                    arguments: ["/bin/launchctl", "unload", path])
            }

            await logger.log("Trashing \(name)...")
            onProgress?(pct, name)

            let t = itemTimeout(path)
            let (result, trashPath) = trashItem(path: path, password: password, seconds: t)
            switch result {
            case .done:
                await logger.log("✓ \(name) → Trash")
                removed.append(path)
                if let tp = trashPath {
                    trashRecords.append(TrashRecord(originalPath: path, trashPath: tp))
                }
            case .skipped:
                await logger.log("⚠ Skipped (timeout): \(name)")
            case .failed:
                await logger.log("✗ Could not trash: \(name)")
                failed.append(path)
            }

            onProgress?(pct, name)
        }

        if alreadyGoneCount > 0 {
            await logger.log("Skipped \(alreadyGoneCount) already-removed path(s)")
        }

        // ── Phase 4: Write manifest so Undo Uninstall knows Trash paths ───────
        let manifestPath = writeTrashManifest(trashRecords, for: record.fileName)

        // ── Phase 5: Forget PKG receipts ─────────────────────────────────────
        await logger.log("Removing receipts...")
        var forgotCount = 0
        for id in record.pkgReceiptIDs {
            if cancellationRequested {
                await logger.log("Uninstall cancelled during receipt removal.")
                break
            }
            if PKGReceiptScanner.forgetReceipt(id, password: password) { forgotCount += 1 }
            else { await logger.log("⚠ Could not clear receipt: \(id)") }
        }
        if forgotCount > 0 { await logger.log("✓ Cleared \(forgotCount) receipt(s)") }

        // ── Phase 6: Clean up empty parent directories ────────────────────────
        let emptyDirs = cleanupEmptyDirs(from: removed, password: password)
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

        onProgress?(1.0, "")
        if cancellationRequested {
            await logger.log("Cancelled — partial uninstall: trashed \(uniqueRemoved.count) item(s)")
        } else {
            await logger.log("Completed — trashed: \(uniqueRemoved.count), failed: \(uniqueFailed.count)")
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
            _ = runWithPassword(password: password, arguments: ["/bin/mkdir", "-p", parentDir])

            // Try user-space move first, fall back to sudo
            if (try? FileManager.default.moveItem(atPath: record.trashPath,
                                                  toPath: record.originalPath)) != nil {
                restoredCount += 1
                await logger.log("✓ Recovered: \(URL(fileURLWithPath: record.originalPath).lastPathComponent)")
            } else {
                let r = runWithPassword(password: password,
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

        while changed {
            changed = false
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
                                  seconds: Double) -> (RemoveResult, String?) {
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

        let mv = runWithPassword(password: password,
                                 arguments: ["/bin/mv", path, dest])
        guard mv.success else { return (.failed, nil) }

        // Fix ownership so the item appears under the user's account in Finder Trash
        // and can be emptied without an admin prompt.
        let userName = NSUserName()
        _ = runWithPassword(password: password,
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
                                                seconds: Double) -> [String] {
        let process = Process()
        let pipe    = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments     = ["--files", receiptID]
        process.standardOutput = pipe
        process.standardError  = Pipe()
        guard (try? process.run()) != nil else { return [] }

        // Read pipe concurrently so a large receipt (10k+ files) never fills
        // the pipe buffer and deadlocks the process before it can exit.
        var outputData = Data()
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }

        // Poll with cancellation check — terminate early if user cancelled
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            if cancellationRequested { break }
        }
        if process.isRunning { process.terminate() }
        _ = sema.wait(timeout: .now() + 5)

        let output   = String(data: outputData, encoding: .utf8) ?? ""
        let location = PKGReceiptScanner.installLocation(forReceipt: receiptID)
        let anchors  = protectedAncestors

        // Bundle extensions that are directories but should be treated as files
        let bundleExts: Set<String> = [
            "component", "vst3", "vst", "aaxplugin", "app",
            "framework", "plugin", "kext", "appex", "bundle"
        ]
        let fm = FileManager.default

        return output
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
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
                                         password: String) -> [String] {
        var parents    = Set<String>()
        let protected  = protectedDirs
        let aggregates = aggregateDirs

        for path in removedPaths {
            var url = URL(fileURLWithPath: path).deletingLastPathComponent()
            for _ in 0..<5 {
                let p           = url.path
                let grandparent = url.deletingLastPathComponent().path
                // Stop if we hit a protected dir or a vendor root
                if protected.contains(p) || p == "/" { break }
                if aggregates.contains(grandparent) || aggregates.contains(p) { break }
                parents.insert(p)
                url = url.deletingLastPathComponent()
            }
        }

        var cleaned: [String] = []
        for dir in parents.sorted(by: { $0.count > $1.count }) {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            if contents.isEmpty {
                if case .done = hardRemove(path: dir, password: password, seconds: 4) {
                    cleaned.append(dir)
                }
            }
        }
        return cleaned
    }

    // Permanent delete — only used for empty directories where there is nothing to preserve.
    private static func hardRemove(path: String,
                                   password: String,
                                   seconds: Double) -> RemoveResult {
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
            Thread.sleep(forTimeInterval: 0.05)
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
                                        timeout: TimeInterval = 30) -> (success: Bool, output: String) {
        let process    = Process()
        let inputPipe  = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments     = ["-S"] + arguments
        process.standardInput  = inputPipe
        process.standardOutput = outputPipe
        process.standardError  = outputPipe

        var outputData = Data()
        let sema = DispatchSemaphore(value: 0)

        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
        } catch {
            return (false, error.localizedDescription)
        }

        DispatchQueue.global(qos: .utility).async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            if cancellationRequested { break }
        }
        if process.isRunning {
            process.terminate()
        }
        _ = sema.wait(timeout: .now() + 3)

        let out = String(data: outputData, encoding: .utf8) ?? ""
        return (process.terminationStatus == 0, out)
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
