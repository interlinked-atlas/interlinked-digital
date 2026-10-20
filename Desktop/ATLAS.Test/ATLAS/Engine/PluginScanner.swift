import Foundation

// MARK: - Data types

struct InstalledDAW: Identifiable {
    let id = UUID()
    let name: String
    let formats: Set<String>   // "component", "vst3", "vst", "aaxplugin"
}

struct PluginCheckResult: Identifiable {
    let id = UUID()
    let pluginName: String
    let format: String
    let installedPath: String
    let isPresent: Bool          // file actually on disk
    let compatibleDAWs: [String] // DAW names that support this format and are installed
}

// MARK: - Scanner

struct PluginScanner {

    // Standard install locations per format
    static let pluginDirs: [String: [String]] = [
        "component": [
            "/Library/Audio/Plug-Ins/Components",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/Components",
        ],
        "vst3": [
            "/Library/Audio/Plug-Ins/VST3",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST3",
        ],
        "vst": [
            "/Library/Audio/Plug-Ins/VST",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST",
        ],
        "aaxplugin": [
            "/Library/Application Support/Avid/Audio/Plug-Ins",
        ],
    ]

    // Run after a successful install; returns results only for plugin formats.
    static func scan(installedFiles: [InstallRecord.InstalledFile]) -> [PluginCheckResult] {
        let daws = detectInstalledDAWs()
        var results: [PluginCheckResult] = []

        for file in installedFiles {
            let url = URL(fileURLWithPath: file.destinationPath)
            let ext = url.pathExtension.lowercased()
            guard pluginDirs.keys.contains(ext) else { continue }

            let isPresent = FileManager.default.fileExists(atPath: file.destinationPath)
            let compat    = daws.filter { $0.formats.contains(ext) }.map { $0.name }

            results.append(PluginCheckResult(
                pluginName:     url.deletingPathExtension().lastPathComponent,
                format:         ext,
                installedPath:  file.destinationPath,
                isPresent:      isPresent,
                compatibleDAWs: compat
            ))
        }

        return results.sorted { $0.format < $1.format }
    }

    static func detectInstalledDAWs() -> [InstalledDAW] {
        let definitions: [(name: String, prefixes: [String], formats: Set<String>)] = [
            ("Logic Pro",          ["Logic Pro.app", "Logic Pro X.app"],   ["component", "vst3"]),
            ("GarageBand",         ["GarageBand.app"],                      ["component"]),
            ("Pro Tools",          ["Pro Tools.app"],                       ["component", "vst3", "aaxplugin"]),
            ("Ableton Live",       ["Ableton Live"],                        ["vst3", "vst", "component"]),
            ("Cubase",             ["Cubase"],                              ["vst3", "vst", "component"]),
            ("Nuendo",             ["Nuendo"],                              ["vst3", "vst", "component"]),
            ("Reaper",             ["REAPER.app"],                          ["vst3", "vst", "component"]),
            ("Studio One",         ["Studio One"],                          ["vst3", "vst", "component"]),
            ("FL Studio",          ["FL Studio"],                           ["vst3", "vst"]),
            ("Bitwig Studio",      ["Bitwig Studio.app"],                   ["vst3", "component"]),
            ("Digital Performer",  ["Digital Performer.app"],               ["component", "vst"]),
            ("Reason Studios",     ["Reason.app"],                          ["vst3"]),
        ]

        let fm = FileManager.default
        let appDir = "/Applications"
        let contents = (try? fm.contentsOfDirectory(atPath: appDir)) ?? []

        return definitions.compactMap { def -> InstalledDAW? in
            for prefix in def.prefixes {
                // Exact match
                if fm.fileExists(atPath: "\(appDir)/\(prefix)") {
                    return InstalledDAW(name: def.name, formats: def.formats)
                }
                // Prefix match (e.g. "Ableton Live 11 Suite.app")
                if !prefix.hasSuffix(".app") &&
                   contents.contains(where: { $0.hasPrefix(prefix) }) {
                    return InstalledDAW(name: def.name, formats: def.formats)
                }
            }
            return nil
        }
    }

    // Human-readable label for a plugin format
    static func formatLabel(_ ext: String) -> String {
        switch ext {
        case "component": return "Audio Unit"
        case "vst3":      return "VST3"
        case "vst":       return "VST"
        case "aaxplugin": return "AAX"
        default:          return ext.uppercased()
        }
    }
}
