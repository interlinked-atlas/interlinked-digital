import Foundation
import AppKit
import ApplicationServices

// MARK: - Result types

struct VerifyResult {
    /// true = all hard checks passed (PKG receipts + files on disk). Soft checks (AU, app launch) are non-blocking.
    let passed: Bool
    let checks: [VerifyCheck]
    /// Demo-mode hits found during UI scan — non-empty means the app opened in Demo/Trial mode.
    let demoWarnings: [DemoHit]
    /// true = demo scan found activation-specific keywords only (license required, activate now, etc.)
    let requiresActivation: Bool

    var summary: String {
        let failed = checks.filter { !$0.passed && $0.isBlocker }
        if failed.isEmpty && demoWarnings.isEmpty { return "All checks passed" }
        var parts: [String] = failed.map { $0.label }
        if !demoWarnings.isEmpty { parts.append("Demo mode detected") }
        return parts.joined(separator: ", ")
    }

    var demoDetected: Bool { !demoWarnings.isEmpty }

    /// true = soft checks (AU, app launch, binary) flagged issues but hard checks passed.
    var hasVerificationWarnings: Bool {
        checks.contains { !$0.passed && !$0.isBlocker }
    }

    var verificationWarningSummary: String {
        checks.filter { !$0.passed && !$0.isBlocker }.map(\.detail).joined(separator: "; ")
    }
}

struct VerifyCheck {
    let label: String
    let passed: Bool
    let detail: String
    /// false = soft check — failure is a warning, not an install failure.
    var isBlocker: Bool = true
}

struct DemoHit {
    let keyword: String   // the matched keyword (e.g. "demo", "trial")
    let context: String   // surrounding text snippet for the log
    let source: String    // where it was found: "window title", "button", "label", etc.
}

// MARK: - TITAN VERIFY™

/// Post-install health checker. Runs after every successful install to confirm
/// the software actually landed and is not running in demo/trial mode.
struct TitanVerify {

    // MARK: - Keyword sets

    /// Keywords that signal the product needs a license key / activation, but is fully installed.
    /// If the demo scan finds ONLY these (no trial/demo keywords), classify as activationRequired.
    private static let activationKeywords: Set<String> = [
        "activation required", "please activate", "activate now",
        "license required", "enter license", "enter serial",
        "register now", "please register",
    ]

    /// Keywords that indicate the app is in demo, trial, or unlicensed mode.
    /// Matched case-insensitively as whole-word or substring depending on specificity.
    private static let demoKeywords: [String] = [
        "demo mode", "demo version", "running in demo",
        "trial mode", "trial version", "trial expired", "trial period",
        "unregistered", "unlicensed", "not licensed",
        "license required", "enter license", "enter serial",
        "activate now", "activation required", "please activate",
        "buy now", "purchase to unlock", "upgrade to unlock",
        "days remaining", "days left", "days of use",
        "watermarked", "watermark",
        "evaluation version", "evaluation mode",
        "limited functionality", "limited version",
        "full version required",
        "register now", "please register",
    ]

    /// Short single-word signals — only matched when they appear as standalone words
    /// (surrounded by spaces, punctuation, or string boundaries) to avoid false positives
    /// like "Democracy" or "Fundamental".
    private static let demoSingleWords: [String] = [
        "demo", "trial", "unregistered", "unlicensed",
        "watermarked", "evaluation",
    ]

    // MARK: - Entry point

