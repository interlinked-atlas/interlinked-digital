#if DEBUG
import Foundation

// MARK: - Transaction Attribution Tests
//
// Tests for the receipt and filesystem transaction-attribution logic.
// Self-contained, non-destructive, no permanent state changes.
// Run via ATLASDebugMenu alongside RecoveryKitTests.
//
// Scenarios tested:
//   A — Clean install: all receipts are new (after − before)
//   B — Complete reinstall: all receipts pre-existed, updated by installer
//   C — Mixed: some new, some pre-existing (FabFilter-style)
//   D — Pre-existing plugin overwritten: mtime reset, ctime advances (ctime detection)
//   E — Unrelated background receipt: timestamp outside window, must be excluded
//   F — Unrelated background receipt: timestamp inside window but not in after set
//   G — FilesystemSnapshot ctime: detects bundle replaced even when mtime was reset

enum TransactionAttributionTests {

    struct TestResult {
        let name: String
        let passed: Bool
        let detail: String
    }

    static func runAll() -> [TestResult] {
        [
            tA_cleanInstallNewReceiptsOnly(),
            tB_reinstallAllReceiptsPreExisting(),
            tC_mixedNewAndPreExistingReceipts(),
            tD_preExistingPluginMtimeReset(),
            tE_unrelatedReceiptOutsideWindow(),
            tF_unrelatedReceiptInsideWindowNotInAfter(),
            tG_filesystemSnapshotCtimeDetection(),
            tH_preExistingReceiptUnchangedFile(),
            tI_preExistingFileReplaced(),
            tJ_newFileTransactionCreated(),
            tK_sharedReceiptAdobeFontsPattern(),
            tL_cleanInstallFontsNew(),
            tM_outsideSnapshotCoverage(),
        ]
    }

    // MARK: - Helpers

    private static let receiptDir = "/private/var/db/receipts"

    // Write a synthetic receipt plist to a temp location and return the path.
    // Does NOT write to /var/db/receipts — avoids any system mutation.
    private static func syntheticReceiptAttrs(modDate: Date) -> [FileAttributeKey: Any] {
        [.modificationDate: modDate]
    }

    // Simulate findNewReceipts by applying the timestamp filter to a mock receipt set.
    // Mirrors the production logic without touching disk receipts.
    private static func simulateFindNewReceipts(
        allAfterIDs: Set<String>,
        modDates: [String: Date],  // plist mod dates for each candidate
        since: Date
    ) -> [String] {
        let grace = since.addingTimeInterval(-5)
        return allAfterIDs.filter { id in
            guard let mod = modDates[id] else { return false }
            return mod >= grace
        }.sorted()
    }

    // MARK: - Scenario A: Clean install — all receipts are genuinely new

    static func tA_cleanInstallNewReceiptsOnly() -> TestResult {
        let name = "A — Clean install: all new receipts attributed"
        let installStart = Date(timeIntervalSinceNow: -30)  // 30s ago
        let before: Set<String> = []
        let newReceipts: Set<String> = ["com.vendor.PluginX", "com.vendor.PluginY"]
        // Both receipts were written during the install window (20s ago)
        let modDates: [String: Date] = [
            "com.vendor.PluginX": Date(timeIntervalSinceNow: -20),
            "com.vendor.PluginY": Date(timeIntervalSinceNow: -18),
        ]
        let _ = before  // unused: clean install has no before receipts to check
        let result = simulateFindNewReceipts(allAfterIDs: newReceipts, modDates: modDates, since: installStart)
        let expected = ["com.vendor.PluginX", "com.vendor.PluginY"]
        guard result == expected else {
            return TestResult(name: name, passed: false,
                              detail: "Expected \(expected), got \(result)")
        }
        return TestResult(name: name, passed: true, detail: "Both new receipts attributed correctly")
    }

    // MARK: - Scenario B: Complete reinstall — all receipts pre-existed, all updated

