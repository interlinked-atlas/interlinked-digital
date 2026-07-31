import Foundation

// RecipeComposer maps a WorkflowFamily to an ordered Capability list
// and composes them against a PackageManifest to produce an InstallPlan.
//
// Recipes live in Swift, not JSON or a database. Remote-editable recipes
// are not needed until there is a proven need for runtime recipe changes.
// New workflows are added as new switch cases with appropriate capability lists.

struct RecipeComposer {

    // MARK: - Capability recipes

    // Returns the ordered capabilities for a workflow family.
    // Capabilities whose canApply() returns false are automatically skipped by compose().
    private static func capabilities(for family: WorkflowFamily) -> [any InstallCapability] {
        switch family {

        case .pkgOnly:
            return [
                RunPKGCapability(),
                EditHostsCapability(),
            ]

        case .pkgPlusPatch:
            return [
                RunPKGCapability(),
                RunPatchCapability(),
                EditHostsCapability(),
            ]

        case .zipPluginDrop:
            return [
                ExtractZIPPluginsCapability(),
                EditHostsCapability(),
            ]

        case .loosePluginDrop:
            return [
                CopyLoosePluginsCapability(),
                EditHostsCapability(),
            ]

        case .dmgAppCopy:
            return [
                CopyAppCapability(),
                EditHostsCapability(),
            ]

        case .wavesManager:
            return [
                LaunchManagerAppCapability(appHint: "waves central"),
                RunPatchCapability(),       // skipped when no patch binary present
                EditHostsCapability(),
            ]

        case .nativeAccess:
            return [
                LaunchManagerAppCapability(appHint: "native access"),
                EditHostsCapability(),
            ]

        case .izotopePortal:
            return [
                LaunchManagerAppCapability(appHint: "izotope"),
                EditHostsCapability(),
            ]

        case .arturia:
            return [
                LaunchManagerAppCapability(appHint: "arturia"),
                EditHostsCapability(),
            ]

        case .splice:
            return [
                LaunchManagerAppCapability(appHint: "splice"),
                EditHostsCapability(),
            ]

        case .ilok:
            return [
                RunPKGCapability(),                        // skipped when no PKG
                LaunchManagerAppCapability(appHint: "ilok"),
                EditHostsCapability(),
            ]

        case .pluginAlliance:
            return [
                LaunchManagerAppCapability(appHint: "plugin alliance"),
                EditHostsCapability(),
            ]

        case .slateDigital:
            return [
                LaunchManagerAppCapability(appHint: "slate"),
                EditHostsCapability(),
            ]

        case .soundtoys:
            return [
                RunPKGCapability(),
                LaunchManagerAppCapability(appHint: "soundtoys"),
                EditHostsCapability(),
            ]

        case .fabfilter:
            return [
                RunPKGCapability(),
                LaunchManagerAppCapability(appHint: "fabfilter"),
                EditHostsCapability(),
            ]

        case .installerWizard:
            return [
                RunPKGCapability(),                        // skipped when no PKG
                LaunchManagerAppCapability(appHint: nil),  // first available installer app
                RunPatchCapability(),                      // skipped when no patch binary
                EditHostsCapability(),
            ]

        case .licensePatchOnly:
            return [
                RunPatchCapability(),
                RunScriptCapability(),                     // skipped when no scripts
                EditHostsCapability(),
            ]

        case .scriptBased:
            return [
                RunScriptCapability(),
                EditHostsCapability(),
            ]

        case .unknownComplex, .unknownSimple:
            // Mirror the current heuristic behaviour — try every capability and
            // let canApply() filter to what the package actually contains.
            return [
                RunPKGCapability(),
                CopyLoosePluginsCapability(),
                ExtractZIPPluginsCapability(),
                CopyAppCapability(),
                LaunchManagerAppCapability(appHint: nil),
                RunPatchCapability(),
                RunScriptCapability(),
                EditHostsCapability(),
            ]
        }
    }

    // MARK: - Compose

