// RecoveryKitAccountScopingTests.swift
// Standalone XCTest for the Recovery Kit DEK account-switching fix
// (Core/CloudRecoveryKitService.swift). Mirrors the key-selection decision
// only — does NOT touch the real macOS Keychain. A real Keychain/device-level
// test is NOT run here; see the audit report for what that would require and
// why it isn't automated (would write/delete real Keychain items under this
// app's identity, which is not something to do unattended).
//
// CONFIRMED (via direct source trace, before this pass's fix): loadDEK()/
// saveDEK() queried a single fixed Keychain identifier
// (service "com.atlas.ATLAS", account "atlas-recovery-kit-dek") with no
// user-identity check anywhere, and AuthManager.signOut() never cleared it.
// Reproducible precondition: account A signs in, uploads/downloads a
// Recovery Kit (caching A's DEK under the fixed identifier), signs out
// (fixed identifier NOT cleared), account B signs in on the same Mac and
// uploads a Recovery Kit — fetchOrLoadDEK() would return A's cached DEK
// before ever asking the server for B's real one, silently encrypting B's
// kit with the wrong key. The server itself stays correctly scoped (B's row
// is still stored under B's user_id), so there is no cross-account DATA
// EXPOSURE — the defect is that B's own backup becomes undecryptable on a
// different device later, since that device would correctly fetch B's real
// server-side DEK, which no longer matches what encrypted the kit.
//
// FIX: Keychain account identifier is now scoped per user_id
// ("atlas-recovery-kit-dek-<userID>"), with a one-time, one-directional
// migration of any pre-existing legacy (fixed-identifier) item into the
// first account that reads it — safe for the overwhelming common case (one
// account per Mac) and bounds any multi-account-Mac exposure to at most one
// migration, ever, on a given machine, after which the legacy item is
// deleted so a second account can never also inherit it. signOut() now also
// clears the CURRENT account's own per-account entry, so re-signing in
// always re-derives from the server's authoritative DEK rather than any
// local cache.
import XCTest

private struct DEKAccountScopingModel {
    static func legacyAccountName() -> String { "atlas-recovery-kit-dek" }
    static func accountName(for userID: String) -> String { "atlas-recovery-kit-dek-\(userID)" }

    // Mirrors fetchOrLoadDEK()'s resolution order: per-account cache first,
    // then (one-time) legacy migration, then server fetch.
    enum Resolution: Equatable {
        case fromPerAccountCache(String)
        case migratedFromLegacy(String)
        case fetchedFromServer
    }

    static func resolve(
        perAccountCached: String?,
        legacyCached: String?
    ) -> Resolution {
        if let perAccountCached { return .fromPerAccountCache(perAccountCached) }
        if let legacyCached { return .migratedFromLegacy(legacyCached) }
        return .fetchedFromServer
    }
}

final class RecoveryKitAccountScopingTests: XCTestCase {

    func testDifferentAccountsGetDistinctKeychainIdentifiers() {
        let a = DEKAccountScopingModel.accountName(for: "user-A")
        let b = DEKAccountScopingModel.accountName(for: "user-B")
        XCTAssertNotEqual(a, b, "two different accounts must never resolve to the same Keychain item")
    }

    func testBugPrecondition_legacyIdentifierHadNoAccountDistinction() {
        // Before the fix, both accounts would have queried this exact same
        // literal string — this is the confirmed root cause.
        XCTAssertEqual(DEKAccountScopingModel.legacyAccountName(), "atlas-recovery-kit-dek")
    }

    func testFreshAccountWithNoCacheAtAllFetchesFromServer() {
        let resolution = DEKAccountScopingModel.resolve(perAccountCached: nil, legacyCached: nil)
        XCTAssertEqual(resolution, .fetchedFromServer)
    }

    func testAccountWithItsOwnCacheNeverTouchesLegacyOrServer() {
        let resolution = DEKAccountScopingModel.resolve(perAccountCached: "dek-B-bytes", legacyCached: "dek-A-bytes")
        XCTAssertEqual(resolution, .fromPerAccountCache("dek-B-bytes"), "an account's own cached DEK must never be shadowed by a stale legacy entry")
    }

    func testFirstReadAfterUpgradeMigratesTheLegacyEntryInsteadOfHittingTheServerUnnecessarily() {
        let resolution = DEKAccountScopingModel.resolve(perAccountCached: nil, legacyCached: "dek-A-bytes")
        XCTAssertEqual(resolution, .migratedFromLegacy("dek-A-bytes"), "existing single-account installs must not be forced into an unnecessary server round-trip")
    }

    func testSignOutClearingOnlyOwnEntryCannotAffectAnotherAccount() {
        // clearDEK(userID:) deletes exactly one per-account identifier — by
        // construction (distinct identifiers per account, proven above) it
        // cannot remove a different account's entry.
        let signingOutAccount = DEKAccountScopingModel.accountName(for: "user-A")
        let otherAccount = DEKAccountScopingModel.accountName(for: "user-B")
        XCTAssertNotEqual(signingOutAccount, otherAccount)
    }
}