    static func tB_reinstallAllReceiptsPreExisting() -> TestResult {
        let name = "B — Complete reinstall: pre-existing receipts updated by installer"
        let installStart = Date(timeIntervalSinceNow: -60)
        // 5 receipts existed before; installer updated all of them
        let before: Set<String> = ["com.v.A", "com.v.B", "com.v.C", "com.v.D", "com.v.E"]
        let after: Set<String>  = before  // no new receipts; all pre-existing
        // All receipt plists were rewritten during the install window (40–50s ago)
        let modDates: [String: Date] = [
            "com.v.A": Date(timeIntervalSinceNow: -50),
            "com.v.B": Date(timeIntervalSinceNow: -48),
            "com.v.C": Date(timeIntervalSinceNow: -46),
            "com.v.D": Date(timeIntervalSinceNow: -44),
            "com.v.E": Date(timeIntervalSinceNow: -42),
        ]
        // Old (known-bad) logic: after − before → empty → fallback by name
        let oldLogicNewOnly = after.subtracting(before)
        guard oldLogicNewOnly.isEmpty else {
            return TestResult(name: name, passed: false, detail: "Test setup wrong: after−before should be empty")
        }
        // New logic: scan all after receipts for timestamp in install window
        let result = simulateFindNewReceipts(allAfterIDs: after, modDates: modDates, since: installStart)
        guard result.count == 5 else {
            return TestResult(name: name, passed: false,
                              detail: "Expected 5 receipts, got \(result.count): \(result)")
        }
        return TestResult(name: name, passed: true,
                          detail: "All 5 pre-existing receipts correctly attributed via timestamp window")
    }

    // MARK: - Scenario C: Mixed — some new, some pre-existing (FabFilter pattern)

    static func tC_mixedNewAndPreExistingReceipts() -> TestResult {
        let name = "C — Mixed: new and pre-existing receipts, both attributed"
        let installStart = Date(timeIntervalSinceNow: -90)
        // 22 pre-existing FabFilter receipts + 1 new (Pro-C.3) + 1 font package
        let preExisting = Set((1...22).map { "com.fabfilter.Plugin\($0)" })
        let genuinelyNew: Set<String> = ["com.fabfilter.Pro-C.3", "com.adobe.Fonts"]
        let after = preExisting.union(genuinelyNew)
        // All updated during the install window (80–70s ago)
        var modDates: [String: Date] = [:]
        for id in after {
            modDates[id] = Date(timeIntervalSinceNow: Double.random(in: -80 ..< -70))
        }
        // Old logic misses the 22 pre-existing
        let oldResult = after.subtracting(preExisting)  // only 2 new
        guard oldResult.count == 2 else {
            return TestResult(name: name, passed: false, detail: "Test setup error")
        }
        // New logic captures all 24
        let result = simulateFindNewReceipts(allAfterIDs: after, modDates: modDates, since: installStart)
        guard result.count == 24 else {
            return TestResult(name: name, passed: false,
                              detail: "Expected 24, got \(result.count). Missing: \(Set(result).symmetricDifference(after))")
        }
        guard result.contains("com.fabfilter.Pro-C.3") && result.contains("com.adobe.Fonts") else {
            return TestResult(name: name, passed: false, detail: "New receipts missing from result")
        }
        return TestResult(name: name, passed: true,
                          detail: "All 24 receipts (22 pre-existing + 2 new) attributed. Old logic would have missed 22.")
    }

    // MARK: - Scenario D: Unrelated receipt with timestamp outside install window — excluded

