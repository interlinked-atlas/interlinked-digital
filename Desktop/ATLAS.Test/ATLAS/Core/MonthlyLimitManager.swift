import Foundation

@MainActor
final class MonthlyLimitManager: ObservableObject {
    static let shared = MonthlyLimitManager()
    private init() { load() }

    // MARK: - Limits
    static let standardDailyLimit   = 3
    static let standardMonthlyLimit = 10
    static let proLimit             = 25

    // MARK: - State
    @Published private(set) var installsThisPeriod: Int = 0
    @Published private(set) var installsToday:      Int = 0
    @Published private(set) var periodStart:        Date = Date()
    @Published private(set) var today:              Date = Date()
    @Published private(set) var pendingURLs:        [URL] = []

    // MARK: - Derived limits

    var currentLimit: Int {
        AuthManager.shared.isPro ? Self.proLimit : Self.standardMonthlyLimit
    }

    var dailyLimit: Int {
        AuthManager.shared.isPro ? Int.max : Self.standardDailyLimit
    }

    // MARK: - Lock state

    /// Daily limit hit (Standard only) — resets at midnight
    var isDailyLocked: Bool {
        guard !AuthManager.shared.isPro else { return false }
        guard !AuthManager.shared.isAdmin else { return false }
        return installsToday >= Self.standardDailyLimit
    }

    /// Monthly cap hit — resets on billing anniversary
    var isMonthlyLocked: Bool {
        guard !AuthManager.shared.isAdmin else { return false }
        return installsThisPeriod >= currentLimit && timeUntilMonthlyReset > 0
    }

    /// Either lock applies
    var isLocked: Bool { isDailyLocked || isMonthlyLocked }

    // MARK: - Remaining

    var remaining: Int {
        refreshIfExpired()
        if AuthManager.shared.isPro {
            return max(0, currentLimit - installsThisPeriod)
        }
        let dailyLeft   = max(0, Self.standardDailyLimit   - installsToday)
        let monthlyLeft = max(0, Self.standardMonthlyLimit - installsThisPeriod)
        return min(dailyLeft, monthlyLeft)
    }

    var hasPendingFiles: Bool { !pendingURLs.isEmpty }

    // MARK: - Countdowns

    var timeUntilDailyReset: TimeInterval {
        let cal = Calendar.current
        guard let nextMidnight = cal.nextDate(after: today,
                                              matching: DateComponents(hour: 0, minute: 0, second: 0),
                                              matchingPolicy: .nextTime) else { return 0 }
        return max(0, nextMidnight.timeIntervalSinceNow)
    }

    var timeUntilMonthlyReset: TimeInterval {
        max(0, nextMonthlyResetDate.timeIntervalSinceNow)
    }

    /// Whichever lock is active — returns the relevant countdown
    var timeUntilReset: TimeInterval {
        isDailyLocked ? timeUntilDailyReset : timeUntilMonthlyReset
    }

    var isLockedByDaily:   Bool { isDailyLocked && !isMonthlyLocked }
    var isLockedByMonthly: Bool { isMonthlyLocked }

    // MARK: - Next reset dates

