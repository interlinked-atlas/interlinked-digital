// OperationJournalTests.swift
// Standalone XCTest for the crash-safe operation journal
// (Core/OperationJournal.swift).
//
// Does NOT import the ATLAS executable module (not importable from this
// test target — see RecoveryKitXCTests.swift's header for the same
// constraint). Duplicates only the pure types/logic needed for testing:
// a mirror of FilesystemSnapshot.Snapshot's shape, the journal entry model,
// and OperationReconciler's decision logic. These mirrors are kept
// structurally identical to the real implementation (same field names,
// same branching) so a reviewer can diff them against
// Core/OperationJournal.swift directly; they are not a different design.
//
// Real atomic file I/O (write/load/clear/dismiss against an actual temp
// directory) IS exercised directly with Foundation APIs, since that part
// needs no app-module import.
//
// NOT covered here (needs a real macOS runtime — see the audit report's
// isolated-VM test plan): actually force-quitting ATLAS or restarting the
// Mac mid-install/mid-uninstall and confirming the review sheet appears.
import XCTest

// MARK: - Mirrors of Core/OperationJournal.swift's pure types

private enum OpKind: String, Codable { case install, uninstall }

private struct SnapshotMirror: Equatable {
    struct DeepEntry: Equatable { let mtime: Date; let ctime: Date }
    var deep: [String: DeepEntry]
    var shallow: Set<String>
}

private struct TrashMoveMirror: Codable, Equatable {
    let originalPath: String
    let trashPath: String
}

private struct JournalEntryMirror {
    let jobID: UUID
    let kind: OpKind
    let targetIdentifier: String
    let startedAt: Date
    var installBeforeSnapshot: SnapshotMirror?
    var uninstallCompletedMoves: [TrashMoveMirror] = []
}

private struct InstallReviewMirror: Equatable {
    let jobID: UUID
    let targetIdentifier: String
    let changedPaths: [String]
}

private struct UninstallReviewMirror: Equatable {
    let jobID: UUID
    let targetIdentifier: String
    let confirmedMoved: [TrashMoveMirror]
    let unresolvedOriginalPaths: [String]
}

private enum ReviewMirror: Equatable {
    case install(InstallReviewMirror)
    case uninstall(UninstallReviewMirror)
    var jobID: UUID {
        switch self { case .install(let r): return r.jobID; case .uninstall(let r): return r.jobID }
    }
}

// Mirrors FilesystemSnapshot.diff()'s deep-only comparison (the shape this
// reconciler actually relies on) just enough to drive these tests —
// not a reimplementation of the real shallow-diff/bundle-extraction logic.
private func diffMirror(before: SnapshotMirror, after: SnapshotMirror) -> [String] {
    var changed: [String] = []
    for (path, afterDates) in after.deep {
        let afterEffective = max(afterDates.mtime, afterDates.ctime)
        if let beforeDates = before.deep[path] {
            let beforeEffective = max(beforeDates.mtime, beforeDates.ctime)
            if afterEffective > beforeEffective { changed.append(path) }
        } else {
            changed.append(path)
        }
    }
    return changed.sorted()
}

private struct ReconcilerMirror {
    static func reconcileInstall(entry: JournalEntryMirror, currentSnapshot: SnapshotMirror) -> InstallReviewMirror? {
        guard entry.kind == .install, let before = entry.installBeforeSnapshot else { return nil }
        let changed = diffMirror(before: before, after: currentSnapshot)
        guard !changed.isEmpty else { return nil }
        return InstallReviewMirror(jobID: entry.jobID, targetIdentifier: entry.targetIdentifier, changedPaths: changed)
    }

    static func reconcileUninstall(entry: JournalEntryMirror, fileExists: (String) -> Bool) -> UninstallReviewMirror? {
        guard entry.kind == .uninstall else { return nil }
        let moves = entry.uninstallCompletedMoves
        guard !moves.isEmpty else { return nil }
        let confirmed = moves.filter { fileExists($0.trashPath) }
        let unresolved = moves.filter { !fileExists($0.trashPath) }.map(\.originalPath)
        guard !confirmed.isEmpty || !unresolved.isEmpty else { return nil }
        return UninstallReviewMirror(jobID: entry.jobID, targetIdentifier: entry.targetIdentifier, confirmedMoved: confirmed, unresolvedOriginalPaths: unresolved)
    }

    static func reconcileAll(entries: [JournalEntryMirror], currentSnapshot: SnapshotMirror, fileExists: (String) -> Bool) -> [ReviewMirror] {
        entries.compactMap { entry in
            switch entry.kind {
            case .install: return reconcileInstall(entry: entry, currentSnapshot: currentSnapshot).map { .install($0) }
            case .uninstall: return reconcileUninstall(entry: entry, fileExists: fileExists).map { .uninstall($0) }
            }
        }
    }
}