    // Applies the recipe for the given workflow to the manifest, merges product
    // knowledge, and returns a complete InstallPlan compatible with TitanMission.
    static func compose(
        workflow:  WorkflowMatch,
        manifest:  PackageManifest,
        product:   ProductMatch?,
        directory: String
    ) -> InstallPlan {

        let caps = capabilities(for: workflow.family)

        // ── Collect steps from each applicable capability ─────────────────
        var allSteps:     [InstallStep] = []
        var handledPaths: Set<String>   = []
        var hostsCapability: EditHostsCapability?

        for cap in caps {
            if let hc = cap as? EditHostsCapability {
                hostsCapability = hc   // handled separately below
                continue
            }
            guard cap.canApply(to: manifest) else { continue }

            for step in cap.steps(from: manifest, product: product) {
                guard !handledPaths.contains(step.url.path) else { continue }
                handledPaths.insert(step.url.path)
                allSteps.append(step)
            }
        }

        // Re-number steps sequentially after deduplication
        let orderedSteps = allSteps.enumerated().map { idx, step in
            InstallStep(url: step.url, type: step.type, order: idx + 1, note: step.note)
        }

        // ── Merge hosts from all sources ──────────────────────────────────
        let hosts = hostsCapability?.mergedHostsEntries(manifest: manifest, product: product)
                    ?? (product?.hostsEntries ?? [])

        // ── Build ParsedInstructions ──────────────────────────────────────
        // Instructions are preserved verbatim and hosts are overlaid with the merged set.
        // This ensures TitanMission.buildMission() can still find instruction-named scripts
        // and binaries via plan.instructions?.scriptsToRun / binariesToRun.
        let syntheticInstructions: ParsedInstructions?

        if let instr = manifest.instructions {
            // Real instruction file: keep all fields, replace hostsEntries with merged set.
            syntheticInstructions = ParsedInstructions(
                rawText:                 instr.rawText,
                sourceFileName:          instr.sourceFileName,
                steps:                   instr.steps,
                mentionsPatch:           instr.mentionsPatch || manifest.hasPatchBinary,
                mentionsOrder:           instr.mentionsOrder,
                mentionsRosetta:         instr.mentionsRosetta,
                mentionsAdminRequired:   instr.mentionsAdminRequired,
                customNotes:             instr.customNotes,
                appToLaunch:             instr.appToLaunch,
                mentionsSelectAll:       instr.mentionsSelectAll,
                mentionsManagerApp:      instr.mentionsManagerApp,
                folderCopySteps:         instr.folderCopySteps,
                hostsEntries:            hosts,
                terminalCommands:        instr.terminalCommands,
                mentionsXcodeTools:      instr.mentionsXcodeTools,
                scriptsToRun:            instr.scriptsToRun,
                binariesToRun:           instr.binariesToRun,
                detectedLanguage:        instr.detectedLanguage,
                requiresInternetActivation: instr.requiresInternetActivation,
                isDownloadAssistant:     instr.isDownloadAssistant
            )
        } else if !hosts.isEmpty || manifest.hasInstallerApp || manifest.needsXcodeTools {
            // No instruction file but we have computed knowledge — synthesise minimal instructions.
            syntheticInstructions = ParsedInstructions(
                rawText:                 "",
                sourceFileName:          "ATLAS",
                steps:                   [],
                mentionsPatch:           manifest.hasPatchBinary,
                mentionsOrder:           false,
                mentionsRosetta:         false,
                mentionsAdminRequired:   true,
                customNotes:             [],
                appToLaunch:             manifest.detectedManagerApp,
                mentionsSelectAll:       false,
                mentionsManagerApp:      manifest.hasInstallerApp,
                folderCopySteps:         [],
                hostsEntries:            hosts,
                terminalCommands:        [],
                mentionsXcodeTools:      manifest.needsXcodeTools,
                scriptsToRun:            [],
                binariesToRun:           [],
                detectedLanguage:        "en",
                requiresInternetActivation: false,
                isDownloadAssistant:     false
            )
        } else {
            syntheticInstructions = nil
        }

        // ── Warnings ──────────────────────────────────────────────────────
        var warnings: [String] = []

        if workflow.confidence == .low {
            warnings.append("ATLAS isn't certain about this package structure — review steps before proceeding.")
        }
        if orderedSteps.contains(where: { $0.type == .patch }) {
            warnings.append("Patch detected — will be applied after main installer.")
        }
        if orderedSteps.contains(where: { $0.type == .managedInstall }) {
            warnings.append("Manager installer detected — ATLAS will launch and automate it.")
        }
        if manifest.instructions?.mentionsRosetta == true {
            warnings.append("Instructions mention Rosetta — may be required on M1/M2 Macs.")
        }
        if manifest.instructions?.mentionsSelectAll == true {
            warnings.append("Instructions say to select all products — ATLAS will automate this.")
        }
        if manifest.needsXcodeTools {
            warnings.append("Xcode Command Line Tools may be required.")
        }

        // ── Summary ───────────────────────────────────────────────────────
        let sourceTag: String
        switch product?.source {
        case .titanMemory:
            sourceTag = "TITAN MEMORY™"
        case .atlasLearn(let count):
            sourceTag = "ATLASLearn™ (\(count) installs)"
        case nil:
            sourceTag = workflow.family.displayName
        }

        let iCount = orderedSteps.filter { $0.type == .installer     }.count
        let pCount = orderedSteps.filter { $0.type == .patch         }.count
        let lCount = orderedSteps.filter { $0.type == .plugin        }.count
        let aCount = orderedSteps.filter { $0.type == .app           }.count
        let mCount = orderedSteps.filter { $0.type == .managedInstall }.count

        var parts: [String] = []
        if iCount > 0 { parts.append("\(iCount) installer\(iCount > 1 ? "s" : "")") }
        if aCount > 0 { parts.append("\(aCount) app\(aCount > 1 ? "s" : "")") }
        if lCount > 0 { parts.append("\(lCount) plugin\(lCount > 1 ? "s" : "")") }
        if mCount > 0 { parts.append("manager") }
        if pCount > 0 { parts.append("\(pCount) patch\(pCount > 1 ? "es" : "")") }

        let summary = parts.isEmpty
            ? "[\(sourceTag)] No installable content found"
            : "[\(sourceTag)] \(parts.joined(separator: " → "))"

        let pipelineSource: String
        switch product?.source {
        case .titanMemory:              pipelineSource = "TITAN MEMORY"
        case .atlasLearn:               pipelineSource = "ATLASLearn"
        case nil:                       pipelineSource = "pipeline"
        }

        return InstallPlan(
            instructions: syntheticInstructions,
            orderedSteps: orderedSteps,
            warnings:     warnings,
            summary:      summary,
            planSource:   pipelineSource
        )
    }
}