    static func verify(
        installedFiles: [InstallRecord.InstalledFile],
        pkgReceiptIDs: [String],
        sourceURL: URL,
        logger: Logger
    ) async -> VerifyResult {

        var checks: [VerifyCheck] = []
        var demoWarnings: [DemoHit] = []

        // 1. PKG receipt check
        if !pkgReceiptIDs.isEmpty {
            checks.append(verifyPKGReceipts(pkgReceiptIDs))
        }

        // 2. Installed files on-disk check
        if !installedFiles.isEmpty {
            checks.append(verifyInstalledFiles(installedFiles))
        }

        // 3. App launch + demo scan (first .app in Applications only)
        let appFiles = installedFiles.filter {
            $0.destinationPath.hasSuffix(".app") &&
            ($0.destinationPath.hasPrefix("/Applications") ||
             $0.destinationPath.hasPrefix(NSHomeDirectory() + "/Applications"))
        }
        if let appFile = appFiles.first {
            let appURL = URL(fileURLWithPath: appFile.destinationPath)
            let (launchCheck, hits) = await verifyAppAndScanDemo(appURL: appURL)
            checks.append(launchCheck)
            demoWarnings.append(contentsOf: hits)
        }

        // 4. AU component validation
        if let auFile = installedFiles.first(where: { $0.destinationPath.hasSuffix(".component") }) {
            checks.append(await verifyAudioUnit(componentPath: auFile.destinationPath))
        }

        // 5. VST3 / AAX / VST binary validation
        let pluginExtensions = ["vst3", "aaxplugin", "vst"]
        for plugin in installedFiles.filter({
            pluginExtensions.contains(URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased())
        }).prefix(2) {
            checks.append(verifyPlugin(path: plugin.destinationPath))
        }

        // 6. Fallback for script/hosts-only installs
        if installedFiles.isEmpty && pkgReceiptIDs.isEmpty {
            checks.append(verifyFallback(sourceURL: sourceURL))
        }

        // Hard checks (receipts, files) determine pass/fail.  Soft checks (AU, app launch,
        // binary validity) are warnings only — files being present means install succeeded.
        let allPassed = checks.filter(\.isBlocker).allSatisfy(\.passed)
        let hasWarnings = checks.contains { !$0.passed && !$0.isBlocker }

        // If demo scan found ONLY activation-specific keywords, classify as activation-required
        // rather than a generic demo warning (product is installed and just needs a license).
        let activationHits = demoWarnings.filter { activationKeywords.contains($0.keyword) }
        let trialHits      = demoWarnings.filter { !activationKeywords.contains($0.keyword) }
        let requiresActivation = !activationHits.isEmpty && trialHits.isEmpty

        // Log results
        await MainActor.run { logger.log("── TITAN VERIFY™ ──────────────────────────────") }
        for c in checks {
            let tag = c.passed ? "✓" : (c.isBlocker ? "✗" : "⚠")
            await MainActor.run { logger.log("  \(tag) \(c.label): \(c.detail)") }
        }
        let capturedDemo = demoWarnings
        if !capturedDemo.isEmpty {
            await MainActor.run { logger.log("  ⚠️ DEMO MODE SCAN — \(capturedDemo.count) signal(s) detected:") }
            for hit in capturedDemo {
                await MainActor.run { logger.log("    [\(hit.source)] \"\(hit.keyword)\" → \(hit.context)") }
            }
            let keywords = capturedDemo.map { $0.keyword }
            await LicenseManagerDetector.logHints(for: keywords, to: logger)
        }
        await MainActor.run {
            if !allPassed {
                logger.log("  ❌ Verification failed — install downgraded to Failed")
            } else if requiresActivation {
                logger.log("  ⚠️ Installed — Activation Required (open in your DAW and enter your license key)")
            } else if hasWarnings {
                logger.log("  ⚠️ Installed — Verification Warning (soft checks flagged; files confirmed present)")
            } else if !capturedDemo.isEmpty {
                logger.log("  ⚠️ Install OK but Demo Mode detected — license may not have applied")
            } else {
                logger.log("  ✅ Verification passed — no demo signals found")
            }
        }

        return VerifyResult(passed: allPassed, checks: checks, demoWarnings: demoWarnings,
                            requiresActivation: requiresActivation)
    }

    // MARK: - App launch + Demo Mode scan

    private static func verifyAppAndScanDemo(appURL: URL) async -> (VerifyCheck, [DemoHit]) {
        let appName = appURL.deletingPathExtension().lastPathComponent

        guard FileManager.default.fileExists(atPath: appURL.path) else {
            return (VerifyCheck(label: "App launch (\(appName))", passed: false,
                                detail: "Bundle not found at \(appURL.path)", isBlocker: false), [])
        }

        // Strip quarantine so the app can launch cleanly
        _ = shell("xattr -dr com.apple.quarantine \(shellEscape(appURL.path)) 2>/dev/null")

        await MainActor.run { NSWorkspace.shared.open(appURL) }

        // Wait up to 15s for app to finish launching
        let appeared = await MacUIAutomator.waitFor(timeout: 15) {
            MacUIAutomator.findApp(named: appName)?.isFinishedLaunching == true
        }

        guard appeared, let runningApp = MacUIAutomator.findApp(named: appName) else {
            return (VerifyCheck(label: "App launch (\(appName))", passed: false,
                                detail: "App did not appear within 15s", isBlocker: false), [])
        }

        // Wait an extra 3s for any license/demo dialogs to appear after launch
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        // Scan AX tree for demo signals
        let hits = scanDemoSignals(in: runningApp)

        // Quit cleanly
        await MacUIAutomator.quitApp(named: appName)

        let launchCheck = VerifyCheck(
            label: "App launch (\(appName))",
            passed: true,
            detail: hits.isEmpty
                ? "Launched and quit successfully — no demo signals"
                : "Launched OK — ⚠️ demo signals found (see Demo Scan below)")

        return (launchCheck, hits)
    }