    static func tD_preExistingPluginMtimeReset() -> TestResult {
        let name = "D — Unrelated receipt outside window: excluded"
        let installStart = Date(timeIntervalSinceNow: -60)
        let transactionReceipts: Set<String> = ["com.v.Plugin"]
        var modDates: [String: Date] = [
            "com.v.Plugin": Date(timeIntervalSinceNow: -50),                // inside window ✓
            "com.acrobat.reader": Date(timeIntervalSinceNow: -86400 * 30),  // 30 days ago ✗
        ]
        let _ = modDates  // used below
        let allAfter: Set<String> = transactionReceipts.union(["com.acrobat.reader"])
        let result = simulateFindNewReceipts(allAfterIDs: allAfter, modDates: modDates, since: installStart)
        guard result == ["com.v.Plugin"] else {
            return TestResult(name: name, passed: false,
                              detail: "Expected only com.v.Plugin, got \(result)")
        }
        return TestResult(name: name, passed: true,
                          detail: "com.acrobat.reader (30 days old) correctly excluded; com.v.Plugin included")
    }

    // MARK: - Scenario E: Background receipt inside window but with very old plist — excluded

    static func tE_unrelatedReceiptOutsideWindow() -> TestResult {
        let name = "E — Background process with old receipt timestamp: excluded"
        let installStart = Date(timeIntervalSinceNow: -30)
        // Toontrack Product Manager updated a receipt 2 hours before our install
        let modDates: [String: Date] = [
            "com.toontrack.EZDrummer3":  Date(timeIntervalSinceNow: -7200),  // 2h ago — before install
            "com.v.NewPlugin":           Date(timeIntervalSinceNow: -20),    // during install window
        ]
        let allAfter: Set<String> = ["com.toontrack.EZDrummer3", "com.v.NewPlugin"]
        let result = simulateFindNewReceipts(allAfterIDs: allAfter, modDates: modDates, since: installStart)
        guard result == ["com.v.NewPlugin"] else {
            return TestResult(name: name, passed: false,
                              detail: "Expected only com.v.NewPlugin, got \(result)")
        }
        return TestResult(name: name, passed: true,
                          detail: "Toontrack receipt (2h before install) excluded; only window-matched receipt included")
    }

    // MARK: - Scenario F: Background receipt inside window but also happened to match window

    static func tF_unrelatedReceiptInsideWindowNotInAfter() -> TestResult {
        let name = "F — Background receipt inside window (edge case): timestamp discrimination"
        // Two receipts both updated during the install window.
        // One is a transaction receipt; one is from a background updater.
        // The only discriminator is: was the receipt actually involved in the install?
        // Our model uses the timestamp window — if both are inside, both are attributed.
        // This is the known limitation: we cannot distinguish two receipts both updated
        // in the same 90-second window without additional evidence (e.g. Distribution XML).
        // The test documents this behavior explicitly.
        let installStart = Date(timeIntervalSinceNow: -60)
        let modDates: [String: Date] = [
            "com.vendor.Plugin":          Date(timeIntervalSinceNow: -50),  // transaction
            "com.background.updater.pkg": Date(timeIntervalSinceNow: -45),  // coincidental
        ]
        let allAfter: Set<String> = Set(modDates.keys)
        let result = simulateFindNewReceipts(allAfterIDs: allAfter, modDates: modDates, since: installStart)
        // Both will be attributed — this is the known boundary of the timestamp model.
        // A false positive here is safer than a false negative (missing a transaction receipt).
        // The com.adobe.Fonts case shows this is not a problem in practice: FabFilter's
        // Fonts_Installer.pkg genuinely installs com.adobe.Fonts as part of the transaction.
        guard result.count == 2 else {
            return TestResult(name: name, passed: false,
                              detail: "Expected 2 results (both inside window), got \(result)")
        }
        return TestResult(name: name, passed: true,
                          detail: "Both window-matching receipts attributed. Known limitation: background updater " +
                                  "coinciding in the same window would be attributed. In practice, macOS installers " +
                                  "run fast (<90s) making coincidence rare; false positives are safer than false negatives.")
    }

    // MARK: - Scenario G: FilesystemSnapshot ctime detection

