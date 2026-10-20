import Foundation

// PluginPathAdvisor — detects when a DAW is configured to scan a non-standard
// plugin location (e.g. an external drive), and warns the user if ATLAS is
// about to install to the system path which that DAW will never find.

struct PluginScanPath {
    let daw: String
    let path: String
    let isExternal: Bool  // on a mounted volume other than /
}

struct PluginPathAdvisor {

    // Standard system locations ATLAS installs to
    static let systemPluginDirs: [String] = [
        "/Library/Audio/Plug-Ins/Components",
        "/Library/Audio/Plug-Ins/VST3",
        "/Library/Audio/Plug-Ins/VST",
        "/Library/Application Support/Avid/Audio/Plug-Ins",
    ]

    // MARK: - DAW scan path detection

    /// Read each DAW's known config file to find custom scan paths.
    static func customScanPaths() -> [PluginScanPath] {
        var results: [PluginScanPath] = []
        results += logicPaths()
        results += abletonPaths()
        results += studioOnePaths()
        results += cubasePaths()
        results += bitwigPaths()
        return results
    }

    /// Returns paths that are on external volumes (not the boot drive).
    static func externalScanPaths() -> [PluginScanPath] {
        customScanPaths().filter { $0.isExternal }
    }

    /// True if any DAW scans a path that doesn't overlap with system plugin dirs.
    static func hasExternalOnlyPaths() -> Bool {
        !externalScanPaths().isEmpty
    }

    /// Log a mismatch warning if DAWs are scanning external paths only.
    static func logMismatchWarning(to logger: Logger) async {
        let externals = externalScanPaths()
        guard !externals.isEmpty else { return }

        await logger.log("  ⚠️  PLUGIN PATH MISMATCH DETECTED")
        for p in externals {
            await logger.log("    \(p.daw) scans: \(p.path)")
        }
        await logger.log("    ATLAS installed to the system library, but the DAW(s) above")
        await logger.log("    may not find the plugin if they only scan external locations.")
        await logger.log("    💡 In your DAW settings, add /Library/Audio/Plug-Ins/ to the scan path,")
        await logger.log("       or move the installed plugin to match your DAW's scan folder.")
    }

    // MARK: - Per-DAW detection

    private static func logicPaths() -> [PluginScanPath] {
        // Logic Pro uses system AU locations only — no user-configurable scan path
        return []
    }

    private static func abletonPaths() -> [PluginScanPath] {
        // Ableton Live preferences: ~/Library/Preferences/Ableton/Live x.x.x/Options.txt
        // and the Plug-In Sources plist
        let home = NSHomeDirectory()
        let prefsDir = "\(home)/Library/Preferences/Ableton"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: prefsDir) else { return [] }

        var paths: [PluginScanPath] = []
        for entry in entries where entry.hasPrefix("Live") {
            let optionsPath = "\(prefsDir)/\(entry)/Options.txt"
            guard let contents = try? String(contentsOfFile: optionsPath, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                // -PlugInFolder:/Volumes/AudioDrive/Plugins
                if line.hasPrefix("-PlugInFolder:") {
                    let path = String(line.dropFirst(14))
                    paths.append(PluginScanPath(daw: "Ableton Live", path: path, isExternal: isExternal(path)))
                }
            }
        }
        return paths
    }

    private static func studioOnePaths() -> [PluginScanPath] {
        let plistPath = "\(NSHomeDirectory())/Library/Application Support/PreSonus/Studio One 6/Studio One.options"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let locations = plist["VST3Paths"] as? [String] else { return [] }
        return locations.map { PluginScanPath(daw: "Studio One", path: $0, isExternal: isExternal($0)) }
    }

    private static func cubasePaths() -> [PluginScanPath] {
        // Cubase stores plugin paths in VST2 Plugin Paths key in its plist
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/Library/Preferences/Cubase 13/cubase13.xml",
            "\(home)/Library/Preferences/Cubase 12/cubase12.xml",
        ]
        var paths: [PluginScanPath] = []
        for xmlPath in candidates {
            guard let contents = try? String(contentsOfFile: xmlPath, encoding: .utf8) else { continue }
            // Quick regex for <string value="/Volumes/...">
            let pattern = #"<string value="(/Volumes/[^"]+)""#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let nsStr = contents as NSString
                let matches = regex.matches(in: contents, range: NSRange(location: 0, length: nsStr.length))
                for m in matches {
                    let path = nsStr.substring(with: m.range(at: 1))
                    paths.append(PluginScanPath(daw: "Cubase", path: path, isExternal: true))
                }
            }
        }
        return paths
    }

    private static func bitwigPaths() -> [PluginScanPath] {
        let settingsPath = "\(NSHomeDirectory())/Library/Application Support/Bitwig Studio/settings.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pluginPaths = json["plugin-search-paths"] as? [String] else { return [] }
        return pluginPaths.map { PluginScanPath(daw: "Bitwig Studio", path: $0, isExternal: isExternal($0)) }
    }

    // MARK: - Helpers

    private static func isExternal(_ path: String) -> Bool {
        path.hasPrefix("/Volumes/")
    }
}
