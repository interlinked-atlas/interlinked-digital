import Foundation

@MainActor
final class MonthlyLimitManager: ObservableObject {
    static let shared = MonthlyLimitManager()
    private init() { load() }

    // Monthly caps per plan
    static let standardLimit  = 10
    static let proLimit        = 25
    static let advancedLimit   = 50

    @Published private(set) var installsThisMonth: Int = 0
    @Published private(set) var periodStart: Date = Date()
    @Published private(set) var pendingURLs: [URL] = []

    // MARK: - Status

    var currentLimit: Int {
        if AuthManager.shared.isAdvanced { return Self.advancedLimit }
        if AuthManager.shared.isPro      { return Self.proLimit }
        return Self.standardLimit
    }

    var isLocked: Bool {
        installsThisMonth >= currentLimit && timeUntilReset > 0
    }

    var timeUntilReset: TimeInterval {
        let end = Calendar.current.date(byAdding: .month, value: 1, to: periodStart) ?? Date()
        return max(0, end.timeIntervalSinceNow)
    }

    var remaining: Int {
        refreshIfExpired()
        return max(0, currentLimit - installsThisMonth)
    }

    var hasPendingFiles: Bool { !pendingURLs.isEmpty }

    // MARK: - Public API

    func recordInstall() {
        refreshIfExpired()
        installsThisMonth = min(installsThisMonth + 1, currentLimit + 1)
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

    // MARK: - Server sync

    private func syncToServer() async {
        guard let token = await AuthManager.shared.currentToken() else { return }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/install-count") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct SyncBody: Encodable { let count: Int; let period_start: String }
        req.httpBody = try? JSONEncoder().encode(SyncBody(count: installsThisMonth,
                                                          period_start: ISO8601DateFormatter().string(from: periodStart)))
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Private

    private func refreshIfExpired() {
        guard timeUntilReset == 0 else { return }
        installsThisMonth = 0
        periodStart = firstOfCurrentMonth()
        save()
    }

    private func firstOfCurrentMonth() -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    private func save() {
        let ud = UserDefaults.standard
        ud.set(installsThisMonth, forKey: "atlas_installs_month")
        ud.set(periodStart.timeIntervalSinceReferenceDate, forKey: "atlas_month_start")
    }

    private func savePending() {
        UserDefaults.standard.set(pendingURLs.map(\.path), forKey: "atlas_pending_urls")
    }

    private func load() {
        let ud = UserDefaults.standard
        installsThisMonth = ud.integer(forKey: "atlas_installs_month")
        let ti = ud.double(forKey: "atlas_month_start")
        if ti > 0 {
            periodStart = Date(timeIntervalSinceReferenceDate: ti)
        } else {
            periodStart = firstOfCurrentMonth()
        }
        let raw = ud.stringArray(forKey: "atlas_pending_urls") ?? []
        pendingURLs = raw.compactMap { path -> URL? in
            FileManager.default.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        if pendingURLs.count != raw.count { savePending() }
        refreshIfExpired()
    }
}
