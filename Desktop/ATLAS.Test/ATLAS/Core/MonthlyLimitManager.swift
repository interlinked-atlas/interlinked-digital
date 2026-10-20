import Foundation

@MainActor
final class MonthlyLimitManager: ObservableObject {
    static let shared = MonthlyLimitManager()
    private init() { load() }

    // MARK: - Limits
    /// Flat 25/month for every plan tier, per registered device. Intentional —
    /// not Pro/Advanced/Atlas-specific.
    static let atlasMonthlyLimit = 25

    // MARK: - State
    @Published private(set) var installsThisPeriod: Int = 0
    @Published private(set) var periodStart:        Date = Date()
    @Published private(set) var today:              Date = Date()
    @Published private(set) var pendingURLs:        [URL] = []

    /// True once the server has confirmed usage for the CURRENT local user + device +
    /// period. Purely a display/offline-policy signal — never itself the enforcement
    /// authority. Reset on sign-out and on period rollover so a stale confirmation from
    /// a previous account/device/period can never be mistaken for a trustworthy one.
    @Published private(set) var hasServerConfirmedThisPeriod: Bool = false

    // MARK: - Derived limits

    var currentLimit: Int { Self.atlasMonthlyLimit }

    // MARK: - Lock state

    /// Monthly cap hit — resets at the start of each calendar month, regardless of
    /// plan or billing cadence.
    var isMonthlyLocked: Bool {
        guard !AuthManager.shared.isAdmin else { return false }
        return installsThisPeriod >= currentLimit && timeUntilMonthlyReset > 0
    }

    /// isLocked — only monthly cap applies (no daily limit)
    var isLocked: Bool { isMonthlyLocked }

    /// Strict offline policy: true when we do NOT have a trustworthy, server-confirmed
    /// basis for the current local count (never synced this period, or synced under a
    /// different user/device identity). Callers should treat this the same as "locked"
    /// when the server cannot be reached — see checkOfflineFallback().
    var lacksTrustworthyLocalState: Bool { !hasServerConfirmedThisPeriod }

    // MARK: - Remaining

    var remaining: Int {
        refreshIfExpired()
        return max(0, currentLimit - installsThisPeriod)
    }

    var hasPendingFiles: Bool { !pendingURLs.isEmpty }

    // MARK: - Countdowns

    var timeUntilMonthlyReset: TimeInterval {
        max(0, nextMonthlyResetDate.timeIntervalSinceNow)
    }

    var timeUntilReset: TimeInterval { timeUntilMonthlyReset }

    var isLockedByMonthly: Bool { isMonthlyLocked }

    // MARK: - Next reset date
    // Mirrors the server's atlas_period_start/atlas_next_period_start exactly
    // (display only — the server remains the sole enforcement authority via
    // reserve_install_slot/confirm_install_reservation):
    //   resets on billingAnchorDay each month, clamped to the last valid day
    //   of a short month (anchor 31 -> Feb 28/29, Apr 30, etc.)

    /// Clamps `day` to the last valid day of the given month — e.g. day 31 in
    /// February becomes the 28th (or 29th in a leap year).
    private func clampedAnchorDate(year: Int, month: Int, day: Int, calendar cal: Calendar) -> Date {
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let firstOfMonth = cal.date(from: comps) else { return Date() }
        let validRange = cal.range(of: .day, in: .month, for: firstOfMonth) ?? (1..<32)
        comps.day = min(day, validRange.count)
        return cal.date(from: comps) ?? firstOfMonth
    }

    private func billingPeriodStart(asOf now: Date) -> Date {
        let profile  = AuthManager.shared.profile
        let cal      = Calendar.current

        let anchorDay = profile?.billingAnchorDay ?? 1
        let comps = cal.dateComponents([.year, .month], from: now)
        guard let year = comps.year, let month = comps.month else { return now }
        let thisMonthAnchor = clampedAnchorDate(year: year, month: month, day: anchorDay, calendar: cal)
        if thisMonthAnchor <= now { return thisMonthAnchor }

        guard let prevMonthDate = cal.date(byAdding: .month, value: -1, to: thisMonthAnchor) else { return thisMonthAnchor }
        let prevComps = cal.dateComponents([.year, .month], from: prevMonthDate)
        guard let prevYear = prevComps.year, let prevMonth = prevComps.month else { return thisMonthAnchor }
        return clampedAnchorDate(year: prevYear, month: prevMonth, day: anchorDay, calendar: cal)
    }

