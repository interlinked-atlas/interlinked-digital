import Foundation
import SwiftUI

// MARK: - Installer file type (container format)

enum InstallerType {
    case dmg
    case iso
    case zip
    case app
    case interactiveInstaller  // .app that is itself a GUI installer wizard
    case pkg
    case component
    case vst3
    case vst
    case aax
    case kontaktLibrary
    case exe          // Windows .exe run via Wine or CrossOver
    case unsupported(String)
}

// MARK: - Content category (what the installer actually contains)

enum ContentCategory: String {
    case audioPlugin    = "Audio Plugin"
    case sampleLibrary  = "Sample Library"
    case daw            = "DAW"
    case app            = "App"
    case utility        = "Utility"
    case driver         = "Driver"
    case font           = "Font"
    case unknown        = "Unknown"

    var icon: String {
        switch self {
        case .audioPlugin:   return "waveform"
        case .sampleLibrary: return "pianokeys.inverse"
        case .daw:           return "pianokeys"
        case .app:           return "app.fill"
        case .utility:       return "wrench.and.screwdriver.fill"
        case .driver:        return "cpu"
        case .font:          return "textformat"
        case .unknown:       return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .audioPlugin:   return Color(hex: "#9B6DFF")
        case .sampleLibrary: return Color(hex: "#E67E22")
        case .daw:           return Color(hex: "#3B82F6")
        case .app:           return Color(hex: "#3ECFB2")
        case .utility:       return Color(hex: "#F0A030")
        case .driver:        return Color(hex: "#E05555")
        case .font:          return Color(hex: "#EC4899")
        case .unknown:       return Color(hex: "#696E7C")
        }
    }
}

// MARK: - Classifier

struct InstallerClassifier {

    static func classify(url: URL) -> InstallerType {
        // Check for Kontakt library folder first (directory containing .ncint)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue && findNcintFile(in: url) != nil {
            return .kontaktLibrary
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "dmg":         return .dmg
        case "iso":         return .iso
        case "zip":         return .zip
        case "app":         return .app
        case "pkg":         return .pkg
        case "component":   return .component
        case "vst3":        return .vst3
        case "vst":         return .vst
        case "aaxplugin":   return .aax
        case "exe":         return .exe
        case "rar", "7z", "tar", "gz", "bz2", "xz", "001": return .zip  // treat all archives as zip — InstallEngine handles extraction
        default:            return .unsupported(ext)
        }
    }

    // Finds the first .ncint file within a folder (Kontakt library marker).
    static func findNcintFile(in folderURL: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "ncint" { return url }
        }
        return nil
    }

    // Determines what the installer actually contains / installs.
    // `contents` comes from InstallerScanner — the items found inside.
    static func categorize(url: URL, contents: [FoundItemType]) -> ContentCategory {
        let ext  = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent.lowercased()

        // ── Kontakt library folder ────────────────────────────────────
        if ext.isEmpty || url.hasDirectoryPath {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue && findNcintFile(in: url) != nil { return .sampleLibrary }
        }

        // ── Direct plugin formats ─────────────────────────────────────
        if ["component", "vst3", "vst", "aaxplugin"].contains(ext) {
            return .audioPlugin
        }

        // ── Driver / kernel extension ─────────────────────────────────
        if ext == "kext" { return .driver }

        // ── Font ──────────────────────────────────────────────────────
        if ["ttf", "otf", "woff", "woff2"].contains(ext) { return .font }

        // ── Contents tell us definitively ─────────────────────────────
        let pluginTypes: Set<FoundItemType> = [.component, .vst3, .vst, .aax]
        let pluginCount = contents.filter { pluginTypes.contains($0) }.count
        if pluginCount > 0 { return .audioPlugin }

        // ── DAW keyword match ─────────────────────────────────────────
        let dawKeywords = [
            "logic", "protools", "pro tools", "ableton", "live",
            "fl studio", "flstudio", "cubase", "nuendo", "reaper",
            "studioone", "studio one", "garageband", "bitwig",
            "reason", "digital performer", "dp10", "dp11",
            "presonus", "steinberg", "avid"
        ]
        if dawKeywords.contains(where: { name.contains($0) }) { return .daw }

        // ── Utility keyword match ─────────────────────────────────────
        let utilKeywords = [
            "driver", "firmware", "codec", "tool", "utility", "helper",
            "setup", "configurator", "patcher", "uninstaller", "cleaner",
            "monitor", "control", "manager", "panel"
        ]
        if utilKeywords.contains(where: { name.contains($0) }) { return .utility }

        // ── App bundle ────────────────────────────────────────────────
        if ext == "app" || contents.contains(.app) { return .app }

        // ── PKG with no plugin contents → likely app or utility ───────
        if ext == "pkg" { return .app }

        return .unknown
    }

    // MARK: - Self-protection

    /// Returns true if the given URL is ATLAS itself (dmg, app, or pkg).
    /// ATLAS must never install or uninstall itself.
    static func isAtlasItself(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let ext  = url.pathExtension.lowercased()

        // Filename match
        if name == "atlas" { return true }

        // For .app bundles, check the bundle identifier
        if ext == "app" {
            let infoPlist = url.appendingPathComponent("Contents/Info.plist")
            if let dict = NSDictionary(contentsOf: infoPlist),
               let bundleID = dict["CFBundleIdentifier"] as? String {
                let myID = Bundle.main.bundleIdentifier ?? "com.interlinked.atlas"
                if bundleID == myID { return true }
            }
        }

        return false
    }
}

// Make FoundItemType equatable/hashable for Set operations
extension FoundItemType: Equatable, Hashable {}