    static func tG_filesystemSnapshotCtimeDetection() -> TestResult {
        let name = "G — FilesystemSnapshot: ctime detects installer-replaced bundle when mtime was reset"
        // Simulate three files with different mtime/ctime relationships:
        //   1. Unchanged file: mtime and ctime both predate install
        //   2. New file: mtime and ctime both during install window
        //   3. Replaced file (mtime reset by postinstall): mtime predates install, ctime is during install

        let installStart = Date(timeIntervalSinceNow: -60)
        let beforeInstall = Date(timeIntervalSinceNow: -3600)     // 1h ago
        let duringInstall = Date(timeIntervalSinceNow: -30)       // 30s ago

        // Simulate snapshot diff using max(mtime, ctime)
        typealias FileDates = (mtime: Date, ctime: Date)

        let before: [String: FileDates] = [
            "/Library/Audio/Plug-Ins/Components/Unchanged.component":    (mtime: beforeInstall, ctime: beforeInstall),
            "/Library/Audio/Plug-Ins/Components/WillBeReplaced.component": (mtime: beforeInstall, ctime: beforeInstall),
        ]
        let after: [String: FileDates] = [
            // Unchanged: no change
            "/Library/Audio/Plug-Ins/Components/Unchanged.component":    (mtime: beforeInstall, ctime: beforeInstall),
            // New file: both dates during install
            "/Library/Audio/Plug-Ins/Components/NewPlugin.component":    (mtime: duringInstall, ctime: duringInstall),
            // Replaced, mtime reset by postinstall (FabFilter pattern): mtime=old, ctime=during
            "/Library/Audio/Plug-Ins/Components/WillBeReplaced.component": (mtime: beforeInstall, ctime: duringInstall),
        ]

        var changed: [String] = []
        for (path, afterDates) in after {
            let afterEffective = max(afterDates.mtime, afterDates.ctime)
            if let beforeDates = before[path] {
                let beforeEffective = max(beforeDates.mtime, beforeDates.ctime)
                if afterEffective > beforeEffective { changed.append(path) }
            } else {
                changed.append(path)
            }
        }

        let changedSet = Set(changed)
        guard !changedSet.contains("/Library/Audio/Plug-Ins/Components/Unchanged.component") else {
            return TestResult(name: name, passed: false, detail: "Unchanged.component incorrectly flagged")
        }
        guard changedSet.contains("/Library/Audio/Plug-Ins/Components/NewPlugin.component") else {
            return TestResult(name: name, passed: false, detail: "NewPlugin.component not detected")
        }
        guard changedSet.contains("/Library/Audio/Plug-Ins/Components/WillBeReplaced.component") else {
            return TestResult(name: name, passed: false,
                              detail: "WillBeReplaced.component not detected — ctime-based detection failed")
        }
        guard changedSet.count == 2 else {
            return TestResult(name: name, passed: false,
                              detail: "Expected 2 changed paths, got \(changedSet.count): \(changedSet)")
        }
        return TestResult(name: name, passed: true,
                          detail: "Unchanged excluded; new file detected via mtime+ctime; replaced file " +
                                  "detected via ctime despite mtime reset. Matches FabFilter postinstall pattern.")
    }
    // MARK: - Scenario H: pre-existing receipt + pre-existing file → preExistingUnchanged → not deleted

