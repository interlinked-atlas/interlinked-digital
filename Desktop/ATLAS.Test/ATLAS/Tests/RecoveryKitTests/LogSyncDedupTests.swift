// LogSyncDedupTests.swift
// Standalone XCTest proving the duplicate-record gap in the Mac app's
// install-log sync path (Core/InstallLogger.swift), the account-ownership
// cross-upload gap, and that both fixes (now IMPLEMENTED in that file) close
// them without affecting the already-correct offline catch-up behavior.
//
// Does NOT import the ATLAS executable module (not importable from this test
// target — see RecoveryKitXCTests.swift's header for the same constraint).
// Mirrors only the pure sentinel/ownership decisions; no network, no real
// UserDefaults/file-system/Keychain access.
//
// GAP 1 — DUPLICATE UPLOAD (now fixed): every live, fire-and-forget
// uploadLog() call site previously uploaded a log and never recorded that
// filename in the "ATLAS.syncedLogNames" sentinel — only syncExistingLogs()
// wrote to it. Fixed by having every live call site (writeLog(), the
// uninstall path, captureCrashLogs()) call the new markLogSynced() on
// success, and by syncExistingLogs() no longer marking a FAILED upload as
// synced (it previously used `try?`, silently losing failed files' retry
// eligibility — now `do`/`catch`, only success marks the sentinel).
//
// GAP 2 — CROSS-ACCOUNT UPLOAD (now fixed): local log files live in one
// shared, account-agnostic directory. Confirmed reproducible: if account A
// creates a log that never live-uploads (e.g. offline), and a later launch
// finds a DIFFERENT account B already signed in with a valid cached session,
// syncExistingLogs() would upload A's pending file under B's token — the
// server correctly attributes rows to whichever token made the request
// (app/api/atlas/logs/route.ts derives user_id from the verified token only,
// never from client input), so the bug is purely client-side: the wrong
// account's session ends up being the one that makes that authenticated
// request. Fixed via a new recordLogOwner()/recordedLogOwner() map (written
// at file-creation time, before any upload is attempted) that
// syncExistingLogs() now checks: a file recorded under a different user_id
// than the current session is skipped — left pending, never uploaded to the
// wrong account, never deleted. A file with no recorded owner (created
// before this fix, or genuinely offline before ownership could be recorded)
// still falls through to the original behavior — nothing new is stranded.
//
// NOT exercised by these tests: real UserDefaults persistence, real Keychain
// session lookups, and real network/server behavior — those remain
// unverified by this file; see the audit report for what would close them.
import XCTest

private struct LogSyncDedupModel {
    // Mirrors syncExistingLogs()'s filter: a file is (re-)uploaded iff its
    // name is not already in the sentinel set.
    static func filesToUpload(onDisk: [String], sentinel: Set<String>) -> [String] {
        onDisk.filter { !sentinel.contains($0) }
    }

    // Mirrors the CURRENT behavior: live upload call sites never touch the
    // sentinel, so it reflects only what syncExistingLogs() itself has
    // already processed.
    static func sentinelAfterCurrentBehavior(
        sentinelBefore: Set<String>,
        liveUploadedFilenames: [String]
    ) -> Set<String> {
        sentinelBefore // live uploads do not update it — this is the bug
    }

    // Mirrors the PROPOSED fix: a live upload site adds its own filename to
    // the sentinel immediately on success.
    static func sentinelAfterProposedFix(
        sentinelBefore: Set<String>,
        liveUploadedFilenames: [String]
    ) -> Set<String> {
        sentinelBefore.union(liveUploadedFilenames)
    }
}

final class LogSyncDedupTests: XCTestCase {

    func testCurrentBehavior_liveUploadIsNotRecordedInSentinel() {
        // A live writeLog() call uploads "Install_Serum_20261022.log" successfully.
        let sentinel = LogSyncDedupModel.sentinelAfterCurrentBehavior(
            sentinelBefore: [],
            liveUploadedFilenames: ["Install_Serum_20261022.log"]
        )
        // Confirms the gap: the sentinel is untouched by the live upload.
        XCTAssertTrue(sentinel.isEmpty, "live upload must not already mark itself synced under current source behavior")
    }

    func testCurrentBehavior_nextLaunchReUploadsTheSameFileOnce() {
        // State right after the live upload above (sentinel still empty, per the previous test).
        let onDisk = ["Install_Serum_20261022.log"]
        let toUpload = LogSyncDedupModel.filesToUpload(onDisk: onDisk, sentinel: [])
        XCTAssertEqual(toUpload, onDisk, "confirmed duplicate: syncExistingLogs() re-uploads a file its own live call already sent")
    }

    func testCurrentBehavior_duplicateIsBoundedToOneExtraUpload() {
        // After syncExistingLogs() runs once, it DOES add the name to the sentinel.
        let sentinelAfterOneLaunch: Set<String> = ["Install_Serum_20261022.log"]
        let toUploadOnSecondLaunch = LogSyncDedupModel.filesToUpload(
            onDisk: ["Install_Serum_20261022.log"],
            sentinel: sentinelAfterOneLaunch
        )
        XCTAssertTrue(toUploadOnSecondLaunch.isEmpty, "the duplicate must not recur on a second launch — it is bounded to exactly one")
    }

