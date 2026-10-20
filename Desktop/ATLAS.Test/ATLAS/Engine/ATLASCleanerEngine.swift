import Foundation
import CryptoKit

// MARK: - Scan category (declaration order = scan order: fastest → slowest)

enum CleanerCategory: String, CaseIterable {
    case orphanedDisabledStorage  // ATLAS/Disabled/ UUID dirs with no active entry
    case staleStagingEntry        // ATLAS/Staging/ entries older than 7 days
    case expiredRollbackBackup    // rollback backup for uninstalled record, 30+ days old
    case incompleteDownload       // *.download/*.crdownload/*.part/*.partial in ~/Downloads
    case unusedInstaller          // installer in ~/Downloads matching a successful install record
    case duplicatePlugin          // same plugin binary at 2+ paths (ATLAS-installed)
    case redundantFormat          // same product in multiple formats, DAW suggests one is unused
    case duplicateInstaller       // same installer file (hash or name) at 2+ paths
    case atlasInstallerArtifact   // exact installer file ATLAS recorded using for a successful install
}

// MARK: - Per-category scan progress

enum CategoryScanState {
    case pending
    case scanning
    case complete(Int)   // item count found
    case error
}

// MARK: - Trash operation types

enum TrashResult {
    case success
    case failed(String)
    case skipped(String)
}

enum TrashState: Equatable {
    case idle
    case trashing
    case complete
}

// MARK: - Cleaner item

struct CleanerItem: Identifiable {
    let id = UUID()
    let category: CleanerCategory
    let path: String
    let size: Int64?
    let productName: String?
    let recordID: UUID?
    let reason: String
    let formatExtensions: [String]
    let isReviewOnly: Bool       // true = never auto-selected; user must explicitly check
    let keepPath: String?        // for duplicate categories: path of the copy being kept
}

// MARK: - Engine

@MainActor
final class ATLASCleanerEngine: ObservableObject {

    enum ScanState: Equatable {
        case idle
        case scanning
        case complete
        case failed(String)

        var isTerminal: Bool {
            switch self { case .complete, .failed: return true; default: return false }
        }
    }

    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var categoryProgress: [CleanerCategory: CategoryScanState] = [:]
    @Published private(set) var items: [CleanerItem] = []

    var totalReclaimableBytes: Int64 {
        items.filter { !$0.isReviewOnly }.compactMap { $0.size }.reduce(0, +)
    }
    var isScanning: Bool { scanState == .scanning }

    @Published private(set) var trashResults: [UUID: TrashResult] = [:]
    @Published private(set) var trashState: TrashState = .idle

    private static let hashCapBytes: Int64 = 2 * 1_073_741_824   // 2 GB

    // MARK: - Scan entry point

    // deepScan: false = skip SHA-256 (fast sidebar badge scan, called from ATLASStorageSectionView)
    //           true  = enable content hashing for duplicate installer detection
    func scan(store: HistoryStore, deepScan: Bool = false) async {
        guard !isScanning else { return }
        scanState = .scanning
        items = []
        trashResults = [:]
        trashState = .idle
        categoryProgress = Dictionary(
            uniqueKeysWithValues: CleanerCategory.allCases.map { ($0, .pending) }
        )

        let activeRecords   = store.records
        let archivedRecords = store.archivedRecords

        for category in CleanerCategory.allCases {
            categoryProgress[category] = .scanning
            let found = await Task.detached(priority: .utility) {
                ATLASCleanerEngine.performCategoryScan(
                    category: category,
                    activeRecords: activeRecords,
                    archivedRecords: archivedRecords,
                    deepScan: deepScan
                )
            }.value
            switch found {
            case .success(let newItems):
                items.append(contentsOf: newItems)
                categoryProgress[category] = .complete(newItems.count)
            case .failure:
                categoryProgress[category] = .error
            }
        }

        scanState = .complete
    }

    // MARK: - Trash entry point

