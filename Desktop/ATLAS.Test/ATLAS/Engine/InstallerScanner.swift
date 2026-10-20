import Foundation

struct ExistingInstall {
    let itemName: String
    let path: String
    let version: String?
}

struct ScanResult {
    let fileURL: URL
    let installerType: InstallerType
    let contentsFound: [FoundItem]
    var confidence: Int
    var warnings: [String]
    let recommendation: String
    var diskSpaceWarning: String? = nil
    var existingInstall: ExistingInstall? = nil
    var isQuarantined: Bool = false
    var estimatedPayloadBytes: Int64 = 0
    var requiresStorageSelection: Bool = false   // Pro: true when payload > 5 GB
    var isWindowsExe: Bool = false
    var isWindowsKeygen: Bool = false
    var docInfo: InstallerDocInfo? = nil   // activation docs parsed from installer media
    var blockedDAWName: String? = nil      // non-nil when DAWInstallationGate blocked this installer
    var canInstall: Bool { confidence >= 50 && blockedDAWName == nil }

    var category: ContentCategory {
        InstallerClassifier.categorize(
            url: fileURL,
            contents: contentsFound.map(\.type)
        )
    }
}

struct FoundItem: Identifiable {
    let id = UUID()
    let name: String
    let type: FoundItemType
    let size: String
    var arch: String? = nil        // "Universal", "Apple Silicon", "Intel"
    var minOSVersion: String? = nil // e.g. "12.0" from LSMinimumSystemVersion
}

enum FoundItemType {
    case app
    case interactiveInstaller  // .app that is itself a GUI installer wizard
    case pkg
    case component
    case vst3
    case vst
    case aax
    case zip
    case dmg
    case iso
    case script
    case readme
    case unknown

    var icon: String {
        switch self {
        case .app:                  return "app.badge"
        case .interactiveInstaller: return "person.crop.square"
        case .pkg:                  return "shippingbox"
        case .component: return "puzzlepiece"
        case .vst3:      return "puzzlepiece.fill"
        case .vst:       return "puzzlepiece"
        case .aax:       return "puzzlepiece.fill"
        case .zip:       return "archivebox"
        case .dmg:       return "externaldrive"
        case .iso:       return "opticaldisc"
        case .script:    return "terminal"
        case .readme:    return "doc.text"
        case .unknown:   return "doc"
        }
    }

    var label: String {
        switch self {
        case .app:                  return "Application"
        case .interactiveInstaller: return "Interactive installer"
        case .pkg:                  return "Package installer"
        case .component: return "Audio Unit component"
        case .vst3:      return "VST3 plugin"
        case .vst:       return "VST plugin"
        case .aax:       return "AAX plugin"
        case .zip:       return "ZIP archive"
        case .dmg:       return "Disk image"
        case .iso:       return "ISO disc image"
        case .script:    return "Shell script"
        case .readme:    return "Instructions"
        case .unknown:   return "File"
        }
    }
}

struct InstallerScanner {

    static func scan(url: URL) async -> ScanResult {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            if let ncint = InstallerClassifier.findNcintFile(in: url) {
                return scanKontaktLibrary(url: url, ncintURL: ncint)
            }
            // Plain folder — look inside for installable files and guide the user
            return scanFolder(url: url)
        }

        let ext = url.pathExtension.lowercased()
        var result: ScanResult
        switch ext {
        case "dmg":       result = await scanMountable(url: url, type: .dmg)
        case "iso":       result = await scanMountable(url: url, type: .iso)
        case "zip":       result = await scanZIPByExtracting(url: url)
        case "app":       result = scanAPP(url: url)
        case "pkg":       result = scanPKG(url: url)
        case "component": result = scanPlugin(url: url, type: .component)
        case "vst3":      result = scanPlugin(url: url, type: .vst3)
        case "vst":       result = scanPlugin(url: url, type: .vst)
        case "aaxplugin": result = scanPlugin(url: url, type: .aax)
        case "rar", "7z", "001":
            result = await scanArchive(url: url)
        case "exe", "msi":
            let lower = url.lastPathComponent.lowercased()
            let isKeygen = ["keygen", "keygen", "patch", "crack", "activat"].contains(where: { lower.contains($0) })
            let warning = isKeygen
                ? "Windows activation tool detected. It cannot run on macOS natively — see the guide below."
                : "This is a Windows executable and cannot run on macOS natively."
            let rec = isKeygen
                ? "Follow the guide to run this tool using Wine or Crossover, then return to ATLAS when done."
                : "To run Windows software on Mac, use Wine (free) or Crossover (paid). Once you have a Mac-compatible installer, drop it into ATLAS."
            var r = ScanResult(
                fileURL: url, installerType: .exe,
                contentsFound: [], confidence: 0,
                warnings: [warning],
                recommendation: rec
            )
            r.isWindowsExe = true
            r.isWindowsKeygen = isKeygen
            return r
        default:
            return ScanResult(
                fileURL: url, installerType: .unsupported(ext),
                contentsFound: [], confidence: 0,
                warnings: ["Unsupported file type: .\(ext)"],
                recommendation: "ATLAS cannot install this file type yet."
            )
        }