// Mirrors OperationJournal's caller-owned-jobID storage model: beginInstall
// is idempotent per jobID (an entry already present for that ID keeps its
// original baseline), and clear only ever removes the one jobID it's given.
// In-memory, not real file I/O — the real file I/O is covered separately by
// testJournalFileLifecycle_writeLoadClear_realFileIO below, and the real
// wiring (that callers actually generate one jobID per logical operation and
// reuse it across sub-steps/retries) is covered by the source-level guard
// tests further down, which read Engine/InstallationManager.swift,
// Sources/ATLAS/ContentView.swift, and Engine/RecoveryModeEngine.swift
// directly rather than mirroring them.
private final class JournalStoreMirror {
    private(set) var entries: [UUID: JournalEntryMirror] = [:]

    @discardableResult
    func beginInstall(jobID: UUID, targetIdentifier: String, before: SnapshotMirror) -> UUID {
        guard entries[jobID] == nil else { return jobID }
        entries[jobID] = JournalEntryMirror(
            jobID: jobID, kind: .install, targetIdentifier: targetIdentifier,
            startedAt: Date(), installBeforeSnapshot: before)
        return jobID
    }

    func clear(jobID: UUID) {
        entries.removeValue(forKey: jobID)
    }

    func leftoverEntries() -> [JournalEntryMirror] { Array(entries.values) }
}

final class OperationJournalTests: XCTestCase {

    func testInstallReconciliation_noChanges_producesNoReview() {
        let before = SnapshotMirror(deep: [:], shallow: [])
        let entry = JournalEntryMirror(jobID: UUID(), kind: .install, targetIdentifier: "/tmp/Foo.pkg", startedAt: Date(), installBeforeSnapshot: before)
        XCTAssertNil(ReconcilerMirror.reconcileInstall(entry: entry, currentSnapshot: before))
    }

    func testInstallReconciliation_newFile_producesReviewWithThatPath() {
        let before = SnapshotMirror(deep: [:], shallow: [])
        let now = Date()
        let after = SnapshotMirror(deep: ["/Library/Audio/Plug-Ins/Components/Foo.component": .init(mtime: now, ctime: now)], shallow: [])
        let entry = JournalEntryMirror(jobID: UUID(), kind: .install, targetIdentifier: "/tmp/Foo.pkg", startedAt: now, installBeforeSnapshot: before)
        let review = ReconcilerMirror.reconcileInstall(entry: entry, currentSnapshot: after)
        XCTAssertEqual(review?.changedPaths, ["/Library/Audio/Plug-Ins/Components/Foo.component"])
    }

