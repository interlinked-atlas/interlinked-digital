import Foundation

// Capabilities are the reusable building blocks of installation workflows.
// Each capability is stateless: given a PackageManifest and optional ProductMatch
// it returns the InstallSteps it contributes. No execution, no side effects.
//
// New installer families are assembled from existing capabilities.
// New capabilities are only added when a genuinely new installation primitive
// is needed — not when a new product is encountered.

// MARK: - ProductMatch

// Carries product-specific knowledge from TITAN MEMORY™ or ATLASLearn™.
// Flows into capabilities as an optional override source.
struct ProductMatch {
    let canonicalName: String
    let hostsEntries:  [String]   // product-specific activation-block domains
    let knownPaths:    [String]   // known install locations for verification
    let source:        Source

    enum Source {
        case titanMemory
        case atlasLearn(successCount: Int)
    }
}

// MARK: - Capability protocol

protocol InstallCapability {
    // Returns true when this capability has work to do for this package.
    func canApply(to manifest: PackageManifest) -> Bool
    // Produces the InstallSteps this capability contributes.
    // Returns [] when canApply is false — callers may skip the check for brevity.
    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep]
}

// MARK: - RunPKGCapability

struct RunPKGCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasPKG }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        let sorted = sortedByInstructionOrder(manifest.pkgs, instructions: manifest.instructions)
        return sorted.enumerated().map { idx, url in
            InstallStep(url: url, type: .installer, order: 1 + idx, note: "Package installer")
        }
    }
}

// MARK: - RunPatchCapability

struct RunPatchCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasPatchBinary }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        let sorted = sortedByInstructionOrder(manifest.patchBinaries, instructions: manifest.instructions)
        return sorted.enumerated().map { idx, url in
            InstallStep(url: url, type: .patch, order: 100 + idx,
                        note: "Patch — applied after main installer")
        }
    }
}

// MARK: - RunScriptCapability

struct RunScriptCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasScript }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        let sorted = sortedByInstructionOrder(manifest.scripts, instructions: manifest.instructions)
        return sorted.enumerated().map { idx, url in
            InstallStep(url: url, type: .patch, order: 100 + idx,
                        note: "Script — runs per installation instructions")
        }
    }
}

// MARK: - CopyLoosePluginsCapability

struct CopyLoosePluginsCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasLoosePlugins }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        return manifest.pluginBundles.enumerated().map { idx, url in
            InstallStep(url: url, type: .plugin, order: 10 + idx, note: "Audio plugin")
        }
    }
}

// MARK: - ExtractZIPPluginsCapability

struct ExtractZIPPluginsCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasZipPlugins }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        return manifest.zipArchives.enumerated().map { idx, url in
            InstallStep(url: url, type: .plugin, order: 10 + idx, note: "Plugin bundle archive")
        }
    }
}

// MARK: - CopyAppCapability

struct CopyAppCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasPlainApp }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        return manifest.plainApps.enumerated().map { idx, url in
            InstallStep(url: url, type: .app, order: 10 + idx, note: "Application")
        }
    }
}

// MARK: - LaunchManagerAppCapability

struct LaunchManagerAppCapability: InstallCapability {
    // Preferred app name substring (lowercased). nil = use first available installer app.
    let appHint: String?

    func canApply(to manifest: PackageManifest) -> Bool { manifest.hasInstallerApp }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] {
        let candidates = manifest.installerApps

        let chosen: URL
        if let hint = appHint?.lowercased(),
           let match = candidates.first(where: {
               $0.deletingPathExtension().lastPathComponent.lowercased().contains(hint)
           }) {
            chosen = match
        } else {
            guard let first = candidates.first else { return [] }
            chosen = first
        }

        return [InstallStep(url: chosen, type: .managedInstall, order: 5,
                            note: "Manager installer — ATLAS will launch and automate")]
    }
}

// MARK: - EditHostsCapability

// EditHostsCapability does not produce InstallSteps — hosts modification is
// handled by TitanMission via ParsedInstructions.hostsEntries.
// RecipeComposer calls mergedHostsEntries() separately and injects the result
// into the synthetic ParsedInstructions it produces.
struct EditHostsCapability: InstallCapability {
    func canApply(to manifest: PackageManifest) -> Bool {
        !manifest.hostsEntries.isEmpty
    }

    func steps(from manifest: PackageManifest, product: ProductMatch?) -> [InstallStep] { [] }

    func mergedHostsEntries(manifest: PackageManifest, product: ProductMatch?) -> [String] {
        let productHosts = product?.hostsEntries ?? []
        return Array(Set(manifest.hostsEntries + productHosts))
    }
}

// MARK: - Shared ordering helper

// Sorts a list of URLs by the order they appear in instruction steps (fuzzy filename match).
// Falls back to leading-number sort, then alphabetical.
func sortedByInstructionOrder(_ urls: [URL], instructions: ParsedInstructions?) -> [URL] {
    guard let instr = instructions, instr.mentionsOrder, !instr.steps.isEmpty else {
        return urls.sorted { a, b in
            let na = capabilityLeadingNumber(from: a.lastPathComponent)
            let nb = capabilityLeadingNumber(from: b.lastPathComponent)
            if let na, let nb { return na < nb }
            if na != nil { return true }
            if nb != nil { return false }
            return a.lastPathComponent < b.lastPathComponent
        }
    }

    return urls.sorted { a, b in
        let sa = instructionRank(url: a, steps: instr.steps)
        let sb = instructionRank(url: b, steps: instr.steps)
        if sa != sb { return sa < sb }
        return a.lastPathComponent < b.lastPathComponent
    }
}

private func instructionRank(url: URL, steps: [String]) -> Int {
    let fname = url.deletingPathExtension().lastPathComponent.lowercased()
    for (i, step) in steps.enumerated() {
        let lower = step.lowercased()
        if lower.contains(fname) || fname.contains(lower.prefix(20)) { return i }
    }
    return Int.max
}

private func capabilityLeadingNumber(from name: String) -> Int? {
    let pattern = #"^(\d+)[\.\s\-]"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
          let range = Range(match.range(at: 1), in: name) else { return nil }
    return Int(name[range])
}
