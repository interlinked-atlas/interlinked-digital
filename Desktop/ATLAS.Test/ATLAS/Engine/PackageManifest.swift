import Foundation

// PackageManifest is the unified view of a dropped package — its file contents,
// parsed instruction knowledge, and signals derived from both. It is the single
// input to the new workflow recognition and capability composition pipeline.
//
// Built by InstallIntelligence.buildManifest(). Runs alongside the existing
// analyze() path when Features.titanPipeline is enabled.

struct PackageManifest {

    // MARK: - Raw file classifications (from the files array + titanScan headers)

    let pkgs:          [URL]   // .pkg / .mpkg
    let installerApps: [URL]   // .app bundles identified as manager/installer tools
    let plainApps:     [URL]   // .app bundles that are plain applications
    let patchBinaries: [URL]   // Mach-O executables with a patch/crack signal in the name
    let otherBinaries: [URL]   // Mach-O executables with no patch signal
    let scripts:       [URL]   // shell scripts / .command files
    let pluginBundles: [URL]   // .vst3, .component, .aaxplugin, .vst
    let zipArchives:   [URL]   // .zip files that may contain plugin bundles

    // MARK: - First-class instruction knowledge

    // Instructions are a primary knowledge source — not an optional extra.
    // When present they influence ordering, hosts extraction, and capability selection.
    let instructions: ParsedInstructions?

    // MARK: - Merged signals (package structure + parsed instructions)

    let hostsEntries:       [String]   // domains to block — merged from scripts + instructions
    let needsXcodeTools:    Bool
    let detectedManagerApp: String?    // key from knownManagerFamilies when a named manager is present

    // MARK: - Convenience predicates

    var hasPKG:          Bool { !pkgs.isEmpty }
    var hasPatchBinary:  Bool { !patchBinaries.isEmpty }
    var hasLoosePlugins: Bool { !pluginBundles.isEmpty }
    var hasZipPlugins:   Bool { !zipArchives.isEmpty }
    var hasInstallerApp: Bool { !installerApps.isEmpty }
    var hasPlainApp:     Bool { !plainApps.isEmpty }
    var hasScript:       Bool { !scripts.isEmpty }
    var hasInstructions: Bool { instructions != nil }

    var isComplex: Bool {
        hasPatchBinary || hasScript || !hostsEntries.isEmpty || hasInstallerApp
    }

    // MARK: - Known manager family registry

    // Keys are lowercase substrings to match against app bundle names and instruction hints.
    // Values are WorkflowFamily raw values.
    static let knownManagerFamilies: [String: String] = [
        "waves central":             "waves_central",
        "wavecentral":               "waves_central",
        "native access":             "ni_native_access",
        "nativeaccess":              "ni_native_access",
        "izotope product portal":    "izotope_portal",
        "izotope":                   "izotope_portal",
        "izoland":                   "izotope_portal",
        "arturia software center":   "arturia",
        "arturiasoftwarecenter":     "arturia",
        "arturia":                   "arturia",
        "splice":                    "splice",
        "ilok license manager":      "ilok",
        "pace license support":      "ilok",
        "plugin alliance":           "plugin_alliance",
        "slate digital":             "slate_digital",
        "soundtoys":                 "soundtoys",
        "fabfilter":                 "fabfilter",
    ]
}

// MARK: - InstallIntelligence extension: buildManifest

extension InstallIntelligence {

    // Builds a PackageManifest from a package directory and its pre-enumerated file list.
    // Does not replace analyze() — called by the new pipeline when Features.titanPipeline is on.
    static func buildManifest(directory: String, files: [URL]) -> PackageManifest {

        // ── 1. Extension-based classification of the files array ──────────
        var pkgs:          [URL] = []
        var installerApps: [URL] = []
        var plainApps:     [URL] = []
        var pluginBundles: [URL] = []
        var zipArchives:   [URL] = []

        for url in files {
            let ext = url.pathExtension.lowercased()
            switch ext {
            case "pkg", "mpkg":
                pkgs.append(url)
            case "component", "vst3", "vst", "aaxplugin":
                pluginBundles.append(url)
            case "zip":
                zipArchives.append(url)
            case "app":
                if isManagerApp(url: url) {
                    installerApps.append(url)
                } else {
                    plainApps.append(url)
                }
            default:
                break
            }
        }

        // ── 2. Header-based scan for scripts and binaries ─────────────────
        // titanScan() reads magic bytes to find Mach-O executables and shell scripts
        // that have no file extension (common in pirated software packages).
        let scan = titanScan(directory: directory)

        let patchBinaries = scan.binaries.filter { isPatch(name: $0.lastPathComponent.lowercased()) }
        let otherBinaries = scan.binaries.filter { !isPatch(name: $0.lastPathComponent.lowercased()) }

        // ── 3. Instruction file (first-class knowledge source) ────────────
        let instructions = findAndParseInstructions(in: directory)

        // ── 4. Merge hosts entries from all sources ────────────────────────
        let instrHosts = instructions?.hostsEntries ?? []
        let scanHosts  = scan.hostsEntries
        let hostsEntries = Array(Set(instrHosts + scanHosts))

        // ── 5. Detect named manager app ────────────────────────────────────
        // First: check actual app bundle names against the known family registry.
        let detectedManagerApp: String? = {
            for appURL in installerApps {
                let appName = appURL.deletingPathExtension().lastPathComponent.lowercased()
                for key in PackageManifest.knownManagerFamilies.keys {
                    if appName.contains(key) { return key }
                }
            }
            // Second: check instruction-mentioned app name.
            if let hint = instructions?.appToLaunch?.lowercased() {
                for key in PackageManifest.knownManagerFamilies.keys {
                    if hint.contains(key) || key.contains(hint) { return key }
                }
            }
            // Third: check instruction text for manager app mentions.
            if instructions?.mentionsManagerApp == true,
               let appHint = instructions?.appToLaunch {
                return appHint.lowercased()
            }
            return nil
        }()

        let needsXcodeTools = scan.needsXcodeTools || (instructions?.mentionsXcodeTools == true)

        return PackageManifest(
            pkgs:             pkgs,
            installerApps:    installerApps,
            plainApps:        plainApps,
            patchBinaries:    patchBinaries,
            otherBinaries:    otherBinaries,
            scripts:          scan.scripts,
            pluginBundles:    pluginBundles,
            zipArchives:      zipArchives,
            instructions:     instructions,
            hostsEntries:     hostsEntries,
            needsXcodeTools:  needsXcodeTools,
            detectedManagerApp: detectedManagerApp
        )
    }
}
