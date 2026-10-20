import Foundation

// Result of DAW gate evaluation
enum DAWGateResult {
    case allowed
    case blocked(dawName: String)
}

// Isolated admission gate for full DAW installations.
// Evaluates a candidate .app bundle — or a list of candidates from a container —
// against an explicit allowlist and blocklist. Everything else is ALLOWED.
// Plugin bundles (.vst3, .component, .aaxplugin, .vst) never reach this gate.
struct DAWInstallationGate {

    // MARK: — Allowlist (evaluated first; match → always ALLOWED)

    // Note: allowlist bundle IDs are high-confidence (Apple + Adobe own products).
    private static let allowedBundleIDPrefixes: [String] = [
        "com.apple.logic10",      // Logic Pro (all versions)
        "com.apple.garageband10", // GarageBand (all versions)
        "com.adobe.audition",     // Adobe Audition (all versions)
    ]

    private static let allowedNormalizedNames: [String] = [
        "logic pro",
        "garageband",
        "adobe audition",
    ]

    // MARK: — Block table

    // Each entry: (bundleIDPrefixes, normalizedProductNames, friendlyDisplayName)
    // Bundle ID prefix matching catches all versioned identifiers (e.g. com.steinberg.cubase14).
    // Normalized name matching is a conservative fallback when bundle ID is unavailable.
    //
    // IMPORTANT: bundle IDs marked [unverified] were not confirmed against local installs.
    // They are best-known values from public macOS developer documentation and reports.
    // Update the table once any of these DAWs can be verified against an actual install.

    private struct DAWEntry {
        let bundleIDPrefixes: [String]
        let normalizedNames: [String]
        let displayName: String
    }

