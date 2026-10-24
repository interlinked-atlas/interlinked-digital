import Foundation
import SwiftUI

// MARK: - Crash-safe operation journal
//
// Closes the confirmed gap in both the install and uninstall paths: history
// records / trash manifests are persisted only once, at the END of an
// operation — a crash, force-quit, or restart during the operation leaves
// real filesystem changes with no durable ATLAS-side record at all.
//
// This journal is a lightweight, additive side-channel: one atomically
// written JSON file per in-flight operation, keyed by a stable job UUID,
// stored under the same Application Support directory HistoryStore already
// uses (same `.atomic` write discipline it already relies on). It never
// replaces InstallRecord/TrashRecord — it only preserves enough evidence to
// reconstruct what the existing FilesystemSnapshot/RollbackEngine logic
// would have produced, if ATLAS is able to ask again after a crash.
//
// Safety invariants, enforced by every function below:
//   - A Mac with no journal files behaves identically to before this file
//     existed — reconciliation only ever runs against files that exist.
//   - Nothing here ever claims ownership of a file, writes an InstallRecord,
//     moves a file, or deletes anything. It is purely advisory: produce
//     evidence, let the existing (or a new, explicit) confirmation step
//     decide.
//   - Every write is atomic (temp + rename), matching HistoryStore.save().
enum OperationKind: String, Codable {
    case install
    case uninstall
}

// Codable mirror of FilesystemSnapshot.Snapshot — that type's tuple values
// aren't directly Codable, so this is a 1:1 translation, not a new model.
struct CodableFilesystemSnapshot: Codable {
    struct DeepEntry: Codable { let mtime: Date; let ctime: Date }
    var deep: [String: DeepEntry]
    var shallow: [String]

    init(_ snapshot: FilesystemSnapshot.Snapshot) {
        deep = snapshot.deep.mapValues { DeepEntry(mtime: $0.mtime, ctime: $0.ctime) }
        shallow = Array(snapshot.shallow)
    }

    func toSnapshot() -> FilesystemSnapshot.Snapshot {
        FilesystemSnapshot.Snapshot(
            deep: deep.mapValues { (mtime: $0.mtime, ctime: $0.ctime) },
            shallow: Set(shallow)
        )
    }
}

struct JournaledTrashMove: Codable, Equatable {
    let originalPath: String
    let trashPath: String
}

struct OperationJournalEntry: Codable {
    let jobID: UUID
    let kind: OperationKind
    let targetIdentifier: String   // install: the installer file's path. uninstall: the product's fileName.
    let startedAt: Date

    // Install only — the baseline snapshot needed to re-run the diff later.
    var installBeforeSnapshot: CodableFilesystemSnapshot?

    // Uninstall only — appended to after EACH individually-verified move,
    // so a crash mid-loop still leaves every already-completed move
    // discoverable, not just the ones before the crash happened to land on
    // a manifest write (which previously only happened once, at the end).
    var uninstallCompletedMoves: [JournaledTrashMove] = []
}

final class OperationJournal {
    static let shared = OperationJournal()
    private init() {}

    private lazy var dir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/in-progress")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private lazy var dismissedDir: URL = {
        let d = dir.appendingPathComponent("dismissed")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func url(for jobID: UUID) -> URL { dir.appendingPathComponent("\(jobID.uuidString).json") }