    private func nextBillingPeriodStart(after start: Date) -> Date {
        let profile  = AuthManager.shared.profile
        let cal      = Calendar.current

        let anchorDay = profile?.billingAnchorDay ?? 1
        guard let nextMonthDate = cal.date(byAdding: .month, value: 1, to: start) else { return start }
        let comps = cal.dateComponents([.year, .month], from: nextMonthDate)
        guard let year = comps.year, let month = comps.month else { return nextMonthDate }
        return clampedAnchorDate(year: year, month: month, day: anchorDay, calendar: cal)
    }

    var nextMonthlyResetDate: Date {
        nextBillingPeriodStart(after: periodStart)
    }

    // MARK: - Public API

    /// Atomic reserve — call BEFORE starting any product install. The authoritative
    /// capacity decision happens server-side, in the same transaction as the
    /// reservation's creation (see reserve_install_slot). Returns the reservation ID
    /// to pass to confirmSuccess(reservationID:)/releaseReservation(reservationID:)
    /// once the install's outcome is known.
    /// ATLAS policy (2026-10-19): zero offline installs. If the server cannot be
    /// reached or cannot verify the subscription, this always denies — a previously
    /// confirmed count or remaining quota is never a substitute for a current,
    /// successful server authorization. See checkOfflineFallback().
    func reserveSlot() async -> (allowed: Bool, reservationID: UUID?, reason: String?) {
        guard !AuthManager.shared.isAdmin else { return (true, nil, nil) }
        guard let token = await AuthManager.shared.currentToken() else {
            let fallback = checkOfflineFallback()
            return (fallback.allowed, nil, fallback.reason)
        }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/check-install") else {
            let fallback = checkOfflineFallback()
            return (fallback.allowed, nil, fallback.reason)
        }
        let reservationID = UUID()
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        struct Body: Encodable { let hardware_uuid: String; let reservation_id: String }
        req.httpBody = try? JSONEncoder().encode(Body(hardware_uuid: atlasHardwareUUID(), reservation_id: reservationID.uuidString))