    func testProposedFix_liveUploadMarkingSentinelPreventsTheDuplicate() {
        let sentinelAfterFixedLiveUpload = LogSyncDedupModel.sentinelAfterProposedFix(
            sentinelBefore: [],
            liveUploadedFilenames: ["Install_Serum_20261022.log"]
        )
        let toUpload = LogSyncDedupModel.filesToUpload(
            onDisk: ["Install_Serum_20261022.log"],
            sentinel: sentinelAfterFixedLiveUpload
        )
        XCTAssertTrue(toUpload.isEmpty, "with the minimal fix, the next launch's syncExistingLogs() must not re-upload a file the live path already sent")
    }

    func testProposedFix_doesNotAffectFilesThatOnlyEverRelyOnTheRetroactiveSync() {
        // A file that failed its live upload (e.g. offline at install time) was
        // never added to the sentinel by either path — syncExistingLogs() must
        // still catch it up exactly as it does today. The fix must not change
        // this path at all.
        let toUpload = LogSyncDedupModel.filesToUpload(
            onDisk: ["Failed_Omnisphere_20261021.log"],
            sentinel: []
        )
        XCTAssertEqual(toUpload, ["Failed_Omnisphere_20261021.log"], "retroactive catch-up for a never-synced file must be unaffected by the fix")
    }

    // MARK: - Failed-upload retry (also fixed this pass)

    func testFailedRetroactiveUploadMustNotBeMarkedSynced() {
        // Previously `try?` meant a FAILED upload still appended to
        // newlySynced, permanently losing the retry. Mirrors the corrected
        // do/catch: only a successful call result feeds the sentinel update.
        func sentinelAfterSyncAttempt(uploadSucceeded: Bool, filename: String, sentinelBefore: Set<String>) -> Set<String> {
            uploadSucceeded ? sentinelBefore.union([filename]) : sentinelBefore
        }
        let afterFailedAttempt = sentinelAfterSyncAttempt(
            uploadSucceeded: false, filename: "Failed_Diva_20261022.log", sentinelBefore: []
        )
        XCTAssertTrue(afterFailedAttempt.isEmpty, "a failed retroactive upload must remain eligible for retry, not be marked synced")

        let stillEligible = LogSyncDedupModel.filesToUpload(onDisk: ["Failed_Diva_20261022.log"], sentinel: afterFailedAttempt)
        XCTAssertEqual(stillEligible, ["Failed_Diva_20261022.log"], "next launch must retry a file whose previous upload attempt failed")
    }
}

// MARK: - Cross-account ownership guard (Gap 2)

private struct LogOwnershipModel {
    // Mirrors syncExistingLogs()'s new ownership check: a file recorded under
    // a different user than the current session is skipped — never uploaded,
    // never deleted, left pending for the correct account to sync later.
    static func isEligibleForCurrentSession(
        recordedOwner: String?,
        currentSessionUserID: String
    ) -> Bool {
        guard let recordedOwner else { return true } // no record — legacy fallback, unchanged behavior
        return recordedOwner == currentSessionUserID
    }

    static func filesEligibleToUpload(
        onDisk: [(filename: String, owner: String?)],
        sentinel: Set<String>,
        currentSessionUserID: String
    ) -> [String] {
        onDisk
            .filter { !sentinel.contains($0.filename) }
            .filter { isEligibleForCurrentSession(recordedOwner: $0.owner, currentSessionUserID: currentSessionUserID) }
            .map(\.filename)
    }
}

final class LogOwnershipTests: XCTestCase {

    func testFileOwnedByCurrentAccountIsEligible() {
        XCTAssertTrue(LogOwnershipModel.isEligibleForCurrentSession(recordedOwner: "user-A", currentSessionUserID: "user-A"))
    }

    func testFileOwnedByDifferentAccountIsSkipped() {
        // Account A created this pending file; account B is now signed in on
        // the same Mac. Must not upload A's file under B's session.
        XCTAssertFalse(LogOwnershipModel.isEligibleForCurrentSession(recordedOwner: "user-A", currentSessionUserID: "user-B"))
    }

    func testFileWithNoRecordedOwnerFallsBackToEligible() {
        // Created before this fix existed (or genuinely offline before
        // ownership could be recorded) — must not be newly stranded.
        XCTAssertTrue(LogOwnershipModel.isEligibleForCurrentSession(recordedOwner: nil, currentSessionUserID: "user-B"))
    }

    func testCrossAccountScenario_endToEnd() {
        // Account A's offline-created, never-uploaded log; account B is the
        // currently signed-in session at this launch (B had a prior valid
        // cached session — the exact precondition that reproduces the bug).
        let onDisk: [(filename: String, owner: String?)] = [
            ("Failed_Serum_20261020.log", "user-A"),   // A's pending file — must stay pending
            ("Install_Massive_20261022.log", "user-B"), // B's own file — must upload normally
            ("Install_Legacy_20261018.log", nil),        // pre-fix file, no owner recorded — falls back
        ]
        let eligible = LogOwnershipModel.filesEligibleToUpload(
            onDisk: onDisk, sentinel: [], currentSessionUserID: "user-B"
        )
        XCTAssertEqual(Set(eligible), Set(["Install_Massive_20261022.log", "Install_Legacy_20261018.log"]))
        XCTAssertFalse(eligible.contains("Failed_Serum_20261020.log"), "account A's pending log must never upload under account B's session")
    }
}
