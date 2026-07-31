import Foundation

// WorkflowRecognizer evaluates a PackageManifest and selects the best-fitting
// installer workflow family. Recognition is driven entirely by package structure
// and instruction signals — it is independent of product identity.
//
// Products provide knowledge (hosts entries, known paths). Workflows provide
// the installation recipe. Neither owns the other.

// MARK: - WorkflowFamily

enum WorkflowFamily: String, CustomStringConvertible {

    // ── Named manager apps (high confidence — matched by bundle name) ────
    case wavesManager   = "waves_central"
    case nativeAccess   = "ni_native_access"
    case izotopePortal  = "izotope_portal"
    case arturia        = "arturia"
    case splice         = "splice"
    case ilok           = "ilok"
    case pluginAlliance = "plugin_alliance"
    case slateDigital   = "slate_digital"
    case soundtoys      = "soundtoys"
    case fabfilter      = "fabfilter"
    case installerWizard = "installer_wizard_auto"   // any unrecognised .app installer

    // ── Package structure families (inferred from file layout) ───────────
    case pkgOnly        = "simple_pkg"
    case pkgPlusPatch   = "pkg_plus_patch"
    case zipPluginDrop  = "zip_plugin_drop"
    case loosePluginDrop = "loose_plugin_drop"
    case dmgAppCopy     = "dmg_app_copy"
    case licensePatchOnly = "license_patch_only"
    case scriptBased    = "script_based"

    // ── Fallbacks ────────────────────────────────────────────────────────
    case unknownComplex  = "unknown_complex"
    case unknownSimple   = "unknown_simple"

    var description: String { rawValue }

    var displayName: String {
        switch self {
        case .wavesManager:    return "Waves Central"
        case .nativeAccess:    return "Native Instruments Native Access"
        case .izotopePortal:   return "iZotope Product Portal"
        case .arturia:         return "Arturia Software Center"
        case .splice:          return "Splice"
        case .ilok:            return "iLok License Manager"
        case .pluginAlliance:  return "Plugin Alliance"
        case .slateDigital:    return "Slate Digital"
        case .soundtoys:       return "Soundtoys"
        case .fabfilter:       return "FabFilter"
        case .installerWizard: return "Installer Wizard"
        case .pkgOnly:         return "Simple PKG"
        case .pkgPlusPatch:    return "PKG + Patch"
        case .zipPluginDrop:   return "ZIP Plugin Bundle"
        case .loosePluginDrop: return "Plugin Drop"
        case .dmgAppCopy:      return "Application Copy"
        case .licensePatchOnly: return "License Patch"
        case .scriptBased:     return "Script Installer"
        case .unknownComplex:  return "Unknown (complex)"
        case .unknownSimple:   return "Unknown"
        }
    }
}

// MARK: - WorkflowMatch

struct WorkflowMatch {
    let family:     WorkflowFamily
    let confidence: Confidence
    let source:     MatchSource

    enum Confidence: CustomStringConvertible {
        case high, medium, low
        var description: String {
            switch self { case .high: return "high"; case .medium: return "medium"; case .low: return "low" }
        }
    }

    enum MatchSource: CustomStringConvertible {
        case namedManager(appName: String)
        case instructionSignal(signal: String)
        case packageStructure
        case fallback

        var description: String {
            switch self {
            case .namedManager(let n):    return "namedManager(\(n))"
            case .instructionSignal(let s): return "instruction(\(s))"
            case .packageStructure:       return "packageStructure"
            case .fallback:               return "fallback"
            }
        }
    }
}

// MARK: - WorkflowRecognizer

struct WorkflowRecognizer {

    // Evaluates the manifest and returns the best workflow match.
    // Rules are evaluated in strict priority order — first match wins.
    static func recognize(manifest: PackageManifest) -> WorkflowMatch {

        // ── Priority 1: Named manager app present in the package ──────────
        // Identified from .app bundle names matched against the known family registry.
        if let managerKey = manifest.detectedManagerApp {
            if let family = familyFromKey(managerKey) {
                return WorkflowMatch(
                    family:     family,
                    confidence: .high,
                    source:     .namedManager(appName: managerKey)
                )
            }
            // Installer app present but not in the known family registry.
            // Fall through to packageStructure rules — the app may still matter.
        }

        // ── Priority 2: Instruction names a recognizable manager ──────────
        if let instr = manifest.instructions,
           instr.mentionsManagerApp,
           let hint = instr.appToLaunch {
            if let family = familyFromKey(hint.lowercased()) {
                return WorkflowMatch(
                    family:     family,
                    confidence: .medium,
                    source:     .instructionSignal(signal: hint)
                )
            }
        }

        // ── Priority 3: Package structure rules ───────────────────────────

        // PKG + patch binary → confirmed two-step workflow
        if manifest.hasPKG && manifest.hasPatchBinary {
            return WorkflowMatch(family: .pkgPlusPatch,    confidence: .high,   source: .packageStructure)
        }

        // PKG only (no manager app, no patch)
        if manifest.hasPKG && !manifest.hasInstallerApp {
            return WorkflowMatch(family: .pkgOnly,          confidence: .high,   source: .packageStructure)
        }

        // ZIP archive containing plugins
        if manifest.hasZipPlugins {
            return WorkflowMatch(family: .zipPluginDrop,    confidence: .high,   source: .packageStructure)
        }

        // Loose plugin bundles directly (no PKG, no ZIP wrapper)
        if manifest.hasLoosePlugins && !manifest.hasPKG {
            return WorkflowMatch(family: .loosePluginDrop,  confidence: .high,   source: .packageStructure)
        }

        // Unrecognised installer .app (instructions may hint at what it is)
        if manifest.hasInstallerApp {
            return WorkflowMatch(family: .installerWizard,  confidence: .medium, source: .packageStructure)
        }

        // Patch/license binary only, no PKG or installer
        if manifest.hasPatchBinary && !manifest.hasPKG {
            return WorkflowMatch(family: .licensePatchOnly, confidence: .medium, source: .packageStructure)
        }

        // Script-only package
        if manifest.hasScript {
            return WorkflowMatch(family: .scriptBased,      confidence: .low,    source: .packageStructure)
        }

        // Single plain .app — DMG-style drag-and-drop copy
        if manifest.hasPlainApp {
            return WorkflowMatch(family: .dmgAppCopy,       confidence: .high,   source: .packageStructure)
        }

        // ── Priority 4: Fallbacks ─────────────────────────────────────────
        if manifest.isComplex {
            return WorkflowMatch(family: .unknownComplex,   confidence: .low,    source: .fallback)
        }
        return     WorkflowMatch(family: .unknownSimple,    confidence: .low,    source: .fallback)
    }

    // MARK: - Private

    // Looks up a WorkflowFamily from a lowercased app-name key.
    // Tries both exact match and substring match against knownManagerFamilies keys.
    private static func familyFromKey(_ key: String) -> WorkflowFamily? {
        // Direct lookup
        if let raw = PackageManifest.knownManagerFamilies[key] {
            return WorkflowFamily(rawValue: raw)
        }
        // Substring match: does the key contain a known family pattern?
        for (pattern, raw) in PackageManifest.knownManagerFamilies {
            if key.contains(pattern) {
                return WorkflowFamily(rawValue: raw)
            }
        }
        return nil
    }
}