        // Post-scan enrichment — runs on every supported type
        result.isQuarantined     = checkQuarantine(url)
        result.existingInstall   = checkExistingInstall(for: result.contentsFound)

        // Warn if RAR/7z with no extraction tool (ATLAS will auto-install unar)
        if ["rar","7z","001"].contains(ext) && !ArchiveExtractor.hasAnyTool {
            result.warnings.append("No extraction tool found. ATLAS will automatically install unar before extracting this archive.")
        }

        // #8 — Multi-part archive guidance
        let fname = url.lastPathComponent.lowercased()
        let isMultiPart = fname.contains(".part") ||
                          ext == "001" ||
                          fname.range(of: #"\.r\d{2}$"#, options: .regularExpression) != nil
        let isNotFirstPart = fname.contains(".part") && !fname.contains(".part1") && !fname.contains(".part01") && !fname.contains(".part001")
        if isMultiPart && isNotFirstPart {
            result.warnings.append("This looks like part of a multi-part archive. Drop the first part (.part1, .part01, or .001) into ATLAS — it will automatically find and use the remaining parts.")
        } else if ext == "001" || (fname.contains(".part1.") || fname.contains(".part01.") || fname.contains(".part001.")) {
            result.warnings.append("Multi-part archive detected. Make sure all parts are in the same folder as this file.")
        }

        return result
    }

    // MARK: - Plain folder scan

    private static func scanFolder(url: URL) -> ScanResult {
        let pluginExts: [String: FoundItemType] = [
            "component": .component, "vst3": .vst3, "vst": .vst, "aaxplugin": .aax
        ]
        let installerExts: [String: FoundItemType] = [
            "dmg": .dmg, "iso": .iso, "zip": .zip,
            "pkg": .pkg, "mpkg": .pkg, "app": .app
        ]
        // Instruction/documentation extensions collected for display and instruction parsing.
        let instructionExts = Set(["rtf", "txt", "nfo", "md", "htm", "html", "pdf"])

        var found: [FoundItem] = []
        let fm = FileManager.default

        // Recursive walk — does NOT follow symlinks (FileManager.enumerator default).
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ScanResult(
                fileURL: url, installerType: .unsupported("folder"),
                contentsFound: [], confidence: 0,
                warnings: ["No supported plugin or installer was found in this folder."],
                recommendation: "Drag a .dmg, .pkg, .zip, or plugin bundle (.component, .vst3) directly into ATLAS."
            )
        }

        for case let item as URL in enumerator {
            let name = item.lastPathComponent
            guard !name.hasPrefix("._"), !name.hasPrefix("."),
                  !item.path.contains("/__MACOSX/") else { continue }
            let ext = item.pathExtension.lowercased()

            if let pluginType = pluginExts[ext] {
                // Plugin bundle is a terminal installable unit — do not crawl its internals.
                found.append(FoundItem(name: name, type: pluginType, size: folderSize(item.path)))
                enumerator.skipDescendants()
            } else if var installerType = installerExts[ext] {
                if installerType == .app && isInteractiveInstallerApp(item) {
                    installerType = .interactiveInstaller
                }
                found.append(FoundItem(name: name, type: installerType, size: folderSize(item.path)))
                enumerator.skipDescendants()  // don't enter app/.mpkg bundles or archives
            } else if instructionExts.contains(ext) {
                found.append(FoundItem(name: name, type: .readme, size: ""))
            }
        }

        if found.isEmpty {
            return ScanResult(
                fileURL: url, installerType: .unsupported("folder"),
                contentsFound: [], confidence: 0,
                warnings: ["No supported plugin or installer was found in this folder."],
                recommendation: "Drag a .dmg, .pkg, .zip, or plugin bundle (.component, .vst3) directly into ATLAS."
            )
        }

        let pluginTypes: Set<FoundItemType>    = [.component, .vst3, .vst, .aax]
        let installerTypes: Set<FoundItemType> = [.dmg, .iso, .zip, .pkg, .app, .interactiveInstaller]

        let pluginItems    = found.filter { pluginTypes.contains($0.type) }
        let installerItems = found.filter { installerTypes.contains($0.type) }

        // Plugin-only payload (may include readme/instruction/unrelated files alongside plugins).
        if !pluginItems.isEmpty && installerItems.isEmpty {
            let names = pluginItems.map(\.name).joined(separator: ", ")
            return ScanResult(
                fileURL: url, installerType: .unsupported("folder"),
                contentsFound: found, confidence: 85,
                warnings: [],
                recommendation: "Audio plugins found — ATLAS will install \(names) to your system plugin folders."
            )
        }

        // Installer files present (may also include plugins — mixed payload handled by collectFromFolder).
        if !installerItems.isEmpty {
            let first = installerItems[0].name
            let rec = installerItems.count == 1
                ? "Open this folder in Finder and drag \"\(first)\" directly into ATLAS."
                : "Open this folder in Finder and drag the installer file (\(first)\(installerItems.count > 1 ? ", …" : "")) directly into ATLAS."
            return ScanResult(
                fileURL: url, installerType: .unsupported("folder"),
                contentsFound: found, confidence: 0,
                warnings: ["Folders can't be installed directly — drag the installer file inside instead."],
                recommendation: rec
            )
        }