    func trash(selectedIDs: Set<UUID>, store: HistoryStore) async {
        guard !selectedIDs.isEmpty, trashState != .trashing else { return }
        trashState = .trashing
        trashResults = [:]

        let activeRecords   = store.records
        let archivedRecords = store.archivedRecords
        let toProcess       = items.filter { selectedIDs.contains($0.id) }
        let trashDate       = Date()

        let outcomes = await Task.detached(priority: .userInitiated) {
            var r: [UUID: (result: TrashResult, trashURL: URL?)] = [:]
            let fm = FileManager.default
            for item in toProcess {
                let (ok, reason) = ATLASCleanerEngine.reVerify(
                    item: item, activeRecords: activeRecords, archivedRecords: archivedRecords
                )
                guard ok else { r[item.id] = (.skipped(reason), nil); continue }
                do {
                    var resultURL: NSURL?
                    try fm.trashItem(at: URL(fileURLWithPath: item.path), resultingItemURL: &resultURL)
                    r[item.id] = (.success, resultURL as URL?)
                } catch {
                    r[item.id] = (.failed(error.localizedDescription), nil)
                }
            }
            return r
        }.value

        trashResults = outcomes.mapValues { $0.result }

        // Record all trashed items to Cleaner history
        let historyEntries: [CleanerHistoryEntry] = toProcess.compactMap { item in
            guard let outcome = outcomes[item.id], case .success = outcome.result else { return nil }
            return CleanerHistoryEntry(
                id: UUID(),
                name: item.productName ?? URL(fileURLWithPath: item.path).lastPathComponent,
                originalPath: item.path,
                trashPath: outcome.trashURL?.path,
                category: item.category.rawValue,
                size: item.size,
                trashedAt: trashDate
            )
        }
        if !historyEntries.isEmpty {
            CleanerHistoryStore.shared.addSession(date: trashDate, entries: historyEntries)
        }

        let succeededIDs = Set(outcomes.filter {
            if case .success = $0.value.result { return true }; return false
        }.map { $0.key })
        items.removeAll { succeededIDs.contains($0.id) }
        trashState = .complete
    }

    // MARK: - Per-category dispatch (nonisolated — runs off main thread)