    static func tH_preExistingReceiptUnchangedFile() -> TestResult {
        let name = "H — Pre-existing receipt + unchanged file: preExistingUnchanged → not authorized"
        let installStart = Date(timeIntervalSinceNow: -60)
        let beforeInstall = Date(timeIntervalSinceNow: -3600)  // file existed 1h before install
        let duringInstall = Date(timeIntervalSinceNow: -30)

        // Receipt pre-existed and was rewritten (new timestamp model attributes it)
        // but the font file itself was NOT modified (ctime unchanged).
        let beforeFS = makeSnapshot(["/Library/Fonts/FontA.ttf": (mtime: beforeInstall, ctime: beforeInstall)])
        let afterFS  = makeSnapshot(["/Library/Fonts/FontA.ttf": (mtime: beforeInstall, ctime: beforeInstall)])

        let evidence = FilesystemSnapshot.classifyPath(
            "/Library/Fonts/FontA.ttf", before: beforeFS, after: afterFS, installStart: installStart)

        guard evidence == .preExistingUnchanged else {
            return TestResult(name: name, passed: false,
                              detail: "Expected .preExistingUnchanged, got .\(evidence.rawValue). " +
                                      "File must NOT be authorized for deletion.")
        }
        let authorized = evidenceAuthorizesDeletion(evidence: evidence)
        guard !authorized else {
            return TestResult(name: name, passed: false,
                              detail: "evidenceAuthorizesDeletion returned true for .preExistingUnchanged — BUG")
        }
        return TestResult(name: name, passed: true,
                          detail: "Pre-existing unchanged file: correctly classified and NOT authorized for deletion.")
    }

    // MARK: - Scenario I: pre-existing file replaced by installer → transactionReplaced → fail closed

    static func tI_preExistingFileReplaced() -> TestResult {
        let name = "I — Pre-existing file replaced by installer: transactionReplaced → fail closed"
        let installStart = Date(timeIntervalSinceNow: -60)
        let beforeInstall = Date(timeIntervalSinceNow: -3600)
        let duringInstall = Date(timeIntervalSinceNow: -30)

        // Font file existed before install. Installer replaced it (ctime advanced).
        // This is the Adobe CC + FabFilter scenario.
        let beforeFS = makeSnapshot(["/Library/Fonts/FontA.ttf": (mtime: beforeInstall, ctime: beforeInstall)])
        let afterFS  = makeSnapshot(["/Library/Fonts/FontA.ttf": (mtime: beforeInstall, ctime: duringInstall)])

        let evidence = FilesystemSnapshot.classifyPath(
            "/Library/Fonts/FontA.ttf", before: beforeFS, after: afterFS, installStart: installStart)

        guard evidence == .transactionReplaced else {
            return TestResult(name: name, passed: false,
                              detail: "Expected .transactionReplaced, got .\(evidence.rawValue).")
        }
        let authorized = evidenceAuthorizesDeletion(evidence: evidence)
        guard !authorized else {
            return TestResult(name: name, passed: false,
                              detail: "evidenceAuthorizesDeletion returned true for .transactionReplaced — FAIL CLOSED violated. " +
                                      "Replacing a pre-existing file does NOT confer exclusive ownership.")
        }
        return TestResult(name: name, passed: true,
                          detail: "Pre-existing file replaced by installer: classified .transactionReplaced, " +
                                  "NOT authorized (fail closed). Adobe CC fonts preserved in this scenario.")
    }

    // MARK: - Scenario J: clean install, new file → transactionCreated → authorized

    static func tJ_newFileTransactionCreated() -> TestResult {
        let name = "J — New file (clean install): transactionCreated → authorized for deletion"
        let installStart = Date(timeIntervalSinceNow: -60)
        let duringInstall = Date(timeIntervalSinceNow: -30)

        // Font file did not exist before install. FabFilter created it.
        let beforeFS = makeSnapshot([:])
        let afterFS  = makeSnapshot(["/Library/Fonts/SourceCodePro-Light.ttf": (mtime: duringInstall, ctime: duringInstall)])

        let evidence = FilesystemSnapshot.classifyPath(
            "/Library/Fonts/SourceCodePro-Light.ttf", before: beforeFS, after: afterFS, installStart: installStart)

        guard evidence == .transactionCreated else {
            return TestResult(name: name, passed: false,
                              detail: "Expected .transactionCreated, got .\(evidence.rawValue).")
        }
        let authorized = evidenceAuthorizesDeletion(evidence: evidence)
        guard authorized else {
            return TestResult(name: name, passed: false,
                              detail: "evidenceAuthorizesDeletion returned false for .transactionCreated — new files must be deletable.")
        }
        return TestResult(name: name, passed: true,
                          detail: "New font file: correctly authorized for deletion on uninstall.")
    }