    var nextMonthlyResetDate: Date {
        let profile   = AuthManager.shared.profile
        let anchorDay = profile?.billingAnchorDay ?? 1
        let isAnnual  = profile?.isAnnual ?? false
        let cal       = Calendar.current

        if isAnnual {
            return cal.date(byAdding: .year, value: 1, to: periodStart) ?? Date()
        } else {
            var comps = cal.dateComponents([.year, .month, .day], from: periodStart)
            comps.day = anchorDay
            guard var candidate = cal.date(from: comps) else { return Date() }
            if candidate <= periodStart {
                candidate = cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
    }

    // MARK: - Public API

    func recordInstall() {
        guard !AuthManager.shared.isAdmin else { return }
        refreshIfExpired()
        installsThisPeriod = min(installsThisPeriod + 1, currentLimit + 1)
        if !AuthManager.shared.isPro {
            installsToday = min(installsToday + 1, Self.standardDailyLimit + 1)
        }
        save()
        Task { await syncToServer() }
    }

    /// Server-side gate — call BEFORE starting any install.
    /// Returns (allowed, reason) where reason is "daily_limit", "monthly_limit", or nil.
    func checkWithServer() async -> (allowed: Bool, reason: String?) {
        guard let token = await AuthManager.shared.currentToken() else {
            return (true, nil) // no token → fail open, local gate still applies
        }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/check-install") else {
            return (true, nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 6

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                return (true, nil) // fail open on server error
            }
            struct Result: Decodable {
                let allowed: Bool
                let reason: String?
                let daily_used: Int?
                let monthly_used: Int?
            }
            let result = try JSONDecoder().decode(Result.self, from: data)
            // Sync server counts back so UI reflects reality
            if let mu = result.monthly_used { installsThisPeriod = mu }
            if let du = result.daily_used   { installsToday = du }
            save(); saveDaily()
            return (result.allowed, result.reason)
        } catch {
            return (true, nil) // network error → fail open
        }
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

    // MARK: - Server sync

    private func syncToServer() async {
        guard let token = await AuthManager.shared.currentToken() else { return }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/install-count") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct SyncBody: Encodable { let count: Int; let period_start: String }
        req.httpBody = try? JSONEncoder().encode(SyncBody(
            count: installsThisPeriod,
            period_start: ISO8601DateFormatter().string(from: periodStart)
        ))
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Expiry refresh

    private func refreshIfExpired() {
        let cal = Calendar.current
        let now = Date()

        // Reset daily count if calendar day changed
        if !cal.isDate(today, inSameDayAs: now) {
            installsToday = 0
            today = now
            saveDaily()
        }

        // Reset monthly count if billing period expired
        if timeUntilMonthlyReset == 0 {
            installsThisPeriod = 0
            periodStart = currentPeriodStart()
            save()
        }
    }

    private func currentPeriodStart() -> Date {
        let profile   = AuthManager.shared.profile
        let anchorDay = profile?.billingAnchorDay ?? 1
        let isAnnual  = profile?.isAnnual ?? false
        let cal       = Calendar.current
        let now       = Date()

        if isAnnual {
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.day = anchorDay
            if let candidate = cal.date(from: comps), candidate <= now { return candidate }
            var prev = cal.dateComponents([.year, .month, .day], from: now)
            prev.year = (prev.year ?? 2026) - 1
            prev.day  = anchorDay
            return cal.date(from: prev) ?? now
        } else {
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = anchorDay
            if let candidate = cal.date(from: comps), candidate <= now { return candidate }
            if let prev = cal.date(byAdding: .month, value: -1, to: cal.date(from: comps) ?? now) { return prev }
            return now
        }
    }

    // MARK: - Persistence

    private func save() {
        let ud = UserDefaults.standard
        ud.set(installsThisPeriod, forKey: "atlas_installs_month")
        ud.set(periodStart.timeIntervalSinceReferenceDate, forKey: "atlas_month_start")
    }

    private func saveDaily() {
        let ud = UserDefaults.standard
        ud.set(installsToday, forKey: "atlas_installs_today")
        ud.set(today.timeIntervalSinceReferenceDate, forKey: "atlas_today_date")
    }

    private func savePending() {
        UserDefaults.standard.set(pendingURLs.map(\.path), forKey: "atlas_pending_urls")
    }

    private func load() {
        let ud  = UserDefaults.standard
        let cal = Calendar.current
        let now = Date()

        // Monthly
        installsThisPeriod = ud.integer(forKey: "atlas_installs_month")
        let ti = ud.double(forKey: "atlas_month_start")
        periodStart = ti > 0 ? Date(timeIntervalSinceReferenceDate: ti) : currentPeriodStart()

        // Daily — discard if saved date is a different calendar day
        let savedTodayTI = ud.double(forKey: "atlas_today_date")
        let savedToday   = savedTodayTI > 0 ? Date(timeIntervalSinceReferenceDate: savedTodayTI) : now
        if cal.isDate(savedToday, inSameDayAs: now) {
            installsToday = ud.integer(forKey: "atlas_installs_today")
            today = savedToday
        } else {
            installsToday = 0
            today = now
            saveDaily()
        }

        // Pending files
        let raw = ud.stringArray(forKey: "atlas_pending_urls") ?? []
        pendingURLs = raw.compactMap { path -> URL? in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if pendingURLs.count != raw.count { savePending() }

        refreshIfExpired()
    }
}
