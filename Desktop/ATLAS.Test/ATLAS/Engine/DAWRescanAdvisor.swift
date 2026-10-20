import Foundation
import AppKit

// DAWRescanAdvisor — detects which DAWs are running and knows how to trigger
// a plugin rescan in each one, either via menu automation or by instructing the user.

struct DAWRescanAdvisor {

    struct DAWInfo {
        let name: String            // display name
        let processNames: [String]  // NSRunningApplication localizedName variants
        let rescanInstructions: String
        let canAutoRescan: Bool     // if true, MacUIAutomator can trigger it
        let rescanMenuPath: [String] // menu path for auto-rescan (if canAutoRescan)
    }

    static let knownDAWs: [DAWInfo] = [
        DAWInfo(name: "Logic Pro",
                processNames: ["Logic Pro", "Logic Pro X"],
                rescanInstructions: "Logic Pro → Preferences → Plug-in Manager → Reset & Rescan Selection",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Ableton Live",
                processNames: ["Live", "Ableton Live"],
                rescanInstructions: "Live → Preferences → Plug-ins → Rescan",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Pro Tools",
                processNames: ["Pro Tools"],
                rescanInstructions: "Pro Tools → Preferences → Plug-ins → Scan AAX Plug-ins",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Cubase",
                processNames: ["Cubase", "Cubase Pro", "Cubase Artist"],
                rescanInstructions: "Cubase → Studio → VST Plug-in Manager → Rescan",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Studio One",
                processNames: ["Studio One"],
                rescanInstructions: "Studio One → Options → Locations → VST Plug-ins → [Rescan]",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "GarageBand",
                processNames: ["GarageBand"],
                rescanInstructions: "Quit and reopen GarageBand — it rescans automatically on launch",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "FL Studio",
                processNames: ["FL Studio"],
                rescanInstructions: "FL Studio → Options → Manage Plugins → Start scan",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Bitwig Studio",
                processNames: ["Bitwig Studio"],
                rescanInstructions: "Bitwig → Settings → Plug-ins → Rescan",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Reaper",
                processNames: ["REAPER"],
                rescanInstructions: "REAPER → Options → Preferences → Plug-ins → VST → Rescan",
                canAutoRescan: false,
                rescanMenuPath: []),
        DAWInfo(name: "Reason Studios",
                processNames: ["Reason", "Reason Studios"],
                rescanInstructions: "Quit and reopen Reason — it rescans plug-ins on launch",
                canAutoRescan: false,
                rescanMenuPath: []),
    ]

    // MARK: - Running DAW detection

    /// Returns the names of all known DAWs currently running.
    static func runningDAWs() -> [String] {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        return knownDAWs.filter { daw in
            daw.processNames.contains(where: { running.contains($0) })
        }.map { $0.name }
    }

    /// Returns full rescan instructions for all running DAWs.
    static func rescanInstructions() -> [(daw: String, instructions: String)] {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.localizedName }
        return knownDAWs.filter { daw in
            daw.processNames.contains(where: { running.contains($0) })
        }.map { ($0.name, $0.rescanInstructions) }
    }

    /// Log rescan instructions for all running DAWs.
    static func logRescanAdvice(to logger: Logger) async {
        let instructions = rescanInstructions()
        if instructions.isEmpty {
            await logger.log("  💡 Plugin installed. Open your DAW and rescan plugins to use it.")
        } else {
            await logger.log("  💡 Plugin installed. Rescan in your open DAW:")
            for (daw, instr) in instructions {
                await logger.log("    \(daw): \(instr)")
            }
        }
    }
}
