import Foundation
import AppKit

// LicenseManagerDetector — knows about the major third-party license managers
// used by pro audio software and can detect whether they are installed,
// running, or needed for a product that just failed activation.

struct LicenseManager {
    let name: String
    let description: String
    let appBundleIDs: [String]
    let appPaths: [String]
    let downloadURL: String
    let hint: String   // shown in ATLAS log after demo-mode detection
}

struct LicenseManagerDetector {

    static let knownManagers: [LicenseManager] = [
        LicenseManager(
            name: "iLok License Manager",
            description: "Pace iLok — used by Waves, Plugin Alliance, Soundtoys, many others",
            appBundleIDs: ["com.pace.iLokLicenseManager", "com.pace.ilok-license-manager"],
            appPaths: ["/Applications/iLok License Manager.app", "/Applications/Pace/iLok License Manager.app"],
            downloadURL: "https://www.ilok.com/ilm.html",
            hint: "This product uses iLok licensing. Open iLok License Manager and activate your license."
        ),
        LicenseManager(
            name: "eLicenser Control Center",
            description: "Steinberg eLicenser — used by Cubase, Nuendo, HALion, many older Steinberg products",
            appBundleIDs: ["com.steinberg.elicenser", "com.syncrosoft.LCC"],
            appPaths: ["/Applications/eLicenser Control Center.app",
                       "/Applications/Steinberg/eLicenser Control Center.app"],
            downloadURL: "https://www.steinberg.net/elicenser/",
            hint: "This product uses the Steinberg eLicenser. Open eLicenser Control Center and enter your activation code."
        ),
        LicenseManager(
            name: "Native Access",
            description: "Native Instruments Native Access — required for NI products",
            appBundleIDs: ["com.native-instruments.NativeAccess"],
            appPaths: ["/Applications/Native Access.app"],
            downloadURL: "https://www.native-instruments.com/en/specials/native-access/",
            hint: "This is a Native Instruments product. Open Native Access to complete installation and activation."
        ),
        LicenseManager(
            name: "Splice",
            description: "Splice desktop app — used for Splice Sounds and some plugin licenses",
            appBundleIDs: ["com.splice.desktop"],
            appPaths: ["/Applications/Splice.app"],
            downloadURL: "https://splice.com/features/desktop",
            hint: "This product may require activation through the Splice desktop app."
        ),
        LicenseManager(
            name: "Plugin Alliance Connect",
            description: "Plugin Alliance activation app",
            appBundleIDs: ["com.plugin-alliance.Connect"],
            appPaths: ["/Applications/Plugin Alliance Connect.app"],
            downloadURL: "https://www.plugin-alliance.com/en/downloads.html",
            hint: "This Plugin Alliance product requires activation through Plugin Alliance Connect."
        ),
        LicenseManager(
            name: "Waves Central",
            description: "Waves licensing and update manager",
            appBundleIDs: ["com.waves.wavesCentral"],
            appPaths: ["/Applications/Waves Central.app",
                       "/Applications/Waves/Waves Central.app"],
            downloadURL: "https://www.waves.com/downloads/waves-central",
            hint: "Waves products are licensed through Waves Central. Open it to activate your license."
        ),
        LicenseManager(
            name: "PACE License Support",
            description: "PACE anti-piracy / license support service",
            appBundleIDs: ["com.pace.InterLokEngine"],
            appPaths: ["/Library/LaunchAgents/com.pace.iLokAgent.plist"],
            downloadURL: "https://www.ilok.com",
            hint: "PACE license service is required. Install iLok License Manager to activate this product."
        ),
    ]

    // MARK: - Detection

    /// Check which license managers are installed on this Mac.
    static func installedManagers() -> [LicenseManager] {
        knownManagers.filter { mgr in
            mgr.appPaths.contains { FileManager.default.fileExists(atPath: $0) }
        }
    }

    /// Check which license managers are currently running.
    static func runningManagers() -> [LicenseManager] {
        let runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        return knownManagers.filter { mgr in
            mgr.appBundleIDs.contains(where: { runningBundleIDs.contains($0) })
        }
    }

    /// Given demo-mode keywords found by TITAN VERIFY, guess which license manager is needed.
    static func suggestManager(for demoKeywords: [String]) -> LicenseManager? {
        let combined = demoKeywords.joined(separator: " ").lowercased()
        if combined.contains("ilok") || combined.contains("pace") { return knownManagers[0] }
        if combined.contains("elicenser") || combined.contains("steinberg") { return knownManagers[1] }
        if combined.contains("native") || combined.contains("ni ") { return knownManagers[2] }
        if combined.contains("splice") { return knownManagers[3] }
        if combined.contains("plugin alliance") { return knownManagers[4] }
        if combined.contains("waves") { return knownManagers[5] }
        return nil
    }

    /// Log a helpful licensing hint based on what was found.
    static func logHints(for demoKeywords: [String], to logger: Logger) async {
        if let mgr = suggestManager(for: demoKeywords) {
            let installed = mgr.appPaths.contains { FileManager.default.fileExists(atPath: $0) }
            await logger.log("  🔑 License Manager Required: \(mgr.name)")
            await logger.log("    \(mgr.hint)")
            if !installed {
                await logger.log("    ↓ Not installed — download: \(mgr.downloadURL)")
            } else {
                await logger.log("    ✓ \(mgr.name) is installed — open it to activate")
            }
        } else {
            await logger.log("  🔑 This product requires license activation before use.")
            await logger.log("    Check the product's website for activation instructions.")
        }
    }
}
