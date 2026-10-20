import Foundation

// Known minimum macOS requirements for common audio software.
// Used as a fallback when the installer itself doesn't declare OS requirements.
// Matched by lowercase keywords against the installer filename or folder name.

struct CompatibilityEntry {
    let keywords: [String]
    let minOS: String
    let productName: String
}

struct CompatibilityDatabase {

    static let entries: [CompatibilityEntry] = [
        // ── iZotope ──────────────────────────────────────────────────────────
        .init(keywords: ["ozone 12", "ozone12", "ozone_12"],           minOS: "13.0",   productName: "iZotope Ozone 12"),
        .init(keywords: ["ozone 11", "ozone11", "ozone_11"],           minOS: "10.15.7",productName: "iZotope Ozone 11"),
        .init(keywords: ["ozone 10", "ozone10", "ozone_10"],           minOS: "10.15.7",productName: "iZotope Ozone 10"),
        .init(keywords: ["rx 11", "rx11", "izotope rx 11", "rx11_"],   minOS: "11.0",   productName: "iZotope RX 11"),
        .init(keywords: ["rx 10", "rx10", "izotope rx 10"],            minOS: "10.15.7",productName: "iZotope RX 10"),
        .init(keywords: ["neutron 4", "neutron4"],                     minOS: "11.0",   productName: "iZotope Neutron 4"),
        .init(keywords: ["neutron 3", "neutron3"],                     minOS: "10.14.6",productName: "iZotope Neutron 3"),
        .init(keywords: ["neoverb"],                                   minOS: "10.15.7",productName: "iZotope Neoverb"),
        .init(keywords: ["breaktweaker"],                              minOS: "10.14.6",productName: "iZotope BreakTweaker"),
        .init(keywords: ["stutter edit"],                              minOS: "10.15.7",productName: "iZotope Stutter Edit 2"),
        .init(keywords: ["iris 2"],                                    minOS: "10.14.6",productName: "iZotope Iris 2"),
        .init(keywords: ["ddly"],                                      minOS: "10.14.6",productName: "iZotope DDLY"),
        .init(keywords: ["nectar 4", "nectar4"],                       minOS: "11.0",   productName: "iZotope Nectar 4"),
        .init(keywords: ["nectar 3", "nectar3"],                       minOS: "10.14.6",productName: "iZotope Nectar 3"),
        .init(keywords: ["insight 2", "insight2"],                     minOS: "10.14.6",productName: "iZotope Insight 2"),
        .init(keywords: ["dialogue match"],                            minOS: "10.15.7",productName: "iZotope Dialogue Match"),
        .init(keywords: ["spire studio"],                              minOS: "10.14.6",productName: "iZotope Spire Studio"),
        .init(keywords: ["music production suite"],                    minOS: "11.0",   productName: "iZotope Music Production Suite"),

        // ── Native Instruments ────────────────────────────────────────────
        .init(keywords: ["kontakt 8", "kontakt8", "kontakt_8"],        minOS: "11.0",   productName: "Native Instruments Kontakt 8"),
        .init(keywords: ["kontakt 7", "kontakt7", "kontakt_7"],        minOS: "10.15.7",productName: "Native Instruments Kontakt 7"),
        .init(keywords: ["kontakt 6", "kontakt6", "kontakt_6"],        minOS: "10.14.6",productName: "Native Instruments Kontakt 6"),
        .init(keywords: ["komplete 15", "komplete15", "komplete_15"],  minOS: "12.0",   productName: "NI Komplete 15"),
        .init(keywords: ["komplete 14", "komplete14", "komplete_14"],  minOS: "10.15.7",productName: "NI Komplete 14"),
        .init(keywords: ["komplete 13", "komplete13", "komplete_13"],  minOS: "10.14.6",productName: "NI Komplete 13"),
        .init(keywords: ["maschine 3", "maschine3", "maschine_3"],     minOS: "11.0",   productName: "Native Instruments Maschine 3"),
        .init(keywords: ["maschine 2"],                                minOS: "10.14.6",productName: "Native Instruments Maschine 2"),
        .init(keywords: ["native access"],                             minOS: "10.15.7",productName: "Native Access"),
        .init(keywords: ["battery 4", "battery4"],                     minOS: "10.14.6",productName: "NI Battery 4"),
        .init(keywords: ["massive x", "massivex"],                     minOS: "10.14.6",productName: "NI Massive X"),
        .init(keywords: ["form 1", "form_1"],                          minOS: "10.14.6",productName: "NI Form"),

        // ── Xfer Records ─────────────────────────────────────────────────
        .init(keywords: ["serum 2", "serum2", "serum_2", "serum_mac_2"],minOS: "11.0",  productName: "Serum 2"),
        .init(keywords: ["serum_mac", "serum mac"],                    minOS: "10.13.6",productName: "Serum"),
        .init(keywords: ["lfotool", "lfo tool"],                       minOS: "10.13.6",productName: "Xfer LFO Tool"),
        .init(keywords: ["nerve"],                                     minOS: "10.13.6",productName: "Xfer Nerve"),
        .init(keywords: ["cthulhu"],                                   minOS: "10.13.6",productName: "Xfer Cthulhu"),

        // ── Waves ──────────────────────────────────────────────────────────
        .init(keywords: ["waves 15", "waves15"],                       minOS: "12.0",   productName: "Waves 15"),
        .init(keywords: ["waves 14", "waves14"],                       minOS: "10.15.7",productName: "Waves 14"),
        .init(keywords: ["waves 13", "waves13"],                       minOS: "10.14.6",productName: "Waves 13"),
        .init(keywords: ["waves central"],                             minOS: "10.14.6",productName: "Waves Central"),

        // ── FabFilter ─────────────────────────────────────────────────────
        .init(keywords: ["pro-q 4", "pro_q_4", "proq4", "pro-q4"],    minOS: "11.0",   productName: "FabFilter Pro-Q 4"),
        .init(keywords: ["pro-q 3", "pro_q_3", "proq3"],              minOS: "10.14.6",productName: "FabFilter Pro-Q 3"),
        .init(keywords: ["pro-c 2", "pro_c_2", "proc2"],              minOS: "10.14.6",productName: "FabFilter Pro-C 2"),
        .init(keywords: ["pro-l 2", "pro_l_2", "prol2"],              minOS: "10.14.6",productName: "FabFilter Pro-L 2"),
        .init(keywords: ["pro-mb", "pro_mb", "promb"],                minOS: "10.14.6",productName: "FabFilter Pro-MB"),
        .init(keywords: ["pro-r 2", "pro_r_2"],                       minOS: "11.0",   productName: "FabFilter Pro-R 2"),
        .init(keywords: ["saturn 2", "saturn2"],                      minOS: "10.14.6",productName: "FabFilter Saturn 2"),
        .init(keywords: ["timeless 3", "timeless3"],                  minOS: "10.14.6",productName: "FabFilter Timeless 3"),
        .init(keywords: ["volcano 3", "volcano3"],                    minOS: "10.14.6",productName: "FabFilter Volcano 3"),

        // ── Arturia ───────────────────────────────────────────────────────
        .init(keywords: ["pigments 5", "pigments5", "pigments_5"],    minOS: "11.0",   productName: "Arturia Pigments 5"),
        .init(keywords: ["pigments 4", "pigments4"],                  minOS: "10.15.7",productName: "Arturia Pigments 4"),
        .init(keywords: ["v collection 10", "vcollection10"],         minOS: "11.0",   productName: "Arturia V Collection 10"),
        .init(keywords: ["v collection 9", "vcollection9"],           minOS: "11.0",   productName: "Arturia V Collection 9"),
        .init(keywords: ["analog lab v", "analoglab5"],               minOS: "10.15.7",productName: "Arturia Analog Lab V"),
        .init(keywords: ["mini v", "mini_v"],                         minOS: "10.15.7",productName: "Arturia Mini V3"),
        .init(keywords: ["beatstep"],                                  minOS: "10.14.6",productName: "Arturia BeatStep"),

        // ── Ableton ───────────────────────────────────────────────────────
        .init(keywords: ["ableton live 12", "live 12", "live12", "ablive12"], minOS: "11.0", productName: "Ableton Live 12"),
        .init(keywords: ["ableton live 11", "live 11", "live11", "ablive11"], minOS: "10.13.6",productName: "Ableton Live 11"),
        .init(keywords: ["ableton live 10", "live 10", "live10"],     minOS: "10.11.6",productName: "Ableton Live 10"),

        // ── Apple ─────────────────────────────────────────────────────────
        .init(keywords: ["logic pro"],                                 minOS: "14.0",   productName: "Logic Pro"),
        .init(keywords: ["final cut"],                                 minOS: "14.0",   productName: "Final Cut Pro"),
        .init(keywords: ["motion 5"],                                  minOS: "14.0",   productName: "Motion 5"),

        // ── Pro Tools / Avid ──────────────────────────────────────────────
        .init(keywords: ["pro tools 2024", "pro tools 2023"],         minOS: "12.6",   productName: "Pro Tools 2023/2024"),
        .init(keywords: ["pro tools 2022"],                           minOS: "12.6",   productName: "Pro Tools 2022"),
        .init(keywords: ["pro tools 2021", "pro tools 2020"],         minOS: "10.15.7",productName: "Pro Tools 2020/2021"),

        // ── Spectrasonics ─────────────────────────────────────────────────
        .init(keywords: ["omnisphere 3", "omnisphere3"],              minOS: "12.0",   productName: "Spectrasonics Omnisphere 3"),
        .init(keywords: ["omnisphere 2", "omnisphere2"],              minOS: "10.14.6",productName: "Spectrasonics Omnisphere 2"),
        .init(keywords: ["trilian"],                                  minOS: "10.14.6",productName: "Spectrasonics Trilian"),
        .init(keywords: ["stylus rmx", "stylusrmx"],                  minOS: "10.14.6",productName: "Spectrasonics Stylus RMX"),
        .init(keywords: ["keyscape"],                                  minOS: "10.14.6",productName: "Spectrasonics Keyscape"),

        // ── Soundtoys ────────────────────────────────────────────────────
        .init(keywords: ["soundtoys 5", "soundtoys5"],                minOS: "10.14.6",productName: "Soundtoys 5"),
        .init(keywords: ["echoboy"],                                  minOS: "10.14.6",productName: "Soundtoys EchoBoy"),
        .init(keywords: ["decapitator"],                              minOS: "10.14.6",productName: "Soundtoys Decapitator"),
        .init(keywords: ["little alter boy"],                         minOS: "10.14.6",productName: "Soundtoys Little AlterBoy"),

        // ── UAD / Universal Audio ─────────────────────────────────────────
        .init(keywords: ["uad software", "ua connect", "ua_connect"], minOS: "12.0",   productName: "Universal Audio Connect"),
        .init(keywords: ["luna recording"],                           minOS: "11.0",   productName: "Universal Audio LUNA"),

        // ── Slate Digital ────────────────────────────────────────────────
        .init(keywords: ["slate digital", "vms", "virtual mix rack", "vmr"], minOS: "10.14.6",productName: "Slate Digital"),
        .init(keywords: ["fresh air"],                                minOS: "10.14.6",productName: "Slate Fresh Air"),

        // ── Softube ──────────────────────────────────────────────────────
        .init(keywords: ["softube"],                                  minOS: "11.0",   productName: "Softube"),

        // ── Plugin Alliance / Brainworx ───────────────────────────────────
        .init(keywords: ["plugin alliance", "brainworx"],             minOS: "10.14.6",productName: "Plugin Alliance / Brainworx"),

        // ── Celemony ─────────────────────────────────────────────────────
        .init(keywords: ["melodyne 5", "melodyne5"],                  minOS: "10.15.7",productName: "Celemony Melodyne 5"),
        .init(keywords: ["melodyne 4", "melodyne4"],                  minOS: "10.13.6",productName: "Celemony Melodyne 4"),

        // ── Antares ──────────────────────────────────────────────────────
        .init(keywords: ["auto-tune pro x", "auto-tune prox"],        minOS: "11.0",   productName: "Antares Auto-Tune Pro X"),
        .init(keywords: ["auto-tune pro", "autotune pro"],            minOS: "10.15.7",productName: "Antares Auto-Tune Pro"),
        .init(keywords: ["harmony engine"],                           minOS: "10.15.7",productName: "Antares Harmony Engine"),

        // ── Apogee ───────────────────────────────────────────────────────
        .init(keywords: ["apogee symphony", "apogee control"],        minOS: "11.0",   productName: "Apogee"),
        .init(keywords: ["apogee maestro"],                           minOS: "10.14.6",productName: "Apogee Maestro"),
    ]

