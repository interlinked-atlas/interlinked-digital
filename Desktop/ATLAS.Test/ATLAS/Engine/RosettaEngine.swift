import Foundation
import AppKit

// RosettaEngine detects Apple Silicon, checks Rosetta status,
// scans for installed DAWs, and enables Rosetta mode per-app.
//
// "Open using Rosetta" works by setting the x86_64 preference
// via xattr on the .app bundle — identical to the Finder checkbox.

struct DAWInfo: Identifiable {
    let id = UUID()
    let name: String
    let bundlePath: String
    var isRosettaEnabled: Bool
    let icon: String // SF Symbol
}

struct RosettaEngine {

    // MARK: - Architecture Detection

    static var isAppleSilicon: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { ptr in
            String(cString: ptr.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return machine.contains("arm")
    }

    // MARK: - Rosetta Installation Check

    static var isRosettaInstalled: Bool {
        FileManager.default.fileExists(
            atPath: "/Library/Apple/usr/share/rosetta/rosetta")
    }

    static func installRosetta(logger: Logger) async -> Bool {
        await logger.log("Installing Rosetta 2...")
        let result = runProcess(
            path: "/usr/sbin/softwareupdate",
            arguments: ["--install-rosetta", "--agree-to-license"]
        )
        if result.success {
            await logger.log("✓ Rosetta 2 installed")
        } else {
            await logger.log("✗ Rosetta installation failed: \(result.output)")
        }
        return result.success
    }

    // MARK: - DAW Discovery

    // Known DAW bundle identifiers and their common names
    private static let knownDAWs: [(name: String, bundleIDs: [String], icon: String)] = [
        ("Ableton Live",    ["com.ableton.live", "com.ableton.live-suite",
                            "com.ableton.live-standard", "com.ableton.live-intro"], "waveform"),
        ("Logic Pro",       ["com.apple.logic10"], "music.note"),
        ("Pro Tools",       ["com.avid.ProTools"], "slider.horizontal.3"),
        ("FL Studio",       ["com.image-line.flstudio", "com.image-line.FL-Studio-20"], "waveform.circle"),
        ("Studio One",      ["com.presonus.StudioOne", "com.presonus.studioone5",
                            "com.presonus.studioone6"], "music.quarternote.3"),
        ("Cubase",          ["com.steinberg.cubase12", "com.steinberg.cubase11",
                            "com.steinberg.cubase13", "com.steinberg.cubase"], "pianokeys"),
        ("Nuendo",          ["com.steinberg.nuendo12", "com.steinberg.nuendo"], "pianokeys.inverse"),
        ("Reaper",          ["com.cockos.reaper"], "waveform.badge.plus"),
        ("GarageBand",      ["com.apple.garageband10"], "guitars"),
        ("Bitwig Studio",   ["com.bitwig.BitwigStudio"], "rectangle.3.group"),
        ("Reason",          ["com.reasonstudios.reason", "com.propellerheads.reason"], "waveform.badge.magnifyingglass"),
        ("Digital Performer",["com.motu.DigitalPerformer"], "music.note.list"),
        ("Audacity",        ["org.audacityteam.audacity"], "waveform"),
        ("Fender Tone",     ["com.fender.FenderTone"], "guitars"),
        ("Mixcraft",        ["com.acoustica.mixcraft"], "music.note"),
    ]

    // Search locations for DAW apps
    private static let searchLocations = [
        "/Applications",
        NSHomeDirectory() + "/Applications",
        "/Applications/Music Production",
        "/Applications/Audio",
    ]

    static func scanForDAWs() -> [DAWInfo] {
        var found: [DAWInfo] = []
        let fm = FileManager.default
        let workspace = NSWorkspace.shared

        for (name, bundleIDs, icon) in knownDAWs {
            // Try finding via NSWorkspace (most reliable)
            for bundleID in bundleIDs {
                if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) {
                    let rosettaEnabled = checkRosettaEnabled(appPath: url.path)
                    found.append(DAWInfo(
                        name: name,
                        bundlePath: url.path,
                        isRosettaEnabled: rosettaEnabled,
                        icon: icon
                    ))
                    break
                }
            }
        }

        // Also scan search locations for any .app we might have missed
        for location in searchLocations {
            guard let contents = try? fm.contentsOfDirectory(atPath: location) else { continue }
            for item in contents where item.hasSuffix(".app") {
                let fullPath = "\(location)/\(item)"
                // Check if this matches any known DAW name
                for (name, _, icon) in knownDAWs {
                    if item.lowercased().contains(name.lowercased().components(separatedBy: " ").first ?? "") {
                        // Only add if not already found
                        if !found.contains(where: { $0.bundlePath == fullPath }) {
                            let rosettaEnabled = checkRosettaEnabled(appPath: fullPath)
                            found.append(DAWInfo(
                                name: name,
                                bundlePath: fullPath,
                                isRosettaEnabled: rosettaEnabled,
                                icon: icon
                            ))
                        }
                    }
                }
            }
        }

        return found.sorted { $0.name < $1.name }
    }

    // MARK: - Rosetta Toggle

    // Check if a DAW is already set to open with Rosetta
    static func checkRosettaEnabled(appPath: String) -> Bool {
        let result = runProcess(
            path: "/usr/bin/xattr",
            arguments: ["-p", "com.apple.LaunchServices.OpenWith.arch", appPath]
        )
        return result.output.contains("x86_64")
    }

    // Enable Rosetta for a specific DAW
    static func enableRosetta(
        appPath: String,
        password: String,
        logger: Logger
    ) async -> Bool {
        let appName = URL(fileURLWithPath: appPath).lastPathComponent
        await logger.log("Enabling Rosetta for \(appName)...")

        // Set arch preference to x86_64 (same as Finder "Open using Rosetta")
        let result = runWithPassword(
            password: password,
            arguments: ["/usr/bin/xattr", "-w",
                       "com.apple.LaunchServices.OpenWith.arch",
                       "x86_64", appPath]
        )

        if result.success {
            await logger.log("✓ \(appName) set to open with Rosetta")
            return true
        } else {
            await logger.log("✗ Could not enable Rosetta for \(appName): \(result.output)")
            return false
        }
    }

    // Disable Rosetta for a specific DAW (restore native)
    static func disableRosetta(
        appPath: String,
        password: String,
        logger: Logger
    ) async -> Bool {
        let appName = URL(fileURLWithPath: appPath).lastPathComponent
        await logger.log("Restoring native mode for \(appName)...")

        let result = runWithPassword(
            password: password,
            arguments: ["/usr/bin/xattr", "-d",
                       "com.apple.LaunchServices.OpenWith.arch", appPath]
        )

        if result.success {
            await logger.log("✓ \(appName) restored to native Apple Silicon mode")
            return true
        } else {
            await logger.log("✗ Could not restore native mode: \(result.output)")
            return false
        }
    }

    // MARK: - Process Helpers

    private static func runWithPassword(
        password: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S"] + arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write((password + "\n").data(using: .utf8)!)
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let out = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: out, encoding: .utf8) ?? "")
    }

    private static func runProcess(
        path: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}