        // Only readme/unknown files — nothing installable.
        return ScanResult(
            fileURL: url, installerType: .unsupported("folder"),
            contentsFound: found, confidence: 0,
            warnings: ["No supported plugin or installer was found in this folder."],
            recommendation: "Drag a .dmg, .pkg, .zip, or plugin bundle (.component, .vst3) directly into ATLAS."
        )
    }

    // MARK: - Kontakt library folder

    private static func scanKontaktLibrary(url: URL, ncintURL: URL) -> ScanResult {
        let ncintItem = FoundItem(
            name: ncintURL.lastPathComponent,
            type: .unknown,
            size: ""
        )
        return ScanResult(
            fileURL: url,
            installerType: .kontaktLibrary,
            contentsFound: [ncintItem],
            confidence: 95,
            warnings: [],
            recommendation: "ATLAS will register \"\(url.lastPathComponent)\" as a Kontakt library via Native Access."
        )
    }

    // MARK: - Standalone plugin scan
    // .component, .vst3, .vst, .aaxplugin dropped directly

    private static func scanPlugin(url: URL, type: FoundItemType) -> ScanResult {
        let item = FoundItem(name: url.lastPathComponent,
                            type: type,
                            size: folderSize(url.path))

        let destination: String
        let installerType: InstallerType
        switch type {
        case .component:
            destination = "/Library/Audio/Plug-Ins/Components"
            installerType = .component
        case .vst3:
            destination = "/Library/Audio/Plug-Ins/VST3"
            installerType = .vst3
        case .vst:
            destination = "/Library/Audio/Plug-Ins/VST"
            installerType = .vst
        case .aax:
            destination = "/Library/Application Support/Avid/Audio/Plug-Ins"
            installerType = .aax
        default:
            destination = "/Library/Audio/Plug-Ins"
            installerType = .unsupported(url.pathExtension)
        }

        return ScanResult(
            fileURL: url,
            installerType: installerType,
            contentsFound: [item],
            confidence: 90,
            warnings: [],
            recommendation: "ATLAS will copy \(url.lastPathComponent) to \(destination) and apply codesign."
        )
    }

    // MARK: - DMG / ISO

    private static func scanMountable(url: URL, type: InstallerType) async -> ScanResult {
        // If this exact image path is already mounted, reuse it.
        if let existing = findExistingMount(for: url.path) {
            let items   = listContents(of: existing, shallow: true)
            let docInfo = InstallerDocParser.scan(volumeURL: URL(fileURLWithPath: existing))
            return buildResult(url: url, type: type, items: items, docInfo: docInfo)
        }

        let mountPoint = "/Volumes/ATLAS_SCAN_\(UUID().uuidString.prefix(6))"

        // Mount without -quiet so we get the actual error message on failure.
        var mountResult = runProcess(
            path: "/usr/bin/hdiutil",
            arguments: ["attach", url.path, "-mountpoint", mountPoint,
                       "-nobrowse", "-noverify"],
            timeout: 20
        )
        if !mountResult.success {
            mountResult = runProcess(
                path: "/usr/bin/hdiutil",
                arguments: ["attach", url.path, "-mountpoint", mountPoint,
                           "-nobrowse"],
                timeout: 20
            )
        }

        // "Resource busy" means the same disc image content is mounted under a
        // different path (e.g. a copy in Downloads vs Desktop). Detach all stale
        // ATLAS volumes and retry once.
        if !mountResult.success &&
            mountResult.output.contains("Resource busy") {
            detachAllATLASVolumes()
            mountResult = runProcess(
                path: "/usr/bin/hdiutil",
                arguments: ["attach", url.path, "-mountpoint", mountPoint,
                           "-nobrowse"]
            )
        }

        guard mountResult.success else {
            let msg = mountResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            // Can't scan contents but the file itself is a valid disk image — still allow install
            return ScanResult(
                fileURL: url, installerType: type,
                contentsFound: [], confidence: 75,
                warnings: ["Contents could not be pre-scanned (the installer will still run normally)."],
                recommendation: "Proceed with installation."
            )
        }
        let items   = listContents(of: mountPoint, shallow: true)
        // DAW gate — check discovered .app and .pkg candidates before detaching
        let mountBase = URL(fileURLWithPath: mountPoint)
        let appCandidates = items.filter { $0.type == .app || $0.type == .interactiveInstaller }
                                 .map { mountBase.appendingPathComponent($0.name) }
        let pkgCandidates = items.filter { $0.type == .pkg }
                                 .map { mountBase.appendingPathComponent($0.name) }
        var dawBlock: String? = nil
        if case .blocked(let name) = DAWInstallationGate.checkCandidates(appCandidates) {
            dawBlock = name
        }
        if dawBlock == nil {
            for pkgURL in pkgCandidates {
                if case .blocked(let name) = DAWInstallationGate.checkPKG(url: pkgURL) {
                    dawBlock = name; break
                }
            }
        }
        // Scan for installer documentation before detaching the volume
        let docInfo = InstallerDocParser.scan(volumeURL: URL(fileURLWithPath: mountPoint))
        let r = runProcess(path: "/usr/bin/hdiutil",
                          arguments: ["detach", mountPoint, "-quiet"], timeout: 10)
        if !r.success {
            _ = runProcess(path: "/usr/bin/hdiutil",
                          arguments: ["detach", mountPoint, "-force", "-quiet"], timeout: 10)
        }
        var result = buildResult(url: url, type: type, items: items, docInfo: docInfo)
        if let name = dawBlock {
            result.blockedDAWName = name
            result.confidence = 0
        }
        return result
    }

    private static func findExistingMount(for imagePath: String) -> String? {
        let result = runProcess(path: "/usr/bin/hdiutil", arguments: ["info", "-plist"])
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

    // Force-detaches any /Volumes/ATLAS_* left from a previous session.
    private static func detachAllATLASVolumes() {
        let info = runProcess(path: "/usr/bin/hdiutil", arguments: ["info"])
        guard info.success else { return }
        for line in info.output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("/Volumes/ATLAS_") else { continue }
            let path = trimmed.components(separatedBy: .whitespaces).first ?? trimmed
            var r = runProcess(path: "/usr/bin/hdiutil",
                              arguments: ["detach", path, "-quiet"])
            if !r.success {
                r = runProcess(path: "/usr/bin/hdiutil",
                              arguments: ["detach", path, "-force", "-quiet"])
            }
        }
    }

    // MARK: - ZIP

    private static func scanZIPByExtracting(url: URL) async -> ScanResult {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLAS_SCAN_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(
                at: tempDir, withIntermediateDirectories: true)
        } catch {
            return buildResult(url: url, type: .zip, items: [])
        }

        // -P "" prevents unzip from prompting for a password — it will just fail fast
        // if the ZIP is encrypted, which is the correct behavior for a scan.
        let unzipResult = runProcess(
            path: "/usr/bin/unzip",
            arguments: ["-q", "-P", "", url.path, "-d", tempDir.path],
            timeout: 30
        )
        guard unzipResult.success else {
            let isEncrypted = unzipResult.output.lowercased().contains("encrypted") ||
                              unzipResult.output.lowercased().contains("password")
            return ScanResult(
                fileURL: url, installerType: .zip,
                contentsFound: [], confidence: 60,
                warnings: isEncrypted ? ["This ZIP is password-protected."] : ["Could not read ZIP contents"],
                recommendation: isEncrypted
                    ? "ATLAS will ask for the password when you begin the install."
                    : "ZIP may be corrupted or password-protected."
            )
        }
        let items   = listContents(of: tempDir.path, shallow: false)
        // Scan for docs while the temp dir still exists (defer will remove it after return)
        let docInfo = InstallerDocParser.scan(volumeURL: tempDir)
        var result = buildResult(url: url, type: .zip, items: items, docInfo: docInfo)
        // DAW gate — check discovered .app candidates in the extracted archive
        let appCandidates = items.filter { $0.type == .app || $0.type == .interactiveInstaller }
                                 .map { tempDir.appendingPathComponent($0.name) }
        let pkgCandidates = items.filter { $0.type == .pkg }
                                 .map { tempDir.appendingPathComponent($0.name) }
        if case .blocked(let name) = DAWInstallationGate.checkCandidates(appCandidates) {
            result.blockedDAWName = name
            result.confidence = 0
        } else {
            for pkgURL in pkgCandidates {
                if case .blocked(let name) = DAWInstallationGate.checkPKG(url: pkgURL) {
                    result.blockedDAWName = name
                    result.confidence = 0
                    break
                }
            }
        }
        return result
    }

    // MARK: - APP / PKG

    private static func scanAPP(url: URL) -> ScanResult {
        let actualType: FoundItemType = isInteractiveInstallerApp(url) ? .interactiveInstaller : .app
        let item = FoundItem(name: url.lastPathComponent, type: actualType, size: folderSize(url.path))
        let installerType: InstallerType = actualType == .interactiveInstaller ? .app : .app
        var result = buildResult(url: url, type: installerType, items: [item])
        if case .blocked(let name) = DAWInstallationGate.check(appURL: url) {
            result.blockedDAWName = name
            result.confidence = 0
        }
        return result
    }

    private static func scanPKG(url: URL) -> ScanResult {
        var item = FoundItem(name: url.lastPathComponent, type: .pkg,
                            size: folderSize(url.path))
        item.minOSVersion = detectMinOSFromPKG(at: url)
        var result = buildResult(url: url, type: .pkg, items: [item])
        if case .blocked(let name) = DAWInstallationGate.checkPKG(url: url) {
            result.blockedDAWName = name
            result.confidence = 0
        }
        return result
    }

    // MARK: - RAR / 7z / 001 archives

    private static func scanArchive(url: URL) async -> ScanResult {
        guard ArchiveExtractor.hasAnyTool else {
            // No extraction tool yet — ATLAS will auto-install unar before extracting.
            return ScanResult(
                fileURL: url, installerType: .zip,
                contentsFound: [], confidence: 65,
                warnings: ["No extraction tool found. ATLAS will automatically install unar before extracting this archive."],
                recommendation: "ATLAS will extract this archive and install the contents."
            )
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLAS_SCAN_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return buildResult(url: url, type: .zip, items: [])
        }

        let extractResult = ArchiveExtractor.extract(url: url, to: tempDir.path)
        guard extractResult.success else {
            let errMsg = extractResult.error ?? "Could not read archive"
            let isPassword = errMsg.lowercased().contains("password") ||
                             errMsg.lowercased().contains("encrypted")
            return ScanResult(
                fileURL: url, installerType: .zip,
                contentsFound: [], confidence: 60,
                warnings: [isPassword ? "This archive is password-protected." : "Could not read archive contents."],
                recommendation: isPassword
                    ? "ATLAS will ask for the password when you begin the install."
                    : "Archive may be corrupted or require a different extraction tool."
            )
        }

        let items   = listContents(of: tempDir.path, shallow: false)
        let docInfo = InstallerDocParser.scan(volumeURL: tempDir)
        return buildResult(url: url, type: .zip, items: items, docInfo: docInfo)
    }

    // MARK: - Directory listing

    /// Lists installable items inside `path`.
    /// `shallow: true` — only top-level entries (fast; used for mounted disk images).
    /// `shallow: false` — full recursive walk (used for extracted ZIPs / temp dirs).
    private static func listContents(of path: String, shallow: Bool = false) -> [FoundItem] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: path)

        if shallow {
            // Top-level only — no deep scan needed for mounted volumes.
            guard let entries = try? fm.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }

            var items: [FoundItem] = []
            var seen = Set<String>()
            for fileURL in entries {
                let fileName = fileURL.lastPathComponent
                guard !fileName.hasPrefix("._"), !fileName.hasPrefix(".") else { continue }
                guard !seen.contains(fileName) else { continue }
                seen.insert(fileName)
                let size = folderSize(fileURL.path)
                if var item = classifyFilename(fileName, size: size) {
                    if item.type == .app {
                        item.arch = detectArch(at: fileURL)
                        item.minOSVersion = detectMinOS(at: fileURL)
                    } else if item.type == .pkg {
                        item.minOSVersion = detectMinOSFromPKG(at: fileURL)
                    }
                    items.append(item)
                }
            }

            // If no installable content was found at root, look one level deeper inside
            // any top-level directories. This covers the common DMG/ISO pattern where
            // the disk image contains a single named folder with the PKG inside it
            // (e.g. "Teletone Audio PrismPlate v1.0.1/" → "PrismPlate_Mac_Installer.pkg").
            let hasInstallable = items.contains {
                $0.type == .pkg || $0.type == .app ||
                $0.type == .component || $0.type == .vst3 ||
                $0.type == .vst || $0.type == .aax
            }
            if !hasInstallable {
                for dirURL in entries {
                    let dirName = dirURL.lastPathComponent
                    guard !dirName.hasPrefix(".") else { continue }
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                          isDir.boolValue else { continue }
                    guard let subEntries = try? fm.contentsOfDirectory(
                        at: dirURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles]
                    ) else { continue }
                    for subURL in subEntries {
                        let subName = subURL.lastPathComponent
                        guard !subName.hasPrefix("._"), !subName.hasPrefix(".") else { continue }
                        guard !seen.contains(subName) else { continue }
                        seen.insert(subName)
                        let size = folderSize(subURL.path)
                        if var item = classifyFilename(subName, size: size) {
                            if item.type == .app {
                                item.arch = detectArch(at: subURL)
                                item.minOSVersion = detectMinOS(at: subURL)
                            } else if item.type == .pkg {
                                item.minOSVersion = detectMinOSFromPKG(at: subURL)
                            }
                            items.append(item)
                        }
                    }
                }
            }

            return items
        }

        // Full recursive walk for extracted archives.
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [FoundItem] = []
        var seen = Set<String>()

        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent
            guard !fileName.hasPrefix("._"),
                  !fileName.hasPrefix(".") else { continue }
            let fullPath = fileURL.path
            guard !fullPath.contains("/__MACOSX/"),
                  !fullPath.contains("__MACOSX/") else { continue }
            guard !seen.contains(fileName) else { continue }
            seen.insert(fileName)
            let size = folderSize(fullPath)
            if var item = classifyFilename(fileName, size: size) {
                switch item.type {
                case .app:
                    enumerator.skipDescendants()
                    item.arch = detectArch(at: fileURL)
                    item.minOSVersion = detectMinOS(at: fileURL)
                case .pkg:
                    item.minOSVersion = detectMinOSFromPKG(at: fileURL)
                case .component, .vst3, .vst, .aax:
                    enumerator.skipDescendants()
                case .zip:
                    let peekResult = runProcess(path: "/usr/bin/unzip",
                                               arguments: ["-l", fileURL.path], timeout: 10)
                    for line in peekResult.output.components(separatedBy: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        let namePart = trimmed.components(separatedBy: .whitespaces).last ?? ""
                        let nameLower = namePart.lowercased()
                        if nameLower.hasSuffix(".component") && !seen.contains(namePart) {
                            seen.insert(namePart)
                            items.append(FoundItem(name: namePart, type: .component, size: ""))
                        } else if nameLower.hasSuffix(".vst3") && !seen.contains(namePart) {
                            seen.insert(namePart)
                            items.append(FoundItem(name: namePart, type: .vst3, size: ""))
                        } else if nameLower.hasSuffix(".vst") && !nameLower.hasSuffix(".vst3") && !seen.contains(namePart) {
                            seen.insert(namePart)
                            items.append(FoundItem(name: namePart, type: .vst, size: ""))
                        } else if nameLower.hasSuffix(".aaxplugin") && !seen.contains(namePart) {
                            seen.insert(namePart)
                            items.append(FoundItem(name: namePart, type: .aax, size: ""))
                        }
                    }
                default:
                    break
                }
                items.append(item)
            }
        }
        return items
    }

    // MARK: - Classification

    private static func classifyFilename(_ name: String, size: String) -> FoundItem? {
        let lower = name.lowercased()
        guard !name.hasPrefix("._"), !name.hasPrefix(".") else { return nil }

        if lower.hasSuffix(".app")        { return FoundItem(name: name, type: .app, size: size) }
        if lower.hasSuffix(".pkg")        { return FoundItem(name: name, type: .pkg, size: size) }
        if lower.hasSuffix(".component")  { return FoundItem(name: name, type: .component, size: size) }
        if lower.hasSuffix(".vst3")       { return FoundItem(name: name, type: .vst3, size: size) }
        if lower.hasSuffix(".vst")        { return FoundItem(name: name, type: .vst, size: size) }
        if lower.hasSuffix(".aaxplugin")  { return FoundItem(name: name, type: .aax, size: size) }
        if lower.hasSuffix(".zip")        { return FoundItem(name: name, type: .zip, size: size) }
        if lower.hasSuffix(".dmg")        { return FoundItem(name: name, type: .dmg, size: size) }
        if lower.hasSuffix(".iso")        { return FoundItem(name: name, type: .iso, size: size) }
        if lower.hasSuffix(".sh") || lower.hasSuffix(".command") {
            return FoundItem(name: name, type: .script, size: size)
        }
        if lower.hasSuffix(".rtf") || lower.hasSuffix(".txt") || lower.hasSuffix(".md") ||
           lower.hasPrefix("readme") || lower.hasPrefix("install") {
            return FoundItem(name: name, type: .readme, size: size)
        }
        return nil
    }

    // MARK: - Confidence scoring

    private static func buildResult(url: URL, type: InstallerType,
                                   items: [FoundItem],
                                   docInfo: InstallerDocInfo? = nil) -> ScanResult {
        var confidence = 0
        var warnings: [String] = []
        var recommendation = ""

        // Architecture warnings
        let intelApps = items.filter { $0.type == .app && $0.arch == "Intel" }
        if !intelApps.isEmpty {
            if RosettaEngine.isAppleSilicon {
                warnings.append("Intel-only app — Rosetta 2 required on this Mac.")
            } else {
                warnings.append("Intel-only app (x86_64).")
            }
        }

        // macOS minimum version compatibility check — from installer metadata
        let incompatItems = items.filter { item -> Bool in
            guard let minOS = item.minOSVersion else { return false }
            return CompatibilityDatabase.isIncompatible(minOSString: minOS)
        }
        if !incompatItems.isEmpty {
            let minOS = incompatItems.first?.minOSVersion ?? "?"
            let name = incompatItems.first?.name ?? url.lastPathComponent
            warnings.insert(CompatibilityDatabase.incompatibilityWarning(productName: name, minOS: minOS), at: 0)
        }

        // Fallback: check CompatibilityDatabase by filename when installer metadata has no OS declaration
        if incompatItems.isEmpty {
            let checkName = url.lastPathComponent
            if let match = CompatibilityDatabase.lookup(filename: checkName),
               CompatibilityDatabase.isIncompatible(minOSString: match.minOS) {
                warnings.insert(CompatibilityDatabase.incompatibilityWarning(productName: match.productName, minOS: match.minOS), at: 0)
            }
        }

        let hasApp       = items.contains { $0.type == .app }
        let hasPkg       = items.contains { $0.type == .pkg }
        let hasComponent = items.contains { $0.type == .component }
        let hasVST3      = items.contains { $0.type == .vst3 }
        let hasVST       = items.contains { $0.type == .vst }
        let hasAAX       = items.contains { $0.type == .aax }
        let hasScript    = items.contains { $0.type == .script }
        let hasDMG       = items.contains { $0.type == .dmg }
        let hasISO       = items.contains { $0.type == .iso }
        let hasPlugin    = hasComponent || hasVST3 || hasVST || hasAAX

        if hasApp {
            confidence = 95
            recommendation = "Standard app — ATLAS will copy to /Applications."
        } else if hasPkg {
            let pkgCount = items.filter { $0.type == .pkg }.count
            let hasReadme = items.contains { $0.type == .readme }
            let suffix = hasReadme ? " Instructions file detected and will be read." : ""
            confidence = 85
            recommendation = pkgCount > 1
                ? "\(pkgCount) packages found — ATLAS will read instructions and install in correct order.\(suffix)"
                : "Package installer — ATLAS will run the installer.\(suffix)"
        } else if hasPlugin {
            confidence = 85
            var pluginTypes: [String] = []
            if hasComponent { pluginTypes.append("Audio Unit") }
            if hasVST3      { pluginTypes.append("VST3") }
            if hasVST       { pluginTypes.append("VST") }
            if hasAAX       { pluginTypes.append("AAX") }
            recommendation = "Audio plugins found — ATLAS will install \(pluginTypes.joined(separator: ", ")) and apply codesign."
        } else if hasScript {
            confidence = 30
            warnings.append("Shell script detected — review before running.")
            recommendation = "Script installer — manual review recommended."
        } else if hasDMG || hasISO {
            confidence = 80
            let label = hasDMG ? "Disk image" : "ISO disc image"
            recommendation = "\(label) found inside — ATLAS will mount and install from it."
        } else if items.isEmpty {
            confidence = 0
            warnings.append("No installable content found inside.")
            recommendation = "ATLAS could not find anything to install."
        } else {
            confidence = 20
            warnings.append("Unknown installer format.")
            recommendation = "ATLAS is not sure how to install this automatically."
        }

        // Disk space check
        let available = availableDiskBytes()
        let estimated = estimateInstallBytes(sourceURL: url)
        var diskSpaceWarning: String? = nil
        if available > 0 && estimated > 0 {
            if available < estimated {
                diskSpaceWarning = "Not enough space — need ~\(formatBytes(estimated)), only \(formatBytes(available)) free."
            } else if available < Int64(Double(estimated) * 1.15) {
                diskSpaceWarning = "Space is tight — ~\(formatBytes(estimated)) needed, \(formatBytes(available)) free."
            }
        }

        // TITAN CORE™: flag large installs (>5 GB) for storage selection (Standard + Pro)
        let needsStorageSelection = estimated > StorageManager.largeInstallThreshold

        var result = ScanResult(
            fileURL: url, installerType: type,
            contentsFound: items, confidence: confidence,
            warnings: warnings, recommendation: recommendation,
            diskSpaceWarning: diskSpaceWarning
        )
        result.estimatedPayloadBytes    = estimated
        result.requiresStorageSelection = needsStorageSelection
        result.docInfo                  = docInfo
        return result
    }

    // MARK: - Helpers

    private static func folderSize(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return "" }
        return formatSize(String(size))
    }

    private static func formatSize(_ raw: String) -> String {
        guard let bytes = Int64(raw) else { return "" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return "\(bytes / (1024 * 1024)) MB"
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        if bytes < 1024 * 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
        return String(format: "%.2f GB", Double(bytes) / (1024 * 1024 * 1024))
    }

    private static func availableDiskBytes() -> Int64 {
        (try? FileManager.default
            .attributesOfFileSystem(forPath: "/Applications"))?[.systemFreeSize] as? Int64 ?? 0
    }

    // Estimates installed size from the source file using type-based multipliers.
    private static func estimateInstallBytes(sourceURL: URL) -> Int64 {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: sourceURL.path))?[.size] as? Int64,
              size > 0 else { return 0 }
        switch sourceURL.pathExtension.lowercased() {
        case "zip":       return Int64(Double(size) * 3.0)
        case "dmg", "iso": return Int64(Double(size) * 1.4)
        case "pkg":       return Int64(Double(size) * 2.5)
        case "app":       return size
        default:          return Int64(Double(size) * 2.0)
        }
    }

    // Reads LSMinimumSystemVersion from a .app bundle's Info.plist.
    private static func detectMinOS(at appURL: URL) -> String? {
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: infoPlist) else { return nil }
        return dict["LSMinimumSystemVersion"] as? String
    }

    // Reads the Distribution XML from a .pkg file to find the minimum OS requirement.
    // Uses `xar -xOf` to extract just the Distribution file from the XAR archive.
    private static func detectMinOSFromPKG(at pkgURL: URL) -> String? {
        // xar extracts a named file from a XAR archive to stdout
        let result = runProcess(
            path: "/usr/bin/xar",
            arguments: ["-xOf", pkgURL.path, "Distribution"],
            timeout: 8
        )
        guard result.success, !result.output.isEmpty else { return nil }
        return parseOSVersionFromDistribution(result.output)
    }

    // Parses <os-version min="X.Y.Z"/> or <allowed-os-versions><os-version min="..."/>
    // from a PKG Distribution XML string.
    private static func parseOSVersionFromDistribution(_ xml: String) -> String? {
        // Pattern: min="12.0" or min="10.15.7"
        let pattern = #"min\s*=\s*"([\d]+\.[\d]+(?:\.[\d]+)?)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let versionRange = Range(match.range(at: 1), in: xml) else { return nil }
        let version = String(xml[versionRange])
        // Sanity check: ignore suspiciously low versions (e.g. "1.0" is the spec version)
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first, major >= 10 else { return nil }
        return version
    }

    // Reads the main binary of a .app bundle and returns arch string via /usr/bin/file.
    private static func detectArch(at appURL: URL) -> String? {
        let infoPlist = appURL.appendingPathComponent("Contents/Info.plist")
        let execName: String
        if let dict = NSDictionary(contentsOf: infoPlist),
           let exec = dict["CFBundleExecutable"] as? String, !exec.isEmpty {
            execName = exec
        } else {
            execName = appURL.deletingPathExtension().lastPathComponent
        }
        let binary = appURL.appendingPathComponent("Contents/MacOS/\(execName)")
        guard FileManager.default.fileExists(atPath: binary.path) else { return nil }
        let result = runProcess(path: "/usr/bin/file", arguments: [binary.path])
        let out = result.output.lowercased()
        if out.contains("universal binary") { return "Universal" }
        if out.contains("arm64")            { return "Apple Silicon" }
        if out.contains("x86_64")           { return "Intel" }
        return nil
    }

    // MARK: - Interactive installer detection

    /// Returns true if an .app bundle at the given URL is a GUI installer wizard
    /// rather than the actual product app. These must be launched by the user, not
    /// silently copied to /Applications.
    static func isInteractiveInstallerApp(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()

        // Known manager/installer app name fragments
        let installerKeywords = [
            "install", "setup", "wizard", "assistant",
            "native access", "nativeaccess",
            "waves central", "wavecentral",
            "activation manager", "license manager",
            "focusrite control", "focusrite installer",
            "arturia software center", "software center",
            "ua connect", "uad connect", "universal audio",
            "ilok", "pace",
            "kontakt player", "service center",
            "izotope product portal", "product portal",
            "plugin boutique manager",
            "antares auto-tune installer",
        ]
        if installerKeywords.contains(where: { name.contains($0) }) { return true }

        // If the bundle's CFBundleName or CFBundleDisplayName says "Installer"
        let infoPlist = url.appendingPathComponent("Contents/Info.plist")
        if let dict = NSDictionary(contentsOf: infoPlist) {
            let bundleName = (dict["CFBundleName"] as? String ?? "").lowercased()
            let displayName = (dict["CFBundleDisplayName"] as? String ?? "").lowercased()
            if bundleName.contains("install") || bundleName.contains("setup") ||
               bundleName.contains("wizard") || bundleName.contains("assistant") ||
               displayName.contains("install") || displayName.contains("setup") {
                return true
            }
            // installbuilder-based apps have a characteristic Info.plist key
            if dict["LSApplicationCategoryType"] == nil &&
               (dict["CFBundleIdentifier"] as? String ?? "").contains("install") {
                return true
            }
        }

        // Check for installbuilder.sh in Contents/MacOS — dead giveaway
        let macosDir = url.appendingPathComponent("Contents/MacOS")
        if FileManager.default.fileExists(atPath: macosDir.appendingPathComponent("installbuilder.sh").path) {
            return true
        }

        return false
    }

    // MARK: - Quarantine detection

    private static func checkQuarantine(_ url: URL) -> Bool {
        // getxattr returns the attribute size (≥0) if present, -1 if absent.
        let size = getxattr(url.path, "com.apple.quarantine", nil, 0, 0, 0)
        return size >= 0
    }

    // MARK: - Existing install detection

    static func checkExistingInstall(for items: [FoundItem]) -> ExistingInstall? {
        let fm   = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // Apps — check /Applications, ~/Applications, /Applications/Utilities
        let appDirs = ["/Applications", home + "/Applications", "/Applications/Utilities"]
        for item in items where item.type == .app {
            for dir in appDirs {
                let path = dir + "/" + item.name
                if fm.fileExists(atPath: path) {
                    return ExistingInstall(
                        itemName: item.name, path: path,
                        version: readBundleVersion(URL(fileURLWithPath: path)))
                }
            }
        }

        // Plugins — check system + user plugin directories
        let pluginChecks: [(FoundItemType, [String])] = [
            (.vst3,      ["/Library/Audio/Plug-Ins/VST3",
                          home + "/Library/Audio/Plug-Ins/VST3"]),
            (.component, ["/Library/Audio/Plug-Ins/Components",
                          home + "/Library/Audio/Plug-Ins/Components"]),
            (.aax,       ["/Library/Application Support/Avid/Audio/Plug-Ins"]),
            (.vst,       ["/Library/Audio/Plug-Ins/VST",
                          home + "/Library/Audio/Plug-Ins/VST"]),
        ]
        for item in items {
            for (type, dirs) in pluginChecks where item.type == type {
                for dir in dirs {
                    let path = dir + "/" + item.name
                    if fm.fileExists(atPath: path) {
                        return ExistingInstall(itemName: item.name, path: path, version: nil)
                    }
                }
            }
        }
        return nil
    }

    private static func readBundleVersion(_ url: URL) -> String? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plist) else { return nil }
        return dict["CFBundleShortVersionString"] as? String
            ?? dict["CFBundleVersion"] as? String
    }

    private static func runProcess(path: String,
                                  arguments: [String],
                                  timeout: TimeInterval = 15) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (false, error.localizedDescription)
        }

        // Read pipe on background thread to prevent buffer deadlock (pipe fills at 64KB).
        var outputData = Data()
        let sema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            sema.signal()
        }

        let deadline = DispatchTime.now() + timeout
        let killItem = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: killItem)
        process.waitUntilExit()
        killItem.cancel()
        _ = sema.wait(timeout: .now() + 5)
        return (process.terminationStatus == 0, String(data: outputData, encoding: .utf8) ?? "")
    }
}