    // Returns (minOSString, productName) if filename matches a known entry.
    static func lookup(filename: String) -> (minOS: String, productName: String)? {
        let lower = filename.lowercased()
        for entry in entries {
            for keyword in entry.keywords where lower.contains(keyword) {
                return (entry.minOS, entry.productName)
            }
        }
        return nil
    }

    // Returns a human-readable macOS name for a major version number.
    static func macOSName(for major: Int) -> String {
        switch major {
        case 10: return "macOS Catalina or earlier"
        case 11: return "macOS Big Sur"
        case 12: return "macOS Monterey"
        case 13: return "macOS Ventura"
        case 14: return "macOS Sonoma"
        case 15: return "macOS Sequoia"
        default: return "macOS \(major)"
        }
    }

    // Compares a required version string "X.Y.Z" against the current OS.
    // Returns true if the current OS is below the requirement.
    static func isIncompatible(minOSString: String) -> Bool {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let parts = minOSString.split(separator: ".").compactMap { Int($0) }
        guard let reqMajor = parts.first else { return false }
        let reqMinor = parts.count > 1 ? parts[1] : 0
        let reqPatch = parts.count > 2 ? parts[2] : 0
        if reqMajor != current.majorVersion { return reqMajor > current.majorVersion }
        if reqMinor != current.minorVersion { return reqMinor > current.minorVersion }
        return reqPatch > current.patchVersion
    }

    // Formats a warning string for the scan result.
    static func incompatibilityWarning(productName: String, minOS: String) -> String {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let cur = "\(current.majorVersion).\(current.minorVersion)"
        let parts = minOS.split(separator: ".").compactMap { Int($0) }
        let reqMajor = parts.first ?? 0
        let osName = macOSName(for: reqMajor)
        return "⚠ \(productName) requires \(osName) (\(minOS)+) — your Mac runs macOS \(cur). This software may not install or launch correctly."
    }
}