    private func save(_ entry: OperationJournalEntry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url(for: entry.jobID), options: .atomic)
    }

    private func load(_ jobID: UUID) -> OperationJournalEntry? {
        guard let data = try? Data(contentsOf: url(for: jobID)) else { return nil }
        return try? JSONDecoder().decode(OperationJournalEntry.self, from: data)
    }

    // Public, read-only peek at a still-open entry — used to recover the
    // ORIGINAL baseline for a logical operation that has already run one or
    // more failed attempts, so cumulative filesystem evidence can be
    // recomputed from the true starting point rather than a later attempt's
    // own (already-contaminated-by-earlier-attempts) local snapshot. Never
    // mutates anything — callers still clear() at their own existing
    // persistence point.
    func entry(for jobID: UUID) -> OperationJournalEntry? {
        load(jobID)
    }

    // MARK: - Install lifecycle

    // The caller owns jobID for the entire logical install operation — one ID
    // generated once, before the first attempt, reused across every sub-step
    // (a multi-step plan's PKG/patch/managedInstall steps) AND across a retry
    // of the whole operation (the first attempt's failure does not get a new
    // ID; the caller passes the same one into the retry). This makes ownership
    // explicit rather than inferred from a mutable global, and mirrors the
    // uninstall side's existing pattern (RollbackEngine generates its own jobID
    // and threads it through beginUninstall/recordUninstallMove/clear).
    //
    // Idempotent per jobID: if an entry already exists (an earlier sub-step or
    // a prior attempt of the SAME logical operation already opened it), this
    // intentionally does nothing further — the original baseline (state before
    // the very first sub-step/attempt) is preserved, since that is the correct
    // "before" state for reconciling everything the whole logical operation
    // did, not just its most recent sub-step or most recent attempt.
    @discardableResult
    func beginInstall(jobID: UUID, targetIdentifier: String, before: FilesystemSnapshot.Snapshot) -> UUID {
        guard load(jobID) == nil else { return jobID }
        save(OperationJournalEntry(
            jobID: jobID, kind: .install, targetIdentifier: targetIdentifier,
            startedAt: Date(), installBeforeSnapshot: CodableFilesystemSnapshot(before)
        ))
        return jobID
    }

    // MARK: - Uninstall lifecycle

    func beginUninstall(jobID: UUID, targetIdentifier: String) {
        save(OperationJournalEntry(jobID: jobID, kind: .uninstall, targetIdentifier: targetIdentifier, startedAt: Date()))
    }

    // Called after EACH individually-verified trash move — not batched —
    // so the journal always reflects exactly what has actually happened so
    // far, even if the next move never completes.
    func recordUninstallMove(jobID: UUID, move: JournaledTrashMove) {
        guard var entry = load(jobID) else { return }
        entry.uninstallCompletedMoves.append(move)
        save(entry)
    }

    // MARK: - Common lifecycle

    // Call only after the real durable record (InstallRecord in HistoryStore,
    // or the uninstall's TrashManifest) has been successfully persisted.
    // Idempotent — clearing an already-cleared or never-existent jobID is a
    // silent no-op, so a retry or a defensive double-call is always safe.
    func clear(jobID: UUID) {
        try? FileManager.default.removeItem(at: url(for: jobID))
    }

    // MARK: - Startup reconciliation

    // All journals still present at launch — i.e. operations that started
    // but never reached their own `clear()` call. Pure read, no side
    // effects, safe to call on every launch regardless of outcome.
    func leftoverEntries() -> [OperationJournalEntry] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> OperationJournalEntry? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(OperationJournalEntry.self, from: data)
            }
    }

    // Dismissal preserves the evidence rather than destroying it — moves the
    // journal file aside into a `dismissed/` subfolder instead of deleting
    // it, so it is never shown again (leftoverEntries() only scans the live
    // directory) but remains available if ever needed for support/diagnosis.
    func dismiss(jobID: UUID) {
        let src = url(for: jobID)
        let dst = dismissedDir.appendingPathComponent(src.lastPathComponent)
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.moveItem(at: src, to: dst)
    }
}

// MARK: - Reconciliation (pure — no filesystem access of its own beyond what's injected)

struct PendingInstallReview: Equatable {
    let jobID: UUID
    let targetIdentifier: String
    let changedPaths: [String]
}

struct PendingUninstallReview: Equatable {
    let jobID: UUID
    let targetIdentifier: String
    let confirmedMoved: [JournaledTrashMove]
    let unresolvedOriginalPaths: [String]
}

enum PendingReview: Equatable {
    case install(PendingInstallReview)
    case uninstall(PendingUninstallReview)

    var jobID: UUID {
        switch self {
        case .install(let r): return r.jobID
        case .uninstall(let r): return r.jobID
        }
    }
}

// Pure decision logic, deliberately separated from OperationJournal's own
// file I/O so it can be unit-tested without touching the real filesystem.
// Never claims ownership outright — every branch either finds nothing worth
// surfacing (safe to silently clear) or returns evidence for the review UI,
// never a destructive or ownership-claiming action.
struct OperationReconciler {

    // Install: re-runs the EXISTING, already-audited diff logic against the
    // journal's baseline. A diff with no changes means nothing detectable
    // happened — safe to clear with no review. A non-empty diff is NOT
    // auto-imported into HistoryStore; it is only ever returned as evidence.
    static func reconcileInstall(
        entry: OperationJournalEntry,
        currentSnapshot: FilesystemSnapshot.Snapshot
    ) -> PendingInstallReview? {
        guard entry.kind == .install, let before = entry.installBeforeSnapshot?.toSnapshot() else { return nil }
        let changed = FilesystemSnapshot.diff(before: before, after: currentSnapshot)
        guard !changed.isEmpty else { return nil }
        return PendingInstallReview(jobID: entry.jobID, targetIdentifier: entry.targetIdentifier, changedPaths: changed)
    }