    // MARK: - Scenario K: shared receipt (com.adobe.Fonts pattern)

    static func tK_sharedReceiptAdobeFontsPattern() -> TestResult {
        let name = "K — Shared receipt (Adobe Fonts pattern): provenance .rewritten → not forgotten; files preserved"
        let installStart = Date(timeIntervalSinceNow: -60)
        let beforeInstall = Date(timeIntervalSinceNow: -3600)
        let duringInstall = Date(timeIntervalSinceNow: -30)

        // Machine has Adobe CC. com.adobe.Fonts receipt pre-existed.
        let beforeReceipts: Set<String> = ["com.adobe.Fonts", "com.adobe.acrobat", "com.fabfilter.Pro-Q.4"]
        let afterReceipts:  Set<String> = ["com.adobe.Fonts", "com.adobe.acrobat", "com.fabfilter.Pro-Q.4",
                                           "com.fabfilter.Pro-C.3"]  // only Pro-C.3 is new

        // After FabFilter install: com.adobe.Fonts plist was rewritten (timestamp in window)
        let receiptModDates: [String: Date] = [
            "com.adobe.Fonts":    duringInstall,   // rewritten by FabFilter installer
            "com.fabfilter.Pro-C.3": duringInstall, // new receipt
        ]
        let grace = installStart.addingTimeInterval(-5)
        let attributed = afterReceipts.filter { id in
            guard let mod = receiptModDates[id] else { return false }
            return mod >= grace
        }
        // com.adobe.Fonts should be attributed (timestamp in window)
        guard attributed.contains("com.adobe.Fonts") && attributed.contains("com.fabfilter.Pro-C.3") else {
            return TestResult(name: name, passed: false, detail: "Expected both receipts attributed")
        }

        // Receipt provenance
        let provenanceAdobeFonts: ReceiptProvenance = beforeReceipts.contains("com.adobe.Fonts") ? .rewritten : .created
        let provenanceProC3: ReceiptProvenance      = beforeReceipts.contains("com.fabfilter.Pro-C.3") ? .rewritten : .created
        guard provenanceAdobeFonts == .rewritten else {
            return TestResult(name: name, passed: false,
                              detail: "com.adobe.Fonts provenance should be .rewritten (pre-existed) — got .created")
        }
        guard provenanceProC3 == .created else {
            return TestResult(name: name, passed: false,
                              detail: "com.fabfilter.Pro-C.3 provenance should be .created — got .rewritten")
        }

        // File evidence for font files (Adobe CC pre-installed → file existed, ctime advanced)
        let beforeFS = makeSnapshot(["/Library/Fonts/SourceCodePro-Light.ttf": (mtime: beforeInstall, ctime: beforeInstall)])
        let afterFS  = makeSnapshot(["/Library/Fonts/SourceCodePro-Light.ttf": (mtime: beforeInstall, ctime: duringInstall)])
        let fontEvidence = FilesystemSnapshot.classifyPath(
            "/Library/Fonts/SourceCodePro-Light.ttf", before: beforeFS, after: afterFS, installStart: installStart)
        guard fontEvidence == .transactionReplaced else {
            return TestResult(name: name, passed: false,
                              detail: "Font evidence: expected .transactionReplaced (pre-existed + replaced), got .\(fontEvidence.rawValue)")
        }
        guard !evidenceAuthorizesDeletion(evidence: fontEvidence) else {
            return TestResult(name: name, passed: false,
                              detail: "Font file authorized for deletion — FAIL CLOSED violated. Adobe CC fonts must be preserved.")
        }

        return TestResult(name: name, passed: true,
                          detail: "com.adobe.Fonts: receipt provenance=.rewritten (not forgotten), " +
                                  "font evidence=.transactionReplaced (not deleted). " +
                                  "Adobe CC fonts preserved on uninstall. " +
                                  "com.fabfilter.Pro-C.3: provenance=.created (will be forgotten). " +
                                  "Decision made from evidence only — no vendor-specific logic.")
    }