    // MARK: - AX tree demo scanner

    private static func scanDemoSignals(in app: NSRunningApplication) -> [DemoHit] {
        let axApp = MacUIAutomator.axApp(for: app)
        var hits: [DemoHit] = []
        var seen = Set<String>() // deduplicate

        // Gather all text from the entire AX tree across all windows
        let windows = MacUIAutomator.windows(of: axApp)
        let roots: [AXUIElement] = windows.isEmpty ? [axApp] : windows

        for root in roots {
            // Check window title itself
            let winTitle = axTitle(of: root)
            if !winTitle.isEmpty {
                let winHits = matchDemoKeywords(in: winTitle, source: "window title")
                for h in winHits where !seen.contains(h.keyword + h.context) {
                    hits.append(h)
                    seen.insert(h.keyword + h.context)
                }
            }

            // Walk every element in the tree
            let elements = MacUIAutomator.allElements(under: root, maxDepth: 12)
            for el in elements {
                let texts = collectTexts(from: el)
                for text in texts where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let source = axRoleLabel(of: el)
                    let elHits = matchDemoKeywords(in: text, source: source)
                    for h in elHits where !seen.contains(h.keyword + h.context) {
                        hits.append(h)
                        seen.insert(h.keyword + h.context)
                    }
                }
            }
        }