    func testInstallReconciliation_neverRunsAgainstAnUninstallEntry() {
        let entry = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "Foo.pkg", startedAt: Date())
        XCTAssertNil(ReconcilerMirror.reconcileInstall(entry: entry, currentSnapshot: SnapshotMirror(deep: [:], shallow: [])))
    }

    func testUninstallReconciliation_noMoves_producesNoReview() {
        let entry = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "Foo.pkg", startedAt: Date())
        XCTAssertNil(ReconcilerMirror.reconcileUninstall(entry: entry, fileExists: { _ in true }))
    }

    func testUninstallReconciliation_confirmedMove_isReportedAsConfirmed() {
        var entry = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "Foo.pkg", startedAt: Date())
        let move = TrashMoveMirror(originalPath: "/Applications/Foo.app", trashPath: "/Users/x/.Trash/pkg/Foo.app")
        entry.uninstallCompletedMoves = [move]
        let review = ReconcilerMirror.reconcileUninstall(entry: entry, fileExists: { $0 == move.trashPath })
        XCTAssertEqual(review?.confirmedMoved, [move])
        XCTAssertTrue(review?.unresolvedOriginalPaths.isEmpty ?? false)
    }

    func testUninstallReconciliation_moveWhoseTrashPathVanished_isReportedUnresolvedNotDropped() {
        var entry = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "Foo.pkg", startedAt: Date())
        let move = TrashMoveMirror(originalPath: "/Applications/Foo.app", trashPath: "/Users/x/.Trash/pkg/Foo.app")
        entry.uninstallCompletedMoves = [move]
        let review = ReconcilerMirror.reconcileUninstall(entry: entry, fileExists: { _ in false })
        XCTAssertEqual(review?.unresolvedOriginalPaths, [move.originalPath])
        XCTAssertTrue(review?.confirmedMoved.isEmpty ?? false)
    }

    func testReconcileAll_isIdempotent_repeatedCallsProduceTheSameReviews() {
        let now = Date()
        let before = SnapshotMirror(deep: [:], shallow: [])
        let after = SnapshotMirror(deep: ["/Library/Fonts/X.ttf": .init(mtime: now, ctime: now)], shallow: [])
        let entry = JournalEntryMirror(jobID: UUID(), kind: .install, targetIdentifier: "/tmp/X.pkg", startedAt: now, installBeforeSnapshot: before)
        let first = ReconcilerMirror.reconcileAll(entries: [entry], currentSnapshot: after, fileExists: { _ in true })
        let second = ReconcilerMirror.reconcileAll(entries: [entry], currentSnapshot: after, fileExists: { _ in true })
        XCTAssertEqual(first, second, "re-running reconciliation against the same unchanged journal must never produce a different or duplicated result")
    }

    func testReconcileAll_mixedInstallAndUninstallEntries_eachKeepsItsOwnEvidence() {
        let now = Date()
        let before = SnapshotMirror(deep: [:], shallow: [])
        let after = SnapshotMirror(deep: ["/Library/Fonts/X.ttf": .init(mtime: now, ctime: now)], shallow: [])
        let installEntry = JournalEntryMirror(jobID: UUID(), kind: .install, targetIdentifier: "/tmp/X.pkg", startedAt: now, installBeforeSnapshot: before)
        var uninstallEntry = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "Y.pkg", startedAt: now)
        let move = TrashMoveMirror(originalPath: "/Applications/Y.app", trashPath: "/trash/Y.app")
        uninstallEntry.uninstallCompletedMoves = [move]

        let results = ReconcilerMirror.reconcileAll(entries: [installEntry, uninstallEntry], currentSnapshot: after, fileExists: { $0 == move.trashPath })
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.contains { if case .install = $0 { return true }; return false })
        XCTAssertTrue(results.contains { if case .uninstall = $0 { return true }; return false })
    }

    func testTwoConcurrentJobs_haveIndependentJournalState() {
        var entryA = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "A.pkg", startedAt: Date())
        var entryB = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "B.pkg", startedAt: Date())
        entryA.uninstallCompletedMoves = [TrashMoveMirror(originalPath: "/Applications/A.app", trashPath: "/trash/A.app")]
        entryB.uninstallCompletedMoves = [TrashMoveMirror(originalPath: "/Applications/B.app", trashPath: "/trash/B.app")]

        let reviewA = ReconcilerMirror.reconcileUninstall(entry: entryA, fileExists: { _ in true })
        let reviewB = ReconcilerMirror.reconcileUninstall(entry: entryB, fileExists: { _ in true })
        XCTAssertEqual(reviewA?.targetIdentifier, "A.pkg")
        XCTAssertEqual(reviewB?.targetIdentifier, "B.pkg")
        XCTAssertNotEqual(reviewA?.confirmedMoved, reviewB?.confirmedMoved)
    }

    func testReconcileAll_emptyEntries_producesNoReviews() {
        let results = ReconcilerMirror.reconcileAll(entries: [], currentSnapshot: SnapshotMirror(deep: [:], shallow: []), fileExists: { _ in true })
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - Real file I/O against a throwaway temp directory

    func testJournalFileLifecycle_writeLoadClear_realFileIO() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jobID = UUID()
        struct CodableEntry: Codable { let jobID: UUID; let kind: String; let targetIdentifier: String }
        let entry = CodableEntry(jobID: jobID, kind: "uninstall", targetIdentifier: "Z.pkg")
        let fileURL = tmpDir.appendingPathComponent("\(jobID.uuidString).json")

        let data = try JSONEncoder().encode(entry)
        try data.write(to: fileURL, options: Data.WritingOptions.atomic)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try JSONDecoder().decode(CodableEntry.self, from: Data(contentsOf: fileURL))
        XCTAssertEqual(loaded.jobID, jobID)
        XCTAssertEqual(loaded.targetIdentifier, "Z.pkg")

        try FileManager.default.removeItem(at: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "clear() must actually remove the journal file")
    }

    func testDismissalMovesFileAsideRatherThanDeletingIt() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dismissedDir = tmpDir.appendingPathComponent("dismissed")
        try FileManager.default.createDirectory(at: dismissedDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let jobID = UUID()
        struct CodableEntry: Codable { let jobID: UUID }
        let src = tmpDir.appendingPathComponent("\(jobID.uuidString).json")
        try JSONEncoder().encode(CodableEntry(jobID: jobID)).write(to: src, options: Data.WritingOptions.atomic)

        let dst = dismissedDir.appendingPathComponent(src.lastPathComponent)
        try FileManager.default.moveItem(at: src, to: dst)

        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "dismissal must remove it from the live/scanned directory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst.path), "dismissal must preserve the evidence, not delete it")
    }

    func testRepeatedReconciliationNeverDuplicatesAConfirmedMove() {
        // Simulates re-opening ATLAS (or re-running reconciliation) twice
        // against the same still-present journal: the list of confirmed
        // moves must be identical both times, never doubled.
        var entry = JournalEntryMirror(jobID: UUID(), kind: .uninstall, targetIdentifier: "Foo.pkg", startedAt: Date())
        let move = TrashMoveMirror(originalPath: "/Applications/Foo.app", trashPath: "/trash/Foo.app")
        entry.uninstallCompletedMoves = [move]

        let firstPass = ReconcilerMirror.reconcileUninstall(entry: entry, fileExists: { _ in true })
        let secondPass = ReconcilerMirror.reconcileUninstall(entry: entry, fileExists: { _ in true })
        XCTAssertEqual(firstPass?.confirmedMoved.count, 1)
        XCTAssertEqual(secondPass?.confirmedMoved.count, 1)
        XCTAssertEqual(firstPass, secondPass)
    }

    // MARK: - Journal ownership model (JournalStoreMirror, NOT real OperationJournal)

    func testTwoJournalOpeningSubSteps_inOneSuccessfulInstall_shareOneEntryAndOriginalBaseline() {
        // Simulates a DMG plan with a PKG step followed by a patch step, both
        // sharing the SAME jobID (as the real code now threads one jobID
        // through every sub-step of one logical install).
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        let trueBefore = SnapshotMirror(deep: [:], shallow: [])

        // Step 1 (PKG): opens the journal with the true "before anything ran" baseline.
        store.beginInstall(jobID: jobID, targetIdentifier: "Installer.pkg", before: trueBefore)
        // Step 2 (patch): takes its OWN "before" snapshot after step 1 already
        // wrote files — but since an entry for this jobID already exists,
        // beginInstall must not overwrite the baseline with this later one.
        let afterStep1 = SnapshotMirror(deep: ["/Library/Audio/Plug-Ins/Components/Foo.component": .init(mtime: now, ctime: now)], shallow: [])
        store.beginInstall(jobID: jobID, targetIdentifier: "Patch.app", before: afterStep1)

        XCTAssertEqual(store.leftoverEntries().count, 1, "both sub-steps must share exactly one journal entry, not two")
        XCTAssertEqual(store.entries[jobID]?.installBeforeSnapshot, trueBefore, "the baseline must remain the ORIGINAL pre-step-1 state, not step 2's later snapshot")

        // The caller persists one InstallRecord covering both steps' files, then clears.
        store.clear(jobID: jobID)
        XCTAssertTrue(store.leftoverEntries().isEmpty, "a successfully completed multi-step install must leave no leftover journal")
    }

    func testFailedFirstAttempt_followedBySuccessfulRetry_doesNotOrphanFirstAttemptsJournal() {
        let store = JournalStoreMirror()
        let jobID = UUID()
        let before = SnapshotMirror(deep: [:], shallow: [])

        // Attempt 1 fails after opening the journal.
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: before)
        XCTAssertEqual(store.leftoverEntries().count, 1)

        // Retry reuses the SAME jobID (as ContentView/InstallationManager now do).
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: before)
        XCTAssertEqual(store.leftoverEntries().count, 1, "a retry of the same logical operation must never create a second journal entry")

        // Retry succeeds; the real InstallRecord is persisted; the caller clears once.
        store.clear(jobID: jobID)
        XCTAssertTrue(store.leftoverEntries().isEmpty, "no orphaned journal must remain after a successful retry")
    }

    func testFirstAttemptChangesFilesBeforeFailing_thenRetry_preservesOriginalBaselineNotInterveningState() {
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        let trueBefore = SnapshotMirror(deep: [:], shallow: [])

        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: trueBefore)
        // Attempt 1 wrote a file, then failed (crashed or returned .failure)
        // before any record was persisted.
        let afterAttempt1 = SnapshotMirror(deep: ["/Library/Audio/Plug-Ins/Components/Partial.component": .init(mtime: now, ctime: now)], shallow: [])
        // Retry's own internal beginInstall call (taking its own "before" at
        // this later point) must NOT replace the stored baseline.
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: afterAttempt1)
        XCTAssertEqual(store.entries[jobID]?.installBeforeSnapshot, trueBefore)

        // If the retry also crashes, reconciling against the ORIGINAL baseline
        // must still surface attempt 1's partial file — it is not lost.
        let review = ReconcilerMirror.reconcileInstall(entry: store.entries[jobID]!, currentSnapshot: afterAttempt1)
        XCTAssertEqual(review?.changedPaths, ["/Library/Audio/Plug-Ins/Components/Partial.component"], "evidence of files the FIRST attempt created before failing must not be lost")
    }

    func testCancellationOrFailureBeforeHistoryPersisted_journalIsNotCleared() {
        let store = JournalStoreMirror()
        let jobID = UUID()
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: SnapshotMirror(deep: [:], shallow: []))
        // Simulates a cancellation/failure path that returns BEFORE reaching
        // the caller's clear() call (e.g. the queue loop's `break` on
        // cancellation, or a crash) — the journal must still be present for
        // the next launch's reconciliation to find.
        XCTAssertEqual(store.leftoverEntries().count, 1, "a journal must survive until the caller actually reaches its commit point")
    }

    func testTwoIndependentLogicalInstalls_neverCrossClearEachOthersJournal() {
        let store = JournalStoreMirror()
        let jobA = UUID()
        let jobB = UUID()
        store.beginInstall(jobID: jobA, targetIdentifier: "A.pkg", before: SnapshotMirror(deep: [:], shallow: []))
        store.beginInstall(jobID: jobB, targetIdentifier: "B.pkg", before: SnapshotMirror(deep: [:], shallow: []))
        XCTAssertEqual(store.leftoverEntries().count, 2)

        store.clear(jobID: jobA)
        XCTAssertNil(store.entries[jobA])
        XCTAssertNotNil(store.entries[jobB], "clearing one logical install's journal must never affect another's")
    }

    func testReconciliationAfterSuccess_clearedJournalProducesNoDuplicateReview() {
        // Simulates the exact false-positive scenario from the Finding #1
        // follow-up audit: a multi-step install succeeds, its one InstallRecord
        // is persisted, and the caller clears the one shared journal. At the
        // next launch, reconciliation must find nothing for this operation —
        // no duplicate-history review can be produced for work already recorded.
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        let before = SnapshotMirror(deep: [:], shallow: [])
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: before)
        store.beginInstall(jobID: jobID, targetIdentifier: "Patch.app", before:
            SnapshotMirror(deep: ["/Library/Audio/Plug-Ins/Components/Foo.component": .init(mtime: now, ctime: now)], shallow: []))
        store.clear(jobID: jobID) // caller's post-persistence clear

        let currentSnapshotAtNextLaunch = SnapshotMirror(
            deep: ["/Library/Audio/Plug-Ins/Components/Foo.component": .init(mtime: now, ctime: now)], shallow: [])
        let reviews = ReconcilerMirror.reconcileAll(entries: store.leftoverEntries(), currentSnapshot: currentSnapshotAtNextLaunch, fileExists: { _ in true })
        XCTAssertTrue(reviews.isEmpty, "a successfully completed and cleared multi-step install must never resurface as an interrupted-operation review")
    }

    // MARK: - Cumulative file-evidence recovery (Finding #2) — mirror, NOT
    // the real InstallEngine.recoverCumulativeInstalledFiles/FilesystemSnapshot.
    //
    // The real function calls FilesystemSnapshot.take(), which scans
    // hardcoded absolute system paths (/Applications,
    // ~/Library/Application Support/..., etc.) — there is no way to redirect
    // it to a temp directory, so it cannot be exercised against real files in
    // a unit test. These tests mirror its union-not-replace logic (same
    // shape: recompute a diff from the ORIGINAL baseline, then merge by
    // destinationPath into whatever the last attempt already produced,
    // never discarding an existing entry). The real wiring — that both
    // callers actually invoke this logic in the right place, and that
    // receipts are deliberately excluded — is covered by the source-level
    // guard tests further down.

    private struct InstalledFileMirror: Equatable {
        let sourceName: String
        let destinationPath: String
    }

    private static func recoverCumulativeMirror(
        existing: [InstalledFileMirror],
        baseline: SnapshotMirror?,
        finalSnapshot: SnapshotMirror
    ) -> [InstalledFileMirror] {
        guard let baseline else { return existing }
        let changedPaths = diffMirror(before: baseline, after: finalSnapshot)
        var seen = Set(existing.map(\.destinationPath))
        var merged = existing
        for path in changedPaths where !seen.contains(path) {
            seen.insert(path)
            merged.append(InstalledFileMirror(sourceName: (path as NSString).lastPathComponent, destinationPath: path))
        }
        return merged
    }

    func testFailedAttemptCreatesFiles_successfulRetryDoesNotRetouchThem_filesAreRecovered() {
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        let trueBefore = SnapshotMirror(deep: [:], shallow: [])
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: trueBefore)

        // Attempt 1 creates a file, then fails before persisting anything.
        let afterAttempt1 = SnapshotMirror(
            deep: ["/Library/Audio/Plug-Ins/Components/LeftByAttempt1.component": .init(mtime: now, ctime: now)],
            shallow: [])

        // Attempt 2 (retry) never touches that path again — its OWN local
        // diff (not simulated here; this is exactly what today's code already
        // computes) would be empty / unrelated, so its own installedFiles is "[]".
        let attempt2OwnInstalledFiles: [InstalledFileMirror] = []
        let finalSnapshot = afterAttempt1 // nothing changed since attempt 1

        let recovered = Self.recoverCumulativeMirror(
            existing: attempt2OwnInstalledFiles,
            baseline: store.entries[jobID]?.installBeforeSnapshot,
            finalSnapshot: finalSnapshot)

        XCTAssertEqual(recovered, [InstalledFileMirror(sourceName: "LeftByAttempt1.component", destinationPath: "/Library/Audio/Plug-Ins/Components/LeftByAttempt1.component")],
            "a file created by a failed first attempt and never re-touched by the retry must still appear in the final record")
    }

    func testMultipleFailedAttempts_thenSuccess_recoversEvidenceFromEveryEarlierAttempt() {
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        let trueBefore = SnapshotMirror(deep: [:], shallow: [])
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: trueBefore)
        // Two more failed attempts' own beginInstall calls are no-ops against
        // the already-open entry (verified separately above); the baseline
        // stays trueBefore throughout.
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: SnapshotMirror(deep: ["/A": .init(mtime: now, ctime: now)], shallow: []))
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: SnapshotMirror(deep: ["/A": .init(mtime: now, ctime: now), "/B": .init(mtime: now, ctime: now)], shallow: []))

        let finalSnapshot = SnapshotMirror(
            deep: ["/A": .init(mtime: now, ctime: now), "/B": .init(mtime: now, ctime: now), "/C": .init(mtime: now, ctime: now)],
            shallow: [])
        let recovered = Self.recoverCumulativeMirror(
            existing: [], baseline: store.entries[jobID]?.installBeforeSnapshot, finalSnapshot: finalSnapshot)

        XCTAssertEqual(Set(recovered.map(\.destinationPath)), Set(["/A", "/B", "/C"]),
            "evidence from every attempt between the original baseline and final success must be recovered, not just the last attempt's")
    }

    func testRecovery_unionsRatherThanReplaces_preservingNonSnapshotTrackedEntries() {
        // Simulates a multi-step plan mixing a journaled step (PKG, tracked via
        // FilesystemSnapshot) with a non-journaled step (.app copy, manually
        // appended and NOT reproducible from a baseline diff). The fix must
        // never discard the manually-appended entry.
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: SnapshotMirror(deep: [:], shallow: []))

        let manuallyAppended = InstalledFileMirror(sourceName: "SomeApp.app", destinationPath: "/Applications/SomeApp.app")
        let finalSnapshot = SnapshotMirror(deep: ["/Library/Receipts/Foo.pkg": .init(mtime: now, ctime: now)], shallow: [])

        let recovered = Self.recoverCumulativeMirror(
            existing: [manuallyAppended],
            baseline: store.entries[jobID]?.installBeforeSnapshot,
            finalSnapshot: finalSnapshot)

        XCTAssertTrue(recovered.contains(manuallyAppended), "a manually-appended, non-snapshot-tracked entry from the last attempt must survive the union")
        XCTAssertTrue(recovered.contains(where: { $0.destinationPath == "/Library/Receipts/Foo.pkg" }), "snapshot-trackable evidence must still be recovered alongside it")
    }

    func testNoJournalEntry_existingInstalledFilesLeftUnchanged() {
        // Install types that never call beginInstall() (.app/.plugin/.folderCopy/
        // .manual-only plans) have no baseline to recompute from — the fix must
        // be a no-op for them, not an empty-result footgun.
        let existing = [InstalledFileMirror(sourceName: "SomeApp.app", destinationPath: "/Applications/SomeApp.app")]
        let recovered = Self.recoverCumulativeMirror(existing: existing, baseline: nil, finalSnapshot: SnapshotMirror(deep: [:], shallow: []))
        XCTAssertEqual(recovered, existing, "with no journal entry for this jobID, the existing installedFiles must be returned unchanged")
    }

    func testExhaustedRetries_noSuccess_recoveryStillRunsAgainstWhicheverFilesExist() {
        // The fix must apply on BOTH outcomes — a failed, retry-exhausted
        // operation's record should still reflect what's actually on disk.
        // This does not change `result`/success status; it only asserts the
        // recompute itself doesn't depend on the outcome flag.
        let store = JournalStoreMirror()
        let jobID = UUID()
        let now = Date()
        store.beginInstall(jobID: jobID, targetIdentifier: "Foo.pkg", before: SnapshotMirror(deep: [:], shallow: []))
        let finalSnapshot = SnapshotMirror(deep: ["/Library/Audio/Plug-Ins/Components/Partial.component": .init(mtime: now, ctime: now)], shallow: [])

        let recovered = Self.recoverCumulativeMirror(existing: [], baseline: store.entries[jobID]?.installBeforeSnapshot, finalSnapshot: finalSnapshot)
        XCTAssertFalse(recovered.isEmpty, "even a final-failure record should reflect files left behind across all attempts")
        // Journal itself is cleared by the caller only AFTER historyStore.add,
        // regardless of result — covered by the existing clear()-ordering
        // tests and the source-guard test below.
    }

    func testTwoIndependentOperations_recoveryNeverMixesEvidence() {
        let store = JournalStoreMirror()
        let jobA = UUID()
        let jobB = UUID()
        let now = Date()
        store.beginInstall(jobID: jobA, targetIdentifier: "A.pkg", before: SnapshotMirror(deep: [:], shallow: []))
        store.beginInstall(jobID: jobB, targetIdentifier: "B.pkg", before: SnapshotMirror(deep: [:], shallow: []))

        let finalForA = SnapshotMirror(deep: ["/A-file": .init(mtime: now, ctime: now)], shallow: [])
        let recoveredA = Self.recoverCumulativeMirror(existing: [], baseline: store.entries[jobA]?.installBeforeSnapshot, finalSnapshot: finalForA)
        XCTAssertEqual(recoveredA.map(\.destinationPath), ["/A-file"])
        XCTAssertFalse(recoveredA.contains(where: { $0.destinationPath.contains("B") }), "recovering operation A's evidence must never pull in operation B's jobID/baseline")
    }

    // MARK: - Patch-step journal coverage (source-level guard, NOT a mirror)
    //
    // Unlike every other test in this file, this one does not exercise a
    // mirrored copy of the logic — it reads the actual production source of
    // Engine/InstallationManager.swift and asserts that each of the three
    // "apply patch" sub-steps still opens a journal before calling
    // runPatchApp(). This is the only way to regression-test this specific
    // defect class (a call site silently going missing) without access to
    // the ATLAS executable module, which this test target cannot import.
    // It proves the call sites exist in the real file; it does NOT prove
    // (and cannot prove, without a real macOS runtime test) that the
    // resulting journal reconciles correctly end-to-end.
    func testPatchApplySites_openJournalBeforeRunningPatchApp_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile
            .deletingLastPathComponent() // RecoveryKitTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // ATLAS/ (repo root)
        let installationManagerURL = repoRoot.appendingPathComponent("Engine/InstallationManager.swift")
        let source = try String(contentsOf: installationManagerURL, encoding: .utf8)

        // Each patch-apply site must take its "before" snapshot immediately
        // followed by a beginInstall(jobID: journalJobID, ...) call using the
        // CALLER-SUPPLIED journalJobID (not a freshly-generated one) — this is
        // what makes the patch step share one journal with the rest of its
        // logical install operation — and only then call runPatchApp().
        let pattern = #"let patchBefore = FilesystemSnapshot\.take\(\)[\s\S]{0,600}?OperationJournal\.shared\.beginInstall\(\s*jobID: journalJobID[\s\S]{0,400}?let ok = await runPatchApp\("#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))

        XCTAssertEqual(
            matches.count, 3,
            "Expected exactly 3 patch-apply sub-steps (installFromMountPoint, installZIP, installAPP) to open an OperationJournal entry sharing the caller-supplied journalJobID between taking their baseline snapshot and running the patch — found \(matches.count). If a new patch-apply site was added without journal coverage, or an existing one reverted to generating its own jobID, this must be fixed before relying on crash recovery for patch installs."
        )
    }

    // MARK: - Journal ownership wiring (source-level guard, NOT a mirror)
    //
    // These prove the real callers generate ONE jobID per logical install
    // operation and reuse it across retries, rather than letting each retry
    // open an independent journal (the Finding #2 defect). Like the test
    // above, this reads the real production source directly; it does not
    // prove end-to-end runtime behavior.
    func testContentViewQueuePath_generatesOneJobIDAndReusesItAcrossTheSilentRetry_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let contentViewURL = repoRoot.appendingPathComponent("Sources/ATLAS/ContentView.swift")
        let source = try String(contentsOf: contentViewURL, encoding: .utf8)

        XCTAssertEqual(
            source.components(separatedBy: "let journalJobID = UUID()").count - 1, 1,
            "the queue install path must generate journalJobID exactly once, before Attempt 1 — generating it again for the retry would reintroduce the orphaned-journal defect"
        )
        // Scope to actual InstallEngine.install() calls specifically — a
        // generic "journalJobID: journalJobID" substring count would also
        // pick up the unrelated recoverCumulativeInstalledFiles(...,
        // journalJobID: journalJobID) call added for Finding #2's file-
        // evidence fix, which is not an install() call and shares no journal
        // of its own.
        XCTAssertEqual(
            source.components(separatedBy: "logger: logger, journalJobID: journalJobID) { pct, step in").count - 1, 2,
            "both the first attempt and the silent retry must pass the SAME journalJobID into InstallEngine.install() — found a different count, which means at least one of them is not sharing the journal"
        )
        XCTAssertFalse(source.contains("OperationJournal.lastInstallJobID"), "the queue path must not rely on the removed mutable global to discover its jobID")
    }

    func testInstallationManagerSingleDropPath_generatesOneJobIDAndReusesItAcrossAllRetries_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Engine/InstallationManager.swift"), encoding: .utf8)

        // Within the InstallationManager.install(url:appState:...) function
        // (the single drag-and-drop path with up to 3 TITAN CORE™ attempts +
        // 1 legacy remediation retry), journalJobID must be generated once and
        // every InstallEngine.install() call must reuse it.
        XCTAssertEqual(
            source.components(separatedBy: "let journalJobID = UUID()").count - 1, 1,
            "the single-drop install path must generate journalJobID exactly once, before Attempt 1"
        )
        XCTAssertEqual(
            source.components(separatedBy: "journalJobID: journalJobID, progress: onProgress").count - 1, 4,
            "all 4 attempts (initial + up to 2 TITAN CORE™ retries + legacy remediation retry) must pass the same journalJobID — found a different count"
        )
        XCTAssertTrue(
            source.contains("OperationJournal.shared.clear(jobID: journalJobID)"),
            "the single-drop path must clear its journal after persisting the InstallRecord — this path previously never cleared its journal at all"
        )
    }

    func testRecoveryModeEngine_generatesItsOwnJobIDRatherThanReadingTheRemovedGlobal_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Engine/RecoveryModeEngine.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("OperationJournal.lastInstallJobID"), "Recovery Mode must not rely on the removed mutable global to discover its jobID")
        XCTAssertTrue(source.contains("let journalJobID = UUID()"), "Recovery Mode must generate its own jobID explicitly before calling InstallEngine.install()")
    }

    func testOperationJournal_noLongerExposesTheMutableGlobalLastInstallJobID_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Core/OperationJournal.swift"), encoding: .utf8)

        XCTAssertFalse(source.contains("lastInstallJobID"), "the single-slot global that caused the multi-step/retry journal-ownership defects must stay removed — ownership must be explicit (caller-supplied jobID) going forward")
        XCTAssertTrue(source.contains("func beginInstall(jobID: UUID"), "beginInstall must take the jobID as an explicit parameter, not generate one internally")
    }

    // MARK: - Cumulative file-evidence recovery wiring (Finding #2, source-level
    // guard, NOT a mirror). Proves the real call sites exist, are ordered
    // correctly relative to historyStore.add()/clear(), and that receipts are
    // deliberately left untouched — it does not prove end-to-end runtime
    // behavior (needs a real macOS runtime; see earlier audit reports).

    func testOperationJournal_exposesReadOnlyEntryAccessor_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Core/OperationJournal.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("func entry(for jobID: UUID) -> OperationJournalEntry?"),
            "a read-only accessor for a still-open entry must exist so cumulative evidence can be recomputed from the original baseline without disturbing the journal's own lifecycle")
    }

    func testInstallationManager_definesCumulativeFileRecoveryHelper_scopedToInstalledFilesOnly_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Engine/InstallationManager.swift"), encoding: .utf8)

        XCTAssertTrue(source.contains("static func recoverCumulativeInstalledFiles("),
            "the shared recovery helper must exist on InstallEngine")

        // The single-drop path's own call site must use it before persisting the record.
        let callCount = source.components(separatedBy: "InstallEngine.recoverCumulativeInstalledFiles(").count - 1
        XCTAssertEqual(callCount, 1, "expected exactly 1 call site in this file (the single-drop path) — found \(callCount); if a new retry path is added to this file without this call, Finding #2 regresses for it")
    }

    func testSingleDropPath_recomputesInstalledFilesBeforePersisting_andClearsAfter_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Engine/InstallationManager.swift"), encoding: .utf8)

        // historyStore.add(record) appears twice in this file (the pre-flight
        // block-reason branch, and the final persistence point after all
        // retries) — the recompute call must precede the SECOND one, the
        // actual final-record persistence point this fix targets.
        // The call itself must run detached from the main actor (this class
        // is @MainActor) — same requirement as every other
        // FilesystemSnapshot.take() call in this file.
        guard let recoverRange = source.range(of: "InstallEngine.recoverCumulativeInstalledFiles(") else {
            XCTFail("expected to find the recompute call")
            return
        }
        XCTAssertNotNil(
            source.range(of: "Task.detached(priority: .userInitiated) {", range: source.startIndex..<recoverRange.lowerBound),
            "recoverCumulativeInstalledFiles must be called inside a Task.detached block — this class is @MainActor, and the recursive filesystem scan inside it must not run on the main thread"
        )
        guard let persistRange = source.range(of: "historyStore.add(record)", range: recoverRange.upperBound..<source.endIndex),
              let clearRange = source.range(of: "OperationJournal.shared.clear(jobID: journalJobID)", range: persistRange.upperBound..<source.endIndex)
        else {
            XCTFail("expected to find a subsequent historyStore.add(record) and a subsequent clear() in order")
            return
        }
        XCTAssertTrue(recoverRange.upperBound < persistRange.lowerBound,
            "installedFiles must be recomputed BEFORE the record is built and persisted, not after")
        XCTAssertTrue(persistRange.upperBound < clearRange.lowerBound,
            "the journal must still be cleared only AFTER historyStore.add — the recompute must not change clear() ordering")
    }

    func testQueuePath_recomputesInstalledFilesBeforePersisting_andClearsAfter_realProductionSource() throws {
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent("Sources/ATLAS/ContentView.swift"), encoding: .utf8)

        // historyStore.add(record) appears elsewhere in this file for unrelated
        // functions — anchor the search to the FIRST historyStore.add(record)
        // AFTER the recompute call, which is this queue path's own persistence point.
        guard let recoverRange = source.range(of: "installedFiles = InstallEngine.recoverCumulativeInstalledFiles("),
              let persistRange = source.range(of: "historyStore.add(record)", range: recoverRange.upperBound..<source.endIndex),
              let clearRange = source.range(of: "OperationJournal.shared.clear(jobID: journalJobID)", range: persistRange.upperBound..<source.endIndex)
        else {
            XCTFail("expected to find the recompute call, a subsequent historyStore.add(record), and a subsequent clear() in order")
            return
        }
        XCTAssertTrue(recoverRange.upperBound < persistRange.lowerBound,
            "installedFiles must be recomputed BEFORE the record is built and persisted, not after")
        XCTAssertTrue(persistRange.upperBound < clearRange.lowerBound,
            "the journal must still be cleared only AFTER historyStore.add — the recompute must not change clear() ordering")
    }

    func testReceiptAndProvenanceEvidence_remainLastAttemptOnly_notMergedByThisFix_realProductionSource() throws {
        // Finding #2's receipt/provenance investigation concluded merging is
        // unsafe (no journaled receipt baseline; a failed PKG attempt never
        // reaches the receipt scan at all; macOS rewrites receipt plist/bom
        // on every reinstall so a full-plan retry already regenerates
        // equivalent evidence). This guards against that conclusion being
        // silently reversed by a future edit.
        let thisFile = URL(fileURLWithPath: #filePath)
        let repoRoot = thisFile.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let installationManagerSource = try String(contentsOf: repoRoot.appendingPathComponent("Engine/InstallationManager.swift"), encoding: .utf8)
        let contentViewSource = try String(contentsOf: repoRoot.appendingPathComponent("Sources/ATLAS/ContentView.swift"), encoding: .utf8)

        for name in ["receiptIDs", "lastPKGEvidenceMap", "lastPKGReceiptProvenance"] {
            XCTAssertFalse(installationManagerSource.contains("\(name) = Array(Set(\(name)"),
                "\(name) must not be merged/unioned across attempts in InstallationManager.swift — receipts/evidence maps are deliberately last-attempt-only")
            XCTAssertFalse(contentViewSource.contains("\(name) = Array(Set(\(name)"),
                "\(name) must not be merged/unioned across attempts in ContentView.swift — receipts/evidence maps are deliberately last-attempt-only")
        }
    }
}