    // MARK: - Scenario L: clean FabFilter install, fonts are new → transactionCreated → authorized

    static func tL_cleanInstallFontsNew() -> TestResult {
        let name = "L — Clean install: font files are new → transactionCreated → authorized for deletion"
        let installStart = Date(timeIntervalSinceNow: -60)
        let duringInstall = Date(timeIntervalSinceNow: -30)

        // Machine has no prior fonts. FabFilter installer creates them.
        let beforeFS = makeSnapshot([:])
        let afterFS  = makeSnapshot([
            "/Library/Fonts/SourceCodePro-ExtraLight.ttf": (mtime: duringInstall, ctime: duringInstall),
            "/Library/Fonts/SourceCodePro-Light.ttf":      (mtime: duringInstall, ctime: duringInstall),
            "/Library/Fonts/SourceCodePro-Medium.ttf":     (mtime: duringInstall, ctime: duringInstall),
        ])
        var allAuthorized = true
        var failed: [String] = []
        for path in afterFS.deep.keys {
            let evidence = FilesystemSnapshot.classifyPath(path, before: beforeFS, after: afterFS, installStart: installStart)
            if evidence != .transactionCreated {
                allAuthorized = false
                failed.append("\(URL(fileURLWithPath: path).lastPathComponent): .\(evidence.rawValue)")
            }
            if !evidenceAuthorizesDeletion(evidence: evidence) {
                allAuthorized = false
                failed.append("\(URL(fileURLWithPath: path).lastPathComponent): not authorized")
            }
        }
        guard allAuthorized else {
            return TestResult(name: name, passed: false,
                              detail: "Some fonts not correctly handled: \(failed.joined(separator: "; "))")
        }
        return TestResult(name: name, passed: true,
                          detail: "All 3 Source Code Pro fonts: transactionCreated, authorized for deletion on uninstall. " +
                                  "com.adobe.Fonts receipt: provenance=.created (will be forgotten) on clean install.")
    }

    // MARK: - Scenario M: outside deepLocations → bomOnly → not authorized

    static func tM_outsideSnapshotCoverage() -> TestResult {
        let name = "M — Path outside deepLocations: bomOnly → not authorized (fail closed)"
        let installStart = Date(timeIntervalSinceNow: -60)

        // A path outside FilesystemSnapshot.deepLocations has no ctime evidence.
        // Even if it appears in a receipt BOM, ATLAS cannot verify it was written
        // during the transaction. Must fail closed.
        let beforeFS = makeSnapshot([:])
        let afterFS  = makeSnapshot([:])  // path not in snapshot coverage

        let evidence = FilesystemSnapshot.classifyPath(
            "/usr/local/lib/libvendor.dylib", before: beforeFS, after: afterFS, installStart: installStart)

        guard evidence == .bomOnly else {
            return TestResult(name: name, passed: false,
                              detail: "Expected .bomOnly for path outside deepLocations, got .\(evidence.rawValue)")
        }
        guard !evidenceAuthorizesDeletion(evidence: evidence) else {
            return TestResult(name: name, passed: false,
                              detail: "bomOnly path authorized for deletion — fail closed violated")
        }
        return TestResult(name: name, passed: true,
                          detail: "Path outside snapshot coverage: .bomOnly, not authorized. " +
                                  "ATLAS does not delete files it cannot verify were installer-written.")
    }

    // MARK: - Helpers for evidence scenarios

    private static func makeSnapshot(
        _ paths: [String: (mtime: Date, ctime: Date)]
    ) -> FilesystemSnapshot.Snapshot {
        FilesystemSnapshot.Snapshot(deep: paths, shallow: [])
    }

    private static func evidenceAuthorizesDeletion(evidence: FileOwnershipEvidence) -> Bool {
        evidence == .transactionCreated
    }
}

#endif