        return hits
    }

    /// Collect all readable text strings from an AX element.
    private static func collectTexts(from el: AXUIElement) -> [String] {
        var texts: [String] = []
        for key in [kAXTitleAttribute, kAXValueAttribute,
                    kAXDescriptionAttribute, kAXHelpAttribute,
                    kAXPlaceholderValueAttribute] as [CFString] {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, key, &v) == .success else { continue }
            if let s = v as? String, !s.isEmpty { texts.append(s) }
        }
        return texts
    }

    /// Match demo keywords against a text string. Returns all hits.
    private static func matchDemoKeywords(in text: String, source: String) -> [DemoHit] {
        let lower = text.lowercased()
        var hits: [DemoHit] = []

        // Multi-word phrases — simple substring match
        for phrase in demoKeywords {
            if lower.contains(phrase) {
                let context = contextSnippet(around: phrase, in: lower)
                hits.append(DemoHit(keyword: phrase, context: context, source: source))
            }
        }

        // Single words — require word boundaries
        for word in demoSingleWords {
            let pattern = "(?<![a-z])\(NSRegularExpression.escapedPattern(for: word))(?![a-z])"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
                // Skip if already captured by a multi-word phrase
                if !hits.contains(where: { $0.keyword.hasPrefix(word) }) {
                    let context = contextSnippet(around: word, in: lower)
                    hits.append(DemoHit(keyword: word, context: context, source: source))
                }
            }
        }

        return hits
    }

    /// Returns up to 60 chars of context around the first occurrence of `term` in `text`.
    private static func contextSnippet(around term: String, in text: String) -> String {
        guard let range = text.range(of: term, options: .caseInsensitive) else {
            return String(text.prefix(60))
        }
        let start = text.index(range.lowerBound, offsetBy: -min(20, text.distance(from: text.startIndex, to: range.lowerBound)), limitedBy: text.startIndex) ?? text.startIndex
        let end   = text.index(range.upperBound, offsetBy: min(40, text.distance(from: range.upperBound, to: text.endIndex)), limitedBy: text.endIndex) ?? text.endIndex
        return "…\(text[start..<end])…"
    }

    // MARK: - AX helpers

    private static func axTitle(of el: AXUIElement) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v) == .success,
              let s = v as? String else { return "" }
        return s
    }

    private static func axRoleLabel(of el: AXUIElement) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &v) == .success,
              let role = v as? String else { return "element" }
        switch role {
        case "AXStaticText":     return "label"
        case "AXButton":         return "button"
        case "AXTextField":      return "text field"
        case "AXTextArea":       return "text area"
        case "AXCheckBox":       return "checkbox"
        case "AXMenuItem":       return "menu item"
        case "AXWindow":         return "window"
        case "AXSheet":          return "sheet"
        case "AXGroup":          return "group"
        default:                 return role.replacingOccurrences(of: "AX", with: "").lowercased()
        }
    }

    // MARK: - Other checks

    private static func verifyPKGReceipts(_ ids: [String]) -> VerifyCheck {
        let missing = ids.filter {
            shell("pkgutil --pkg-info \(shellEscape($0)) 2>/dev/null").isEmpty
        }
        return missing.isEmpty
            ? VerifyCheck(label: "PKG receipts", passed: true,  detail: "\(ids.count) receipt(s) confirmed")
            : VerifyCheck(label: "PKG receipts", passed: false, detail: "Missing: \(missing.joined(separator: ", "))")
    }

    private static func verifyInstalledFiles(_ files: [InstallRecord.InstalledFile]) -> VerifyCheck {
        let missing = files.filter { !FileManager.default.fileExists(atPath: $0.destinationPath) }
        if missing.isEmpty {
            return VerifyCheck(label: "Files on disk", passed: true, detail: "\(files.count) file(s) present")
        }
        let names = missing.prefix(3).map { URL(fileURLWithPath: $0.destinationPath).lastPathComponent }
        return VerifyCheck(label: "Files on disk", passed: false, detail: "Missing: \(names.joined(separator: ", "))")
    }

    private static func verifyAudioUnit(componentPath: String) async -> VerifyCheck {
        let name = URL(fileURLWithPath: componentPath).deletingPathExtension().lastPathComponent
        guard FileManager.default.fileExists(atPath: componentPath) else {
            // Hard failure: component should be on disk if the installer ran
            return VerifyCheck(label: "AU (\(name))", passed: false, detail: "Component missing on disk")
        }
        let plistURL = URL(fileURLWithPath: componentPath).appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: plistURL),
              let components = plist["AudioComponents"] as? [[String: Any]],
              let first = components.first,
              let type = first["type"] as? String,
              let subtype = first["subtype"] as? String,
              let manufacturer = first["manufacturer"] as? String else {
            return VerifyCheck(label: "AU (\(name))", passed: true,
                               detail: "Component present (no AU keys — third-party format)")
        }
        // Retry up to 3 times with 2s delay — AU registration can lag post-install.
        for attempt in 1...3 {
            let out = shell("auval -v \(shellEscape(type)) \(shellEscape(subtype)) \(shellEscape(manufacturer)) 2>&1")
            if out.contains("PASS") || out.contains("successfully opened") {
                return VerifyCheck(label: "AU (\(name))", passed: true, detail: "auval passed")
            }
            if attempt < 3 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        // Still failing after 3 attempts — non-blocking warning.
        // Files are confirmed present; AU may register on first DAW load or after activation.
        return VerifyCheck(label: "AU (\(name))", passed: false,
                           detail: "AU not yet registered — open in your DAW to confirm activation",
                           isBlocker: false)
    }

    private static func verifyPlugin(path: String) -> VerifyCheck {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let ext  = URL(fileURLWithPath: path).pathExtension.lowercased()
        guard FileManager.default.fileExists(atPath: path) else {
            // File presence already caught by verifyInstalledFiles; treat as soft warning here
            return VerifyCheck(label: "\(ext.uppercased()) (\(name))", passed: false,
                               detail: "Not found at expected path", isBlocker: false)
        }
        let binDir = URL(fileURLWithPath: path).appendingPathComponent("Contents/MacOS")
        if FileManager.default.fileExists(atPath: binDir.path) {
            let bins = (try? FileManager.default.contentsOfDirectory(atPath: binDir.path)) ?? []
            guard !bins.isEmpty else {
                return VerifyCheck(label: "\(ext.uppercased()) (\(name))", passed: false,
                                   detail: "Bundle present but Contents/MacOS is empty", isBlocker: false)
            }
            let out = shell("file \(shellEscape(binDir.appendingPathComponent(bins[0]).path)) 2>/dev/null")
            let ok  = out.contains("Mach-O") || out.contains("universal binary")
            return VerifyCheck(label: "\(ext.uppercased()) (\(name))", passed: ok,
                               detail: ok ? "Valid Mach-O binary" : "Binary not recognized as Mach-O",
                               isBlocker: false)
        }
        return VerifyCheck(label: "\(ext.uppercased()) (\(name))", passed: true, detail: "Present on disk")
    }

    private static func verifyFallback(sourceURL: URL) -> VerifyCheck {
        VerifyCheck(label: "Install trace", passed: true,
                    detail: "No tracked files — script/hosts-only install assumed complete")
    }

    // MARK: - Shell helper

    @discardableResult
    private static func shell(_ command: String) -> String {
        let p = Process()
        p.launchPath = "/bin/bash"
        p.arguments  = ["-c", command]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = pipe
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func shellEscape(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
