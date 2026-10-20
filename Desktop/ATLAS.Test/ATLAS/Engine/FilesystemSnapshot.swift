import Foundation

// FilesystemSnapshot captures what an installer placed so ATLAS can uninstall it later.
//
// Safety model — three layers:
//
//  1. SCOPE: We only consider paths explicitly in our watch list.
//     Nothing outside these locations can ever appear in an install record.
//
//  2. DIFF SEMANTICS:
//     Deep locations  → track NEW files AND modified files (a changed plugin binary matters).
//     Shallow locations → track ONLY NEW top-level items (a directory whose modDate changed
//     just means something inside was touched; we must NOT trash the whole pre-existing dir).
//
//  3. UNINSTALL GUARD (RollbackEngine): even if a path somehow reaches the candidate list,
//     systemRoots / protectedDirs / aggregateDirs block it from being trashed.
//
// This file is responsible for layer 2.

struct FilesystemSnapshot {

    // MARK: - Watch lists

    // Deep-scanned locations: enumerate recursively, track new AND modified items.
    // Safe because these are narrow, vendor-specific directories — everything inside
    // belongs to that vendor's software and was placed by an installer.
    private static let deepLocations: [String] = [
        "/Applications",
        "/Library/Audio/Plug-Ins/Components",
        "/Library/Audio/Plug-Ins/VST3",
        "/Library/Audio/Plug-Ins/VST",
        "/Library/Audio/Plug-Ins/AAX",
        "/Library/Audio/Plug-Ins/CLAP",
        "/Library/Application Support/Avid",
        "/Library/Application Support/Native Instruments",
        "/Library/Application Support/Steinberg",
        "/Library/Application Support/iZotope",
        "/Library/Application Support/Waves",
        "/Library/Application Support/UAD",
        "/Library/Application Support/Antares",
        "/Library/Application Support/Output",
        "/Library/Application Support/Arturia",
        "/Library/Application Support/FabFilter",
        "/Library/Application Support/Plugin Alliance",
        "/Library/Application Support/Eventide",
        "/Library/Application Support/Soundtoys",
        "/Library/Application Support/Celemony",
        "/Library/Application Support/Aurora DSP",
        "/Library/Application Support/Kazrog",
        "/Library/Application Support/Baby Audio",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
        "/Library/PreferencePanes",
        "/Library/Receipts",
        // Font files — PKG installers can install fonts here (confirmed: FabFilter Source Code Pro)
        "/Library/Fonts",
        // System audio drivers (kernel extensions for UAD, SSL, Avid hardware, etc.)
        "/Library/Extensions",
        // MIDI interface drivers and plugin-format MIDI components
        "/Library/Audio/MIDI Drivers",
        NSHomeDirectory() + "/Library/Audio/Plug-Ins/Components",
        NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST3",
        NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST",
        NSHomeDirectory() + "/Library/Audio/Plug-Ins/CLAP",
        NSHomeDirectory() + "/Library/Audio/Plug-Ins/AAX",
        NSHomeDirectory() + "/Library/Application Support/Avid",
        NSHomeDirectory() + "/Library/Application Support/Baby Audio",
        NSHomeDirectory() + "/Library/LaunchAgents",
        // User-local fonts installed by PKG postinstall scripts
        NSHomeDirectory() + "/Library/Fonts",
    ]

    // Shallow-scanned locations: only record direct children (depth 1).
    // NEW children that appear after install = installed by this session.
    // EXISTING children whose modDate changed = NOT included (could be any other app).
    // This prevents ATLAS from ever trashing a pre-existing vendor directory just because
    // an installer happened to touch a file inside it.
    private static let shallowLocations: [String] = [
        "/Library/Application Support",
        "/Library/Preferences",
        NSHomeDirectory() + "/Library/Application Support",
        NSHomeDirectory() + "/Library/Preferences",
    ]

    // MARK: - Snapshot

    struct Snapshot {
        // deep: path → (mtime, ctime). mtime can be reset by postinstall scripts;
        // ctime (attributeModificationDate) is kernel-only and reflects when the inode
        // was actually written. Both are recorded so the diff can use the later of the two.
        let deep: [String: (mtime: Date, ctime: Date)]
        // shallow: set of paths; only NEW paths (not in beforeShallow) enter the diff
        let shallow: Set<String>
    }