        struct Result: Decodable {
            let allowed: Bool
            let reason: String?
            let monthly_used: Int?
        }

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                let fallback = checkOfflineFallback()
                return (fallback.allowed, nil, fallback.reason)
            }

            // P1-4: the server reached us but explicitly could not verify
            // (fail-closed 503, reason "server_error") is a DISTINCT state
            // from "network unreachable" (falls to offline policy below) and
            // from a genuine denial like "monthly_limit"/"not_entitled". Do
            // not conflate it with either — surface it as-is so the UI can
            // say "couldn't verify — please retry" specifically.
            if http.statusCode == 503,
               let result = try? JSONDecoder().decode(Result.self, from: data),
               result.reason == "server_error" {
                return (false, nil, "server_error")
            }

            guard http.statusCode == 200 else {
                let fallback = checkOfflineFallback()
                return (fallback.allowed, nil, fallback.reason)
            }

            let result = try JSONDecoder().decode(Result.self, from: data)
            if let mu = result.monthly_used {
                installsThisPeriod = mu
                hasServerConfirmedThisPeriod = true
                save()
            }
            return (result.allowed, result.allowed ? reservationID : nil, result.reason)
        } catch {
            // Genuinely could not reach the server at all — this remains the
            // existing strict offline policy, distinct from a reached-but-
            // erroring server above.
            let fallback = checkOfflineFallback()
            return (fallback.allowed, nil, fallback.reason)
        }
    }

    /// ATLAS policy (2026-10-19): zero offline installs, period. A previously
    /// server-confirmed count and unused quota are NOT a basis for authorizing a
    /// paid operation without a current, successful server check — a subscription
    /// could have been cancelled or lapsed since that last confirmation. Always
    /// fail closed when the server is unreachable or did not return a verdict.
    private func checkOfflineFallback() -> (allowed: Bool, reason: String?) {
        return (false, "offline_entitlement_unknown")
    }

    /// Call ONLY after a product install (started via reserveSlot()) has genuinely,
    /// confirmedly succeeded. Atomically transitions the reservation
    /// reserved -> confirmed and increments usage exactly once — the ONLY thing
    /// that consumes usage. Idempotent: safe to retry with the same reservationID
    /// (a lost response can be retried without double-incrementing).
    func confirmSuccess(reservationID: UUID) async {
        guard !AuthManager.shared.isAdmin else { return }
        guard let token = await AuthManager.shared.currentToken() else { return }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/install-count") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let reservation_id: String; let action: String }
        req.httpBody = try? JSONEncoder().encode(Body(reservation_id: reservationID.uuidString, action: "confirm"))

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            return
        }
        struct Result: Decodable { let used: Int? }
        if let result = try? JSONDecoder().decode(Result.self, from: data), let used = result.used {
            installsThisPeriod = used
            hasServerConfirmedThisPeriod = true
            save()
        }
    }

    /// Call when a product install started via reserveSlot() fails, is cancelled,
    /// or is skipped before completing successfully. Frees the reservation without
    /// consuming usage. Safe to call more than once (idempotent no-op on retry).
    func releaseReservation(reservationID: UUID) async {
        guard !AuthManager.shared.isAdmin else { return }
        guard let token = await AuthManager.shared.currentToken() else { return }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/install-count") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable { let reservation_id: String; let action: String }
        req.httpBody = try? JSONEncoder().encode(Body(reservation_id: reservationID.uuidString, action: "release"))
        _ = try? await URLSession.shared.data(for: req)
    }

    func setPending(_ urls: [URL]) {
        pendingURLs = urls
        savePending()
    }

    func clearPending() {
        pendingURLs = []
        savePending()
    }

    func refreshAfterProfileLoad() {
        refreshIfExpired()
    }

    /// No-op, kept temporarily only so UI/TitanMissionView.swift (protected — pending
    /// its own approved change to call recordSuccessfulInstall() per-product instead)
    /// still compiles unmodified. checkWithServer() already persists its own result
    /// directly, and only recordSuccessfulInstall(count:) may increment usage now, so
    /// this call site's old "persist after gate" semantics are no longer needed —
    /// this deliberately does nothing.
    @available(*, deprecated, message: "No longer needed; see recordSuccessfulInstall(count:). Remove once TitanMissionView.swift is updated under its own approved change.")
    func syncAfterServerGate() { }

    /// Called on sign-out. Resets the local cache to an explicit "unknown" state so a
    /// different account signing in next never sees this account's stale numbers, and
    /// so the strict offline policy correctly refuses to trust leftover local state.
    func resetForSignOut() {
        installsThisPeriod = 0
        hasServerConfirmedThisPeriod = false
        periodStart = currentPeriodStart()
        save()
    }

    // MARK: - Expiry refresh

    private func refreshIfExpired() {
        if timeUntilMonthlyReset == 0 {
            installsThisPeriod = 0
            hasServerConfirmedThisPeriod = false
            periodStart = currentPeriodStart()
            save()
        }
    }

    private func currentPeriodStart() -> Date {
        billingPeriodStart(asOf: Date())
    }

    // MARK: - Persistence
    // Keyed by (userID, hardwareUUID) so switching accounts or devices on the same
    // Mac never shows a different identity's cached usage. This local store is a
    // display/offline-fallback cache only — the server in install_counts remains the
    // sole authoritative source of truth.

    private var cacheKeySuffix: String {
        let uid = AuthManager.shared.session?.userID ?? "signedout"
        return "\(uid)_\(atlasHardwareUUID())"
    }

    private func save() {
        let ud = UserDefaults.standard
        let suffix = cacheKeySuffix
        ud.set(installsThisPeriod, forKey: "atlas_installs_month_\(suffix)")
        ud.set(periodStart.timeIntervalSinceReferenceDate, forKey: "atlas_month_start_\(suffix)")
        ud.set(hasServerConfirmedThisPeriod, forKey: "atlas_month_confirmed_\(suffix)")
    }

    private func savePending() {
        UserDefaults.standard.set(pendingURLs.map(\.path), forKey: "atlas_pending_urls")
    }

    private func load() {
        let ud  = UserDefaults.standard
        let now = Date()
        let suffix = cacheKeySuffix

        installsThisPeriod = ud.integer(forKey: "atlas_installs_month_\(suffix)")
        let ti = ud.double(forKey: "atlas_month_start_\(suffix)")
        periodStart = ti > 0 ? Date(timeIntervalSinceReferenceDate: ti) : currentPeriodStart()
        hasServerConfirmedThisPeriod = ud.bool(forKey: "atlas_month_confirmed_\(suffix)")

        today = now

        let raw = ud.stringArray(forKey: "atlas_pending_urls") ?? []
        pendingURLs = raw.compactMap { path -> URL? in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if pendingURLs.count != raw.count { savePending() }

        refreshIfExpired()
    }

    /// Called after sign-in completes (new session/profile available) so the cache
    /// reloads under the now-current user's key rather than whatever was cached
    /// under "signedout" or a previous account.
    func reloadForCurrentIdentity() {
        load()
    }
}
