import Foundation

// GatekeeperFixer — removes the com.apple.quarantine extended attribute from
// installed plugins/apps that macOS is blocking at runtime.
//
// When to use: after a DAW reports "plugin cannot be opened because the developer
// cannot be verified" — this is almost always a quarantine xattr issue, not a
// genuine security problem, for plugins installed via ATLAS.

struct GatekeeperFixer {

    struct FixResult {
        let fixed: [String]   // paths successfully fixed
        let failed: [String]  // paths that couldn't be fixed
    }

    // MARK: - Fix a specific path

    static func fix(path: String, adminPassword: String) -> Bool {
        let pwd = adminPassword.replacingOccurrences(of: "'", with: "'\\''")
        let r = shell("echo '\(pwd)' | sudo -S /usr/bin/xattr -dr com.apple.quarantine '\(esc(path))' 2>&1")
        return !r.lowercased().contains("error") && !r.lowercased().contains("not permitted")
    }

    // MARK: - Fix all blocked plugins in standard locations

    static func fixAllPluginLocations(adminPassword: String) async -> FixResult {
        let locations = [
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3",
            "/Library/Audio/Plug-Ins/VST",
            "/Library/Application Support/Avid/Audio/Plug-Ins",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/Components",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST3",
        ]

        var fixed: [String] = []
        var failed: [String] = []

        for location in locations {
            guard FileManager.default.fileExists(atPath: location) else { continue }
            let pluginExtensions = ["component", "vst3", "vst", "aaxplugin", "app"]

            guard let enumerator = FileManager.default.enumerator(atPath: location) else { continue }
            while let item = enumerator.nextObject() as? String {
                let ext = URL(fileURLWithPath: item).pathExtension.lowercased()
                guard pluginExtensions.contains(ext) else { continue }
                let fullPath = (location as NSString).appendingPathComponent(item)
                if hasQuarantine(path: fullPath) {
                    if fix(path: fullPath, adminPassword: adminPassword) {
                        fixed.append(item)
                    } else {
                        failed.append(item)
                    }
                }
            }
        }

        return FixResult(fixed: fixed, failed: failed)
    }

    // MARK: - Check if a path has quarantine

    static func hasQuarantine(path: String) -> Bool {
        let r = shell("/usr/bin/xattr -l '\(esc(path))' 2>/dev/null")
        return r.contains("com.apple.quarantine")
    }

    // MARK: - Scan and report blocked plugins (for history/settings view)

    static func findBlockedPlugins() -> [String] {
        let locations = [
            "/Library/Audio/Plug-Ins/Components",
            "/Library/Audio/Plug-Ins/VST3",
            "/Library/Audio/Plug-Ins/VST",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/Components",
            NSHomeDirectory() + "/Library/Audio/Plug-Ins/VST3",
        ]
        var blocked: [String] = []
        for location in locations {
            guard FileManager.default.fileExists(atPath: location),
                  let enumerator = FileManager.default.enumerator(atPath: location) else { continue }
            while let item = enumerator.nextObject() as? String {
                let ext = URL(fileURLWithPath: item).pathExtension.lowercased()
                guard ["component","vst3","vst","aaxplugin"].contains(ext) else { continue }
                let full = (location as NSString).appendingPathComponent(item)
                if hasQuarantine(path: full) { blocked.append(full) }
            }
        }
        return blocked
    }

    // MARK: - Helpers

    @discardableResult
    private static func shell(_ cmd: String) -> String {
        let p = Process()
        p.launchPath = "/bin/bash"; p.arguments = ["-c", cmd]
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }
}