    private nonisolated static func performCategoryScan(
        category: CleanerCategory,
        activeRecords: [InstallRecord],
        archivedRecords: [InstallRecord],
        deepScan: Bool
    ) -> Result<[CleanerItem], Error> {
        let all = activeRecords + archivedRecords
        do {
            switch category {
            case .orphanedDisabledStorage:
                return .success(try scanOrphanedDisabledStorage(allRecords: all))
            case .staleStagingEntry:
                return .success(try scanStaleStagingEntries())
            case .expiredRollbackBackup:
                return .success(scanExpiredRollbackBackups(allRecords: all))
            case .incompleteDownload:
                return .success(scanIncompleteDownloads())
            case .unusedInstaller:
                return .success(scanUnusedInstallers(allRecords: all))
            case .duplicatePlugin:
                return .success(scanDuplicatePlugins(allRecords: all))
            case .redundantFormat:
                return .success(scanRedundantFormats(allRecords: all))
            case .duplicateInstaller:
                return .success(try scanDuplicateInstallers(deepScan: deepScan))
            case .atlasInstallerArtifact:
                return .success(scanAtlasInstallerArtifacts(allRecords: all))
            }
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Category: Orphaned disabled storage

    nonisolated static func scanOrphanedDisabledStorage(
        allRecords: [InstallRecord]
    ) throws -> [CleanerItem] {
        let fm = FileManager.default
        let disabledRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/Disabled")
        guard fm.fileExists(atPath: disabledRoot.path) else { return [] }
        let resolvedRoot = disabledRoot.resolvingSymlinksInPath().standardized

        var referencedDirs = Set<String>()
        for record in allRecords {
            for entry in record.disabledFormats ?? [] {
                let dir = URL(fileURLWithPath: entry.disabledStoragePath)
                    .deletingLastPathComponent().resolvingSymlinksInPath().standardized
                referencedDirs.insert(dir.path)
            }
        }

        let subdirs = try fm.contentsOfDirectory(
            at: disabledRoot, includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        var result: [CleanerItem] = []
        for dir in subdirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            guard UUID(uuidString: dir.lastPathComponent) != nil else { continue }
            let resolved = dir.resolvingSymlinksInPath().standardized
            guard resolved.path.hasPrefix(resolvedRoot.path + "/") else { continue }
            if referencedDirs.contains(resolved.path) { continue }

            let contents = (try? fm.contentsOfDirectory(
                at: resolved, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
            )) ?? []
            let fileURLs = contents.filter { !$0.hasDirectoryPath }
            let baseNames = Set(fileURLs.map { $0.deletingPathExtension().lastPathComponent })
            let productName: String?
            let formatExts: [String]
            if baseNames.count == 1, let name = baseNames.first, !name.isEmpty {
                productName = name
                formatExts  = fileURLs.map { $0.pathExtension.lowercased() }.sorted()
            } else {
                productName = nil
                formatExts  = []
            }
            result.append(CleanerItem(
                category: .orphanedDisabledStorage,
                path: resolved.path,
                size: directorySize(at: resolved),
                productName: productName,
                recordID: UUID(uuidString: dir.lastPathComponent),
                reason: "Disabled plugin storage with no matching ATLAS Library record",
                formatExtensions: formatExts,
                isReviewOnly: false,
                keepPath: nil
            ))
        }
        return result
    }

    // MARK: - Category: Stale staging entries

    private nonisolated static func scanStaleStagingEntries() throws -> [CleanerItem] {
        let fm = FileManager.default
        let stagingRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/Staging")
        guard fm.fileExists(atPath: stagingRoot.path) else { return [] }
        let resolvedRoot = stagingRoot.resolvingSymlinksInPath().standardized
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        let entries = try fm.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isDirectoryKey],
            options: .skipsHiddenFiles
        )
        var result: [CleanerItem] = []
        for entry in entries {
            let resolved = entry.resolvingSymlinksInPath().standardized
            guard resolved.path.hasPrefix(resolvedRoot.path + "/") else { continue }
            guard resolved.deletingLastPathComponent().standardized.path == resolvedRoot.path else { continue }
            guard let attrs = try? resolved.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey]),
                  let date = attrs.creationDate ?? attrs.contentModificationDate,
                  date < cutoff else { continue }
            result.append(CleanerItem(
                category: .staleStagingEntry,
                path: resolved.path,
                size: itemSize(at: resolved),
                productName: nil,
                recordID: nil,
                reason: "ATLAS staging artifact older than 7 days",
                formatExtensions: [],
                isReviewOnly: false,
                keepPath: nil
            ))
        }
        return result
    }

    // MARK: - Category: Expired rollback backups

    private nonisolated static func scanExpiredRollbackBackups(
        allRecords: [InstallRecord]
    ) -> [CleanerItem] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        var result: [CleanerItem] = []
        for record in allRecords {
            guard record.status == .uninstalled,
                  let backupPath = record.rollbackBackupPath else { continue }
            guard fm.fileExists(atPath: backupPath) else { continue }
            let url = URL(fileURLWithPath: backupPath).resolvingSymlinksInPath()
            guard fm.fileExists(atPath: url.path) else { continue }
            guard let attrs = try? url.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey]),
                  let date = attrs.creationDate ?? attrs.contentModificationDate,
                  date < cutoff else { continue }
            result.append(CleanerItem(
                category: .expiredRollbackBackup,
                path: url.path,
                size: itemSize(at: url),
                productName: record.fileName,
                recordID: record.id,
                reason: "Rollback backup for \"\(record.fileName)\", uninstalled 30+ days ago",
                formatExtensions: [],
                isReviewOnly: false,
                keepPath: nil
            ))
        }
        return result
    }

    // MARK: - Category: Incomplete downloads

    private nonisolated static func scanIncompleteDownloads() -> [CleanerItem] {
        let fm = FileManager.default
        let downloadsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard fm.fileExists(atPath: downloadsURL.path) else { return [] }
        let resolvedDownloads = downloadsURL.resolvingSymlinksInPath().standardized
        let incompleteExts = Set(["download", "crdownload", "part", "partial", "tmp"])
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)

        let entries = (try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        )) ?? []

        var result: [CleanerItem] = []
        for entry in entries {
            guard let vals = try? entry.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            let ext = entry.pathExtension.lowercased()
            guard incompleteExts.contains(ext) else { continue }
            guard let attrs = try? entry.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey]),
                  let date = attrs.creationDate ?? attrs.contentModificationDate,
                  date < cutoff else { continue }
            let resolved = entry.resolvingSymlinksInPath().standardized
            guard resolved.path.hasPrefix(resolvedDownloads.path + "/") else { continue }
            result.append(CleanerItem(
                category: .incompleteDownload,
                path: resolved.path,
                size: itemSize(at: resolved),
                productName: entry.deletingPathExtension().lastPathComponent,
                recordID: nil,
                reason: "Incomplete or interrupted download — older than 24 hours",
                formatExtensions: [],
                isReviewOnly: false,
                keepPath: nil
            ))
        }
        return result
    }

    // MARK: - Category: Unused installers

    private nonisolated static func scanUnusedInstallers(
        allRecords: [InstallRecord]
    ) -> [CleanerItem] {
        let fm = FileManager.default
        let downloadsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard fm.fileExists(atPath: downloadsURL.path) else { return [] }

        let successNames = Set(allRecords
            .filter { $0.status == .success }
            .map  { $0.fileName.lowercased() })
        guard !successNames.isEmpty else { return [] }

        let installerExts = Set(["pkg", "zip", "dmg", "run", "exe"])
        let entries = (try? fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )) ?? []

        var result: [CleanerItem] = []
        for entry in entries {
            guard let vals = try? entry.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { continue }
            guard installerExts.contains(entry.pathExtension.lowercased()) else { continue }
            guard successNames.contains(entry.lastPathComponent.lowercased()) else { continue }
            result.append(CleanerItem(
                category: .unusedInstaller,
                path: entry.path,
                size: itemSize(at: entry),
                productName: entry.deletingPathExtension().lastPathComponent,
                recordID: nil,
                reason: "Filename matches a completed ATLAS install — may no longer be needed (filename match only, not content-verified)",
                formatExtensions: [],
                isReviewOnly: true,
                keepPath: nil
            ))
        }
        return result
    }

    // MARK: - Category: Duplicate plugins

    nonisolated static func scanDuplicatePlugins(
        allRecords: [InstallRecord]
    ) -> [CleanerItem] {
        let fm = FileManager.default
        let pluginExts   = Set(["component", "vst3", "vst", "aaxplugin"])
        let disabledPaths = collectDisabledPaths(allRecords: allRecords)

        // Group by lowercased filename (includes extension — component ≠ vst3 ≠ vst)
        var grouped: [String: [(path: String, date: Date)]] = [:]
        for record in allRecords where record.status == .success {
            for file in record.installedFiles {
                let url = URL(fileURLWithPath: file.destinationPath)
                guard pluginExts.contains(url.pathExtension.lowercased()) else { continue }
                let key = url.lastPathComponent.lowercased()
                grouped[key, default: []].append((file.destinationPath, record.date))
            }
        }

        var result: [CleanerItem] = []
        for (_, entries) in grouped {
            // Deduplicate paths (same path reinstalled = same path in multiple records)
            var seenPaths = Set<String>()
            let unique = entries.filter { seenPaths.insert($0.path).inserted }
            guard unique.count >= 2 else { continue }

            let live = unique.filter {
                fm.fileExists(atPath: $0.path) && !disabledPaths.contains($0.path)
            }
            guard live.count >= 2 else { continue }

            let sorted  = live.sorted { $0.date > $1.date }
            let keepPath = sorted[0].path

            for entry in sorted.dropFirst() {
                let url = URL(fileURLWithPath: entry.path)
                result.append(CleanerItem(
                    category: .duplicatePlugin,
                    path: entry.path,
                    size: itemSize(at: url),
                    productName: url.deletingPathExtension().lastPathComponent,
                    recordID: nil,
                    reason: "Duplicate — a newer copy exists at a different location",
                    formatExtensions: [url.pathExtension.lowercased()],
                    isReviewOnly: false,
                    keepPath: keepPath
                ))
            }
        }
        return result
    }

    // MARK: - Category: Redundant formats

    private nonisolated static func scanRedundantFormats(
        allRecords: [InstallRecord]
    ) -> [CleanerItem] {
        let fm = FileManager.default
        let pluginExts = Set(["component", "vst3", "vst", "aaxplugin"])
        let daws = PluginScanner.detectInstalledDAWs()
        guard !daws.isEmpty else { return [] }  // no DAWs detected → cannot classify formats
        let usedFormats = Set(daws.flatMap { $0.formats })

        // Group by product base name (lowercased, no extension)
        var byName: [String: [(format: String, path: String)]] = [:]
        for record in allRecords where record.status == .success {
            for file in record.installedFiles {
                let url = URL(fileURLWithPath: file.destinationPath)
                let ext = url.pathExtension.lowercased()
                guard pluginExts.contains(ext) else { continue }
                let name = url.deletingPathExtension().lastPathComponent.lowercased()
                byName[name, default: []].append((ext, file.destinationPath))
            }
        }

        var result: [CleanerItem] = []
        for (_, entries) in byName {
            let live = entries.filter { fm.fileExists(atPath: $0.path) }
            guard live.count >= 2 else { continue }
            let liveFormats = Set(live.map { $0.format })
            // Only flag if at least one format IS used (so the product remains functional)
            guard !liveFormats.intersection(usedFormats).isEmpty else { continue }

            for entry in live where !usedFormats.contains(entry.format) {
                let url = URL(fileURLWithPath: entry.path)
                result.append(CleanerItem(
                    category: .redundantFormat,
                    path: entry.path,
                    size: itemSize(at: url),
                    productName: url.deletingPathExtension().lastPathComponent,
                    recordID: nil,
                    reason: "Format not used by any detected DAW — based on /Applications",
                    formatExtensions: [entry.format],
                    isReviewOnly: true,
                    keepPath: nil
                ))
            }
        }
        return result
    }

    // MARK: - Category: Duplicate installers

    private nonisolated static func scanDuplicateInstallers(deepScan: Bool) throws -> [CleanerItem] {
        let fm = FileManager.default
        let downloadsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard fm.fileExists(atPath: downloadsURL.path) else { return [] }

        let installerExts = Set(["pkg", "zip", "dmg", "run", "exe", "rar"])
        let all = (try fm.contentsOfDirectory(
            at: downloadsURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .creationDateKey],
            options: .skipsHiddenFiles
        )).filter { url -> Bool in
            guard let vals = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  vals.isRegularFile == true else { return false }
            let ext = url.pathExtension.lowercased()
            if ext == "gz" && url.deletingPathExtension().pathExtension.lowercased() == "tar" { return true }
            return installerExts.contains(ext)
        }

        // Name groups (always built)
        var nameGroups: [String: [URL]] = [:]
        for url in all { nameGroups[url.lastPathComponent.lowercased(), default: []].append(url) }

        // Hash groups (only with deepScan)
        var hashGroups: [String: [URL]] = [:]
        var hashFlagged = Set<String>()

        if deepScan {
            for url in all {
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                guard size <= hashCapBytes else { continue }
                if let h = sha256(url: url) { hashGroups[h, default: []].append(url) }
            }
        }

        var result: [CleanerItem] = []

        // Hash-confirmed duplicates — high confidence, not review-only
        for (_, urls) in hashGroups where urls.count >= 2 {
            let sorted = urls.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return d1 < d2
            }
            let keepURL = sorted.last!
            for url in sorted.dropLast() {
                hashFlagged.insert(url.path)
                result.append(CleanerItem(
                    category: .duplicateInstaller,
                    path: url.path,
                    size: itemSize(at: url),
                    productName: url.deletingPathExtension().lastPathComponent,
                    recordID: nil,
                    reason: "Exact duplicate — SHA-256 content match with a newer copy",
                    formatExtensions: [],
                    isReviewOnly: false,
                    keepPath: keepURL.path
                ))
            }
        }

        // Name-match only — review-only (may be different versions of same installer)
        for (_, urls) in nameGroups where urls.count >= 2 {
            let unflagged = urls.filter { !hashFlagged.contains($0.path) }
            guard unflagged.count >= 2 else { continue }
            for url in unflagged {
                let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                let reason: String
                if size > hashCapBytes {
                    reason = "Possible duplicate — file exceeds 2 GB hash cap (filename match only, not content-verified)"
                } else {
                    reason = "Possible duplicate — filename matches another installer (not content-verified)"
                }
                result.append(CleanerItem(
                    category: .duplicateInstaller,
                    path: url.path,
                    size: itemSize(at: url),
                    productName: url.deletingPathExtension().lastPathComponent,
                    recordID: nil,
                    reason: reason,
                    formatExtensions: [],
                    isReviewOnly: true,
                    keepPath: nil
                ))
            }
        }

        return result
    }

    // MARK: - Re-verification (called immediately before each trash, off main thread)

    private nonisolated static func reVerify(
        item: CleanerItem, activeRecords: [InstallRecord], archivedRecords: [InstallRecord]
    ) -> (Bool, String) {
        switch item.category {
        case .orphanedDisabledStorage:
            return reVerifyDisabledStorage(item: item, all: activeRecords + archivedRecords)
        case .staleStagingEntry:
            return reVerifyStagingEntry(item: item)
        case .expiredRollbackBackup:
            return reVerifyRollbackBackup(item: item, all: activeRecords + archivedRecords)
        case .incompleteDownload:
            return reVerifyIncompleteDownload(item: item)
        case .unusedInstaller:
            return reVerifyDownloadsFile(item: item)
        case .duplicatePlugin:
            return reVerifyDuplicatePlugin(item: item, all: activeRecords + archivedRecords)
        case .redundantFormat:
            return reVerifyRedundantFormat(item: item)
        case .duplicateInstaller:
            return reVerifyDownloadsFile(item: item)
        case .atlasInstallerArtifact:
            return reVerifyAtlasInstallerArtifact(item: item, all: activeRecords + archivedRecords)
        }
    }

    private nonisolated static func reVerifyDisabledStorage(
        item: CleanerItem, all: [InstallRecord]
    ) -> (Bool, String) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/Disabled")
            .resolvingSymlinksInPath().standardized
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else {
            return (false, "Path no longer exists on disk")
        }
        let resolved = URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized
        guard resolved.path.hasPrefix(root.path + "/") else {
            return (false, "Path moved outside ATLAS Disabled root")
        }
        guard isDir.boolValue, UUID(uuidString: resolved.lastPathComponent) != nil else {
            return (false, "UUID directory validation failed")
        }
        for record in all {
            for entry in record.disabledFormats ?? [] {
                let p = URL(fileURLWithPath: entry.disabledStoragePath)
                    .deletingLastPathComponent().resolvingSymlinksInPath().standardized
                if p.path == resolved.path {
                    return (false, "Now referenced by an active disabled-format entry")
                }
            }
        }
        guard URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized.path == resolved.path else {
            return (false, "Path changed since scan")
        }
        return (true, "")
    }

    private nonisolated static func reVerifyStagingEntry(item: CleanerItem) -> (Bool, String) {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/Staging")
            .resolvingSymlinksInPath().standardized
        guard fm.fileExists(atPath: item.path) else { return (false, "Entry no longer exists") }
        let resolved = URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized
        guard resolved.path.hasPrefix(root.path + "/") else {
            return (false, "Moved outside ATLAS Staging root")
        }
        guard resolved.deletingLastPathComponent().standardized.path == root.path else {
            return (false, "Not a top-level staging entry")
        }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        guard let attrs = try? resolved.resourceValues(
            forKeys: [.creationDateKey, .contentModificationDateKey]),
              let date = attrs.creationDate ?? attrs.contentModificationDate,
              date < cutoff else { return (false, "No longer 7+ days old") }
        guard URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized.path == resolved.path else {
            return (false, "Path changed since scan")
        }
        return (true, "")
    }

    private nonisolated static func reVerifyRollbackBackup(
        item: CleanerItem, all: [InstallRecord]
    ) -> (Bool, String) {
        let fm = FileManager.default
        guard let rid = item.recordID, let record = all.first(where: { $0.id == rid }) else {
            return (false, "Originating record no longer exists")
        }
        guard record.status == .uninstalled else { return (false, "Record status changed") }
        guard let cp = record.rollbackBackupPath else {
            return (false, "Rollback path was cleared from record")
        }
        let rc = URL(fileURLWithPath: cp).resolvingSymlinksInPath().standardized
        let ri = URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized
        guard rc.path == ri.path else { return (false, "Rollback path changed since scan") }
        guard fm.fileExists(atPath: rc.path) else { return (false, "Backup no longer exists") }
        let atlasDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS")
            .resolvingSymlinksInPath().standardized
        guard rc.path.hasPrefix(atlasDir.path + "/") else {
            return (false, "Backup moved outside ATLAS storage")
        }
        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        guard let attrs = try? rc.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]),
              let date = attrs.creationDate ?? attrs.contentModificationDate,
              date < cutoff else { return (false, "Backup no longer 30+ days old") }
        return (true, "")
    }

    private nonisolated static func reVerifyIncompleteDownload(item: CleanerItem) -> (Bool, String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.path) else { return (false, "File no longer exists") }
        let resolved = URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").resolvingSymlinksInPath().standardized
        guard resolved.path.hasPrefix(root.path + "/") else {
            return (false, "File moved outside ~/Downloads")
        }
        // Guard against trashing an active download (file grew significantly since scan)
        if let currentSize = (try? resolved.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
           let recorded = item.size.map({ Int($0) }),
           currentSize > recorded + 65_536 {
            return (false, "File size increased since scan — may be an active download")
        }
        return (true, "")
    }

    // Shared re-verify for files that must remain in ~/Downloads
    private nonisolated static func reVerifyDownloadsFile(item: CleanerItem) -> (Bool, String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.path) else { return (false, "File no longer exists") }
        let resolved = URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized
        let root = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").resolvingSymlinksInPath().standardized
        guard resolved.path.hasPrefix(root.path + "/") else {
            return (false, "File moved outside ~/Downloads")
        }
        return (true, "")
    }

    private nonisolated static func reVerifyDuplicatePlugin(
        item: CleanerItem, all: [InstallRecord]
    ) -> (Bool, String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.path) else { return (false, "Duplicate copy no longer exists") }
        if let kp = item.keepPath, !fm.fileExists(atPath: kp) {
            return (false, "The kept copy no longer exists — unsafe to remove duplicate")
        }
        let disabledPaths = collectDisabledPaths(allRecords: all)
        guard !disabledPaths.contains(item.path) else {
            return (false, "Candidate is now referenced by a disabled-format entry")
        }
        let knownDirs = PluginScanner.pluginDirs.values.flatMap { $0 }
        let parent = URL(fileURLWithPath: item.path).deletingLastPathComponent().path
        guard knownDirs.contains(where: { parent.hasPrefix($0) }) else {
            return (false, "Plugin is no longer in a standard plugin directory")
        }
        return (true, "")
    }

    private nonisolated static func reVerifyRedundantFormat(item: CleanerItem) -> (Bool, String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.path) else { return (false, "File no longer exists") }
        let usedFormats = Set(PluginScanner.detectInstalledDAWs().flatMap { $0.formats })
        let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
        if usedFormats.contains(ext) {
            return (false, "Format is now used by a detected DAW")
        }
        return (true, "")
    }

    // MARK: - Helpers

    nonisolated static func collectDisabledPaths(allRecords: [InstallRecord]) -> Set<String> {
        var paths = Set<String>()
        for record in allRecords {
            for entry in record.disabledFormats ?? [] {
                paths.insert(entry.originalPath)
                paths.insert(entry.disabledStoragePath)
            }
        }
        return paths
    }

    nonisolated static func itemSize(at url: URL) -> Int64? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
        if isDir.boolValue {
            let s = directorySize(at: url)
            return s > 0 ? s : nil
        }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return Int64(size)
    }

    private nonisolated static func directorySize(at url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            guard let v = try? f.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  v.isRegularFile == true else { continue }
            total += Int64(v.fileSize ?? 0)
        }
        return total
    }

    private nonisolated static func sha256(url: URL) -> String? {
        guard let stream = InputStream(url: url) else { return nil }
        stream.open()
        defer { stream.close() }
        var hasher = SHA256()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            hasher.update(data: Data(buffer[..<n]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Category: ATLAS installer artifacts

    // Returns CleanerItems for installer files that ATLAS provably used for successful installs.
    // Source of truth: record.installerSourcePath — the exact path recorded at install time.
    // Never reads installedFiles.destinationPath. Never crawls the filesystem.
    // Only regular files are considered; directories are excluded.
    nonisolated static func scanAtlasInstallerArtifacts(
        allRecords: [InstallRecord]
    ) -> [CleanerItem] {
        let fm = FileManager.default
        var seenPaths = Set<String>()
        var result: [CleanerItem] = []

        for record in allRecords {
            guard record.status == .success,
                  let rawPath = record.installerSourcePath else { continue }

            let resolved = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().standardized
            let path = resolved.path

            // Deduplicate by resolved path — multiple records for same installer → one item
            guard seenPaths.insert(path).inserted else { continue }

            // File must still exist
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }

            // Exclude directories (.app bundles etc.) — regular files only
            guard !isDir.boolValue else { continue }

            result.append(CleanerItem(
                category: .atlasInstallerArtifact,
                path: path,
                size: itemSize(at: resolved),
                productName: record.fileName,
                recordID: record.id,
                reason: "Original installer used by ATLAS to install \"\(record.fileName)\"",
                formatExtensions: [resolved.pathExtension.lowercased()],
                isReviewOnly: false,
                keepPath: nil
            ))
        }
        return result
    }

    // Re-verification called immediately before trashing an atlasInstallerArtifact item.
    // All six conditions must pass or the item is skipped.
    private nonisolated static func reVerifyAtlasInstallerArtifact(
        item: CleanerItem,
        all: [InstallRecord]
    ) -> (Bool, String) {
        let fm = FileManager.default
        let pluginExts = Set(["component", "vst", "vst3", "aaxplugin"])
        let pluginRoots = [
            "/Library/Audio/Plug-Ins/",
            "/Library/Application Support/Avid/Audio/Plug-Ins/"
        ]
        let homePluginRoot = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Audio/Plug-Ins/").path

        // 1. File must still exist
        guard fm.fileExists(atPath: item.path) else {
            return (false, "Installer file no longer exists")
        }

        // 2. Resolved path must match stored path (guards against symlink swap)
        let resolved = URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized.path
        guard resolved == URL(fileURLWithPath: item.path).resolvingSymlinksInPath().standardized.path else {
            return (false, "Path changed since scan")
        }

        // 3. Must not be a plugin file extension
        let ext = URL(fileURLWithPath: item.path).pathExtension.lowercased()
        guard !pluginExts.contains(ext) else {
            return (false, "Target has a plugin file extension — will not trash")
        }

        // 4. Must not be inside a known plugin directory
        for root in pluginRoots {
            guard !item.path.hasPrefix(root) else {
                return (false, "Target is inside a system plugin directory — will not trash")
            }
        }
        guard !item.path.hasPrefix(homePluginRoot) else {
            return (false, "Target is inside user plugin directory — will not trash")
        }

        // 5. Must not be a directory
        var isDir: ObjCBool = false
        fm.fileExists(atPath: item.path, isDirectory: &isDir)
        guard !isDir.boolValue else {
            return (false, "Target is a directory — only regular files are supported")
        }

        // 6. Originating record must still exist, still be successful,
        //    and its installerSourcePath must still match item.path exactly
        guard let rid = item.recordID,
              let record = all.first(where: { $0.id == rid }) else {
            return (false, "Originating install record no longer exists")
        }
        guard record.status == .success else {
            return (false, "Install record status changed")
        }
        guard let storedPath = record.installerSourcePath,
              URL(fileURLWithPath: storedPath).resolvingSymlinksInPath().standardized.path == resolved else {
            return (false, "Record's installerSourcePath no longer matches this file")
        }

        return (true, "")
    }

    // MARK: - Quick Scan entry point (read-only, ATLAS-managed plugins only)
    // Checks only plugins that appear in ATLAS install records. Never crawls directories.
    // No hashing, no filesystem enumeration, no Cleaner History involvement.
    // Caller must pass records captured on the main actor before going off-thread.
    nonisolated static func quickScan(records: [InstallRecord], archivedRecords: [InstallRecord]) -> [CleanerItem] {
        let all = records + archivedRecords
        let duplicates = scanDuplicatePlugins(allRecords: all)
        let installerArtifacts = scanAtlasInstallerArtifacts(allRecords: all)
        return duplicates + installerArtifacts
    }
}
