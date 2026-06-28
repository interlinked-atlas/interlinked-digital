import Foundation

@MainActor
final class MonthlyLimitManager: ObservableObject {
    static let shared = MonthlyLimitManager()
    private init() { load() }

    static let standardLimit = 10
    static let proLimit      = 25

    @Published private(set) var installsThisPeriod: Int = 0
    @Published private(set) var periodStart: Date = Date()
    @Published private(set) var pendingURLs: [URL] = []

    // MARK: - Status

    var currentLimit: Int {
        AuthManager.shared.isPro ? Self.proLimit : Self.standardLimit
    }

    var isLocked: Bool {
        installsThisPeriod >= currentLimit && timeUntilReset > 0
    }

    var timeUntilReset: TimeInterval {
        max(0, nextResetDate.timeIntervalSinceNow)
    }

    var remaining: Int {
        refreshIfExpired()
        return max(0, currentLimit - installsThisPeriod)
    }

    var hasPendingFiles: Bool { !pendingURLs.isEmpty }

    // Next reset based on billing anchor day and interval
    var nextResetDate: Date {
        let profile = AuthManager.shared.profile
        let anchorDay = profile?.billingAnchorDay ?? 1
        let isAnnual  = profile?.isAnnual ?? false
        let cal = Calendar.current

        if isAnnual {
            // Annual: reset 12 months from period start
            return cal.date(byAdding: .year, value: 1, to: periodStart) ?? Date()
        } else {
            // Monthly: find the next occurrence of anchorDay
            var comps = cal.dateComponents([.year, .month, .day], from: periodStart)
            comps.day = anchorDay
            guard var candidate = cal.date(from: comps) else { return Date() }
            // If anchor day is in the past relative to period start, advance one month
            if candidate <= periodStart {
                candidate = cal.date(byAdding: .month, value: 1, to: candidate) ?? candidate
            }
            return candidate
        }
    }

    // MARK: - Public API

    func recordInstall() {
        refreshIfExpired()
        installsThisPeriod = min(installsThisPeriod + 1, currentLimit + 1)
        save()
        Task { await syncToServer() }
    }

    func setPending(_ urls: [URL]) {
        pendingURLs = urls
        savePending()
    }

    func clearPending() {
        pendingURLs = []
        savePending()
    }

    // Called after profile loads so reset date recalculates with billing anchor
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

    // MARK: - Private

    private func refreshIfExpired() {
        guard timeUntilReset == 0 else { return }
        installsThisPeriod = 0
        // Set period start to current billing anchor date
        periodStart = currentPeriodStart()
        save()
    }

    private func currentPeriodStart() -> Date {
        let profile = AuthManager.shared.profile
        let anchorDay = profile?.billingAnchorDay ?? 1
        let isAnnual  = profile?.isAnnual ?? false
        let cal = Calendar.current
        let now = Date()

        if isAnnual {
            // Annual: period start is the same month/day as anchor, most recent past occurrence
            var comps = cal.dateComponents([.year, .month, .day], from: now)
            comps.day = anchorDay
            if let candidate = cal.date(from: comps), candidate <= now {
                return candidate
            }
            // Roll back a year
            var prev = cal.dateComponents([.year, .month, .day], from: now)
            prev.year = (prev.year ?? 2026) - 1
            prev.day = anchorDay
            return cal.date(from: prev) ?? now
        } else {
            // Monthly: find the most recent past occurrence of anchorDay
            var comps = cal.dateComponents([.year, .month], from: now)
            comps.day = anchorDay
            if let candidate = cal.date(from: comps), candidate <= now {
                return candidate
            }
            // Roll back one month
            if let prev = cal.date(byAdding: .month, value: -1, to: cal.date(from: comps) ?? now) {
                return prev
            }
            return now
        }
    }

    private func save() {
        let ud = UserDefaults.standard
        ud.set(installsThisPeriod, forKey: "atlas_installs_month")
        ud.set(periodStart.timeIntervalSinceReferenceDate, forKey: "atlas_month_start")
    }

    private func savePending() {
        UserDefaults.standard.set(pendingURLs.map(\.path), forKey: "atlas_pending_urls")
    }

    private func load() {
        let ud = UserDefaults.standard
        installsThisPeriod = ud.integer(forKey: "atlas_installs_month")
        let ti = ud.double(forKey: "atlas_month_start")
        periodStart = ti > 0 ? Date(timeIntervalSinceReferenceDate: ti) : currentPeriodStart()
        let raw = ud.stringArray(forKey: "atlas_pending_urls") ?? []
        pendingURLs = raw.compactMap { path -> URL? in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if pendingURLs.count != raw.count { savePending() }
        refreshIfExpired()
    }
}