    private static let blockedDAWs: [DAWEntry] = [
        DAWEntry(
            bundleIDPrefixes: [
                "com.ableton.live",         // [high confidence — widely documented]
            ],
            normalizedNames: ["ableton live"],
            displayName: "Ableton Live"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.avid.ProTools",        // [unverified — mixed-case uncertain]
                "com.avid.protools",        // [unverified — lowercase variant]
            ],
            normalizedNames: ["pro tools"],
            displayName: "Pro Tools"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.image-line.flstudio",  // [unverified]
                "com.image-line.FLStudio",  // [unverified — mixed-case variant]
            ],
            normalizedNames: ["fl studio"],
            displayName: "FL Studio"
        ),
        DAWEntry(
            // Steinberg appends version number: com.steinberg.cubase13, cubase14, etc.
            // Prefix "com.steinberg.cubase" catches all versions without catching
            // unrelated Steinberg products (WaveLab = com.steinberg.wavelab, etc.).
            bundleIDPrefixes: [
                "com.steinberg.cubase",     // [unverified — prefix covers all versions]
            ],
            normalizedNames: ["cubase"],
            displayName: "Cubase"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.steinberg.nuendo",     // [unverified — prefix covers all versions]
            ],
            normalizedNames: ["nuendo"],
            displayName: "Nuendo"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.presonus.StudioOne",   // [unverified — mixed-case]
                "com.presonus.studioone",   // [unverified — lowercase variant]
            ],
            normalizedNames: ["studio one"],
            displayName: "Studio One"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.bitwig.studio",        // [unverified — variant 1]
                "com.bitwig.BitwigStudio",  // [unverified — variant 2]
            ],
            normalizedNames: ["bitwig studio"],
            displayName: "Bitwig Studio"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.cockos.reaper",        // [high confidence — widely documented]
            ],
            normalizedNames: ["reaper"],
            displayName: "REAPER"
        ),
        DAWEntry(
            // Reason Studios rebranded from Propellerhead; include both identifiers.
            bundleIDPrefixes: [
                "com.reasonstudios.Reason", // [unverified — post-rebrand]
                "com.reasonstudios.reason", // [unverified — lowercase variant]
                "com.propellerheads.reason",// [unverified — legacy pre-rebrand]
            ],
            normalizedNames: ["reason"],
            displayName: "Reason"
        ),
        DAWEntry(
            bundleIDPrefixes: [
                "com.uaudio.luna",          // [unverified]
            ],
            normalizedNames: ["luna"],
            displayName: "LUNA"
        ),
        DAWEntry(
            // Cakewalk/SONAR is currently Windows-only.
            // No Mac bundle ID to verify; name fallback kept for future-proofing.
            bundleIDPrefixes: [],
            normalizedNames: ["cakewalk", "sonar"],
            displayName: "Cakewalk"
        ),
    ]

    // MARK: — Public interface

    // Evaluate a single .app bundle URL.
    // Reads Info.plist directly — no process launch, no side effects.
    static func check(appURL: URL) -> DAWGateResult {
        guard appURL.pathExtension.lowercased() == "app" else { return .allowed }

        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plist: [String: Any]
        if let data = try? Data(contentsOf: plistURL),
           let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            plist = parsed
        } else {
            plist = [:]
        }

        let bundleID    = plist["CFBundleIdentifier"] as? String ?? ""
        let rawName     = (plist["CFBundleDisplayName"] as? String)
                       ?? (plist["CFBundleName"] as? String)
                       ?? appURL.deletingPathExtension().lastPathComponent
        let normalizedN = normalized(rawName)

        // 1. Allowlist — first priority
        for prefix in allowedBundleIDPrefixes {
            if !bundleID.isEmpty && bundleID.hasPrefix(prefix) { return .allowed }
        }
        for name in allowedNormalizedNames {
            if isIdentityMatch(normalizedN, canonical: name) { return .allowed }
        }

        // 2. Blocklist
        for daw in blockedDAWs {
            for prefix in daw.bundleIDPrefixes {
                if !bundleID.isEmpty && bundleID.hasPrefix(prefix) {
                    return .blocked(dawName: daw.displayName)
                }
            }
            for name in daw.normalizedNames {
                if isIdentityMatch(normalizedN, canonical: name) {
                    return .blocked(dawName: daw.displayName)
                }
            }
        }

        // 3. Unknown — allow
        return .allowed
    }

    // Evaluate a list of candidate .app URLs (used for containers: DMG, ZIP).
    // Returns .blocked on the first match; .allowed if none match.
    static func checkCandidates(_ appURLs: [URL]) -> DAWGateResult {
        for appURL in appURLs {
            let result = check(appURL: appURL)
            if case .blocked = result { return result }
        }
        return .allowed
    }

    // Conservative PKG check using normalized filename only.
    // Does NOT run pkgutil or any external process.
    // Biases toward ALLOW when the product identity is ambiguous.
    static func checkPKG(url: URL) -> DAWGateResult {
        let filename      = url.deletingPathExtension().lastPathComponent
        let normalizedN   = normalized(filename)

        // Allowlist first
        for name in allowedNormalizedNames {
            if isIdentityMatch(normalizedN, canonical: name) { return .allowed }
        }

        // Blocklist
        for daw in blockedDAWs {
            for name in daw.normalizedNames {
                if isIdentityMatch(normalizedN, canonical: name) {
                    return .blocked(dawName: daw.displayName)
                }
            }
        }

        return .allowed
    }

    // MARK: — Helpers

    // Lowercase the input. (Version/edition suffix handling is done inside isIdentityMatch.)
    private static func normalized(_ name: String) -> String {
        name.lowercased()
    }

    // Edition/version words that may appear after a DAW product name
    private static let editionTokens: Set<String> = [
        "pro", "artist", "elements", "suite", "intro", "standard",
        "professional", "ultimate", "lite", "education", "academic",
        "trial", "express", "edition", "recording",
    ]

    // Returns true only if normalizedName:
    //   (a) exactly equals canonical, OR
    //   (b) starts with canonical followed by a space, where every remaining
    //       token is a version number or a known edition word.
    //
    // This prevents "ableton echo" matching "ableton live" and
    // "cubase compatible reverb" matching "cubase".
    private static func isIdentityMatch(_ normalizedName: String, canonical: String) -> Bool {
        if normalizedName == canonical { return true }
        guard normalizedName.hasPrefix(canonical + " ") else { return false }
        let suffix = String(normalizedName.dropFirst(canonical.count + 1))
        let tokens = suffix.split(separator: " ").map(String.init)
        return tokens.allSatisfy { token in
            editionTokens.contains(token)
                || token.first?.isNumber == true
                || (token.first == "v" && token.dropFirst().first?.isNumber == true)
        }
    }
}