    static func take() -> Snapshot {
        var deep:    [String: (mtime: Date, ctime: Date)] = [:]
        var shallow: Set<String>                          = []

        // Deep scan — include hidden files (.skipsHiddenFiles removed intentionally)
        // Hidden files matter: license blobs, auth tokens, .component bundles with dot-prefixed
        // support files, and UUID-named directories are all commonly hidden by vendors.
        //
        // We record both mtime (contentModificationDate) and ctime (attributeModificationDate).
        // Some installers reset mtime via postinstall scripts (e.g. FabFilter uses `touch -mtc`)
        // to stamp bundles with a release date. ctime cannot be reset by user-space processes —
        // the kernel updates it whenever inode metadata or content changes. Using max(mtime, ctime)
        // in the diff ensures we detect installer-replaced bundles even when mtime was reset.
        let deepKeys: Set<URLResourceKey> = [.contentModificationDateKey, .attributeModificationDateKey]
        for location in deepLocations {
            guard FileManager.default.fileExists(atPath: location) else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: location),
                includingPropertiesForKeys: Array(deepKeys),
                options: [.skipsPackageDescendants]   // hidden files now included
            ) else { continue }
            for case let url as URL in enumerator {
                guard let attrs = try? url.resourceValues(forKeys: deepKeys),
                      let mtime = attrs.contentModificationDate,
                      let ctime = attrs.attributeModificationDate else { continue }
                deep[url.path] = (mtime: mtime, ctime: ctime)
            }
        }

        // Shallow scan — all direct children including hidden (dot-files, UUID dirs, etc.)
        for location in shallowLocations {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: location),
                includingPropertiesForKeys: nil,
                options: []   // no .skipsHiddenFiles
            ) else { continue }
            for child in children {
                shallow.insert(child.path)
            }
        }

        return Snapshot(deep: deep, shallow: shallow)
    }

    // MARK: - Diff

    // Returns paths that were installed during this session.
    // Deep: new OR modified (file content may have changed).
    // Shallow: NEW ONLY — pre-existing directories with updated modDates are excluded.
    //          When a new directory appears, recursively enumerate its full contents
    //          (including hidden files) so every installed file is tracked, not just
    //          the top-level folder. This catches any new vendor directory regardless
    //          of whether it was in the deepLocations watch list.
    static func diff(before: Snapshot, after: Snapshot) -> [String] {
        var changed: [String] = []

        // Deep diff: new OR modified.
        // "Modified" uses max(mtime, ctime) for both before and after, so a file whose
        // mtime was reset by a postinstall script is still detected via its ctime advancing.
        // Concrete case: FabFilter runs `touch -mtc <release-date>` in postinstall, resetting
        // mtime to a historical date. The bundle's ctime is set by the kernel when the files
        // are written and cannot be overridden by user-space scripts.
        for (path, afterDates) in after.deep {
            let afterEffective = max(afterDates.mtime, afterDates.ctime)
            if let beforeDates = before.deep[path] {
                let beforeEffective = max(beforeDates.mtime, beforeDates.ctime)
                if afterEffective > beforeEffective { changed.append(path) }
            } else {
                changed.append(path)
            }
        }

        // Shallow diff: NEW ONLY — never include pre-existing paths
        let fm = FileManager.default
        for path in after.shallow where !before.shallow.contains(path) {
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            if isDir.boolValue {
                // New vendor directory — recursively track every file inside it,
                // including hidden files (license blobs, dot-prefixed support files, etc.)
                guard let enumerator = fm.enumerator(
                    at: URL(fileURLWithPath: path),
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsPackageDescendants]   // hidden files included
                ) else {
                    changed.append(path)
                    continue
                }
                var hadChildren = false
                for case let child as URL in enumerator {
                    changed.append(child.path)
                    hadChildren = true
                }
                // Also record the directory itself so it can be removed if empty
                changed.append(path)
                _ = hadChildren
            } else {
                changed.append(path)
            }
        }

        return Array(Set(changed)).sorted()
    }

    // MARK: - Per-path ownership evidence classification

    // Determines what kind of ownership claim ATLAS can make on a filesystem path
    // based on pre/post install snapshots and install timing.
    //
    // This is the generic evidence gate: receipt attribution (timestamp) tells ATLAS
    // WHICH receipts were touched; this function tells ATLAS WHETHER EACH FILE was
    // actually written by the installer.
    //
    // Evidence hierarchy:
    //   1. Path in afterFS with ctime advanced during window  → created or replaced
    //   2. Path in afterFS with ctime NOT advanced            → preExistingUnchanged
    //   3. Path not in afterFS (outside deepLocations)        → bomOnly
    //
    // 5-second grace applied to installStart to cover installers that start writing
    // files slightly before the receipt is first registered.
    static func classifyPath(
        _ path: String,
        before: Snapshot,
        after: Snapshot,
        installStart: Date
    ) -> FileOwnershipEvidence {
        let grace = installStart.addingTimeInterval(-5)

        guard let afterDates = after.deep[path] else {
            // Path is outside deepLocations — no ctime evidence available.
            return .bomOnly
        }

        // Use max(mtime, ctime): ctime cannot be reset by user-space; mtime can.
        // Using the later of the two gives the most accurate "when was this written" signal.
        let afterEffective = max(afterDates.mtime, afterDates.ctime)

        if let beforeDates = before.deep[path] {
            // Path existed before install.
            let beforeEffective = max(beforeDates.mtime, beforeDates.ctime)
            if afterEffective > beforeEffective && afterDates.ctime >= grace {
                // Installer wrote the file (ctime advanced during install window).
                return .transactionReplaced
            } else {
                // Installer declared the path in its BOM but did not write the file.
                return .preExistingUnchanged
            }
        } else {
            // Path did not exist before install.
            if afterDates.ctime >= grace {
                return .transactionCreated
            } else {
                // File appeared in afterFS but its ctime predates the install window.
                // This can happen on APFS when timestamps are inherited from a source.
                // Treat conservatively: .bomOnly (no reliable write evidence).
                return .bomOnly
            }
        }
    }

    // MARK: - Build InstalledFile records

    static func buildInstalledFiles(changedPaths: [String]) -> [InstallRecord.InstalledFile] {
        // Plain directories are containers, not installation artifacts.
        // A directory appearing in changedPaths means its modDate changed because
        // an installer added files to it — not that ATLAS owns the directory itself.
        // Bundle-format directories (.aaxplugin, .component, .vst3, etc.) are treated
        // as opaque file units and must continue to be tracked.
        // Empty parent directories are cleaned up by Phase 6 cleanupEmptyDirs.
        let bundleExts: Set<String> = [
            "aaxplugin", "clap", "component", "vst3", "vst",
            "app", "framework", "plugin", "kext", "appex", "bundle"
        ]
        let fm = FileManager.default
        return changedPaths.compactMap { path in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDir)
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            if isDir.boolValue && !bundleExts.contains(ext) { return nil }
            return InstallRecord.InstalledFile(
                sourceName: URL(fileURLWithPath: path).lastPathComponent,
                destinationPath: path
            )
        }
    }
}