    // Uninstall: for each move the journal recorded as completed, checks
    // whether the trash destination still exists. A move whose destination
    // can no longer be confirmed is NOT silently dropped (it might mean the
    // user already dealt with it, or it might mean evidence was lost) — it
    // is surfaced separately as unresolved, never assumed either way.
    static func reconcileUninstall(
        entry: OperationJournalEntry,
        fileExists: (String) -> Bool
    ) -> PendingUninstallReview? {
        guard entry.kind == .uninstall else { return nil }
        let moves = entry.uninstallCompletedMoves
        guard !moves.isEmpty else { return nil }
        let confirmed = moves.filter { fileExists($0.trashPath) }
        let unresolvedOriginals = moves.filter { !fileExists($0.trashPath) }.map(\.originalPath)
        guard !confirmed.isEmpty || !unresolvedOriginals.isEmpty else { return nil }
        return PendingUninstallReview(
            jobID: entry.jobID, targetIdentifier: entry.targetIdentifier,
            confirmedMoved: confirmed, unresolvedOriginalPaths: unresolvedOriginals
        )
    }

    // Top-level entry point startup calls. Repeated calls (e.g. the user
    // reopens ATLAS without resolving a prior review) must be idempotent —
    // they only ever re-derive the same evidence from the still-present
    // journal + current filesystem state, never repeat a destructive action
    // (there is none to repeat; this function never mutates anything).
    static func reconcileAll(
        entries: [OperationJournalEntry],
        currentSnapshot: FilesystemSnapshot.Snapshot,
        fileExists: (String) -> Bool
    ) -> [PendingReview] {
        entries.compactMap { entry in
            switch entry.kind {
            case .install:
                return reconcileInstall(entry: entry, currentSnapshot: currentSnapshot).map { .install($0) }
            case .uninstall:
                return reconcileUninstall(entry: entry, fileExists: fileExists).map { .uninstall($0) }
            }
        }
    }
}

// MARK: - Startup review store (drives the review sheet, never acts alone)

@MainActor
final class PendingReviewStore: ObservableObject {
    static let shared = PendingReviewStore()
    private init() {}

    @Published private(set) var reviews: [PendingReview] = []

    // Called once at launch. Pure in the sense that it only ever reads the
    // filesystem to gather evidence — it never writes an InstallRecord,
    // moves a file, or deletes anything. Safe to call repeatedly (e.g. a
    // future "re-check" action): it always re-derives from whatever
    // journals still exist, so it can never duplicate or repeat an action
    // because it never takes one.
    func reconcileAtLaunch() {
        let entries = OperationJournal.shared.leftoverEntries()
        guard !entries.isEmpty else { reviews = []; return }
        let currentSnapshot = FilesystemSnapshot.take()
        reviews = OperationReconciler.reconcileAll(
            entries: entries,
            currentSnapshot: currentSnapshot,
            fileExists: { FileManager.default.fileExists(atPath: $0) }
        )
        // Any leftover journal that produced NO review (diff empty / no
        // moves to report) represents an interrupted operation that,
        // on inspection, left no detectable trace — safe to clear outright,
        // since there is nothing to show the user and nothing was claimed.
        let reviewedJobIDs = Set(reviews.map(\.jobID))
        for entry in entries where !reviewedJobIDs.contains(entry.jobID) {
            OperationJournal.shared.clear(jobID: entry.jobID)
        }
    }

    // User explicitly confirmed an install review — adds the real
    // InstallRecord now, under the user's own direction, never silently.
    func confirmInstall(_ review: PendingInstallReview, store: HistoryStore) {
        let installedFiles = FilesystemSnapshot.buildInstalledFiles(changedPaths: review.changedPaths)
        let record = InstallRecord(
            id: UUID(),
            date: Date(),
            fileName: URL(fileURLWithPath: review.targetIdentifier).lastPathComponent,
            fileType: URL(fileURLWithPath: review.targetIdentifier).pathExtension,
            installedFiles: installedFiles,
            pkgReceiptIDs: [],
            status: .success,
            // No ordinary install log exists for a reconciled operation (ATLAS
            // never reached its normal logging step before the crash) —
            // named distinctly so it's never confused with a real log file.
            logFileName: "recovered-after-interruption-\(review.jobID.uuidString).log"
        )
        store.add(record)
        OperationJournal.shared.clear(jobID: review.jobID)
        reviews.removeAll { $0.jobID == review.jobID }
    }

    // User explicitly dismissed without importing — evidence is preserved
    // (moved aside, not deleted; see OperationJournal.dismiss()), never
    // shown again, nothing on disk is touched.
    func dismiss(_ review: PendingReview) {
        OperationJournal.shared.dismiss(jobID: review.jobID)
        reviews.removeAll { $0.jobID == review.jobID }
    }
}
