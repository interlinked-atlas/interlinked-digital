import Foundation

// Fetches the "ATLAS Browser" product catalog from the website. Public,
// unauthenticated endpoint — same reasoning as InstallIntelService: no user
// data involved, so no token/session needed here, unlike SupabaseService's
// REST calls.

struct AtlasCatalogItem: Decodable, Identifiable {
    let id: String
    let name: String
    let brand: String?
    let category: String       // "daw" | "app" | "plugin" | "bundle" | "sample_kit" | "expansion_pack"
    let platform: String       // "mac" | "win" | "both"
    let imageUrl: String?
    let externalUrl: String?
    let description: String?
    let fileSize: String?
    let specs: String?
    let titanVerified: Bool?
    let version: String?
    let isAvailable: Bool?
    let links: [AtlasCatalogLink]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, brand, category, platform, description
        case imageUrl = "image_url"
        case externalUrl = "external_url"
        case fileSize = "file_size"
        case specs
        case titanVerified = "titan_verified"
        case version
        case isAvailable = "is_available"
        case links
        case createdAt = "created_at"
    }

    /// Parsed from the raw `created_at` string — Supabase's timestamptz
    /// comes back with up to microsecond fractional seconds, which
    /// ISO8601DateFormatter's .withFractionalSeconds doesn't accept
    /// directly (it expects exactly 3 digits), so the fractional part is
    /// normalized first.
    var createdDate: Date? {
        guard let createdAt else { return nil }
        return Self.parseSupabaseDate(createdAt)
    }

    /// Drives the "NEW" badge in Browser — true for the first 5 days after
    /// a product is added, then it quietly stops applying on its own
    /// (nothing to clean up server-side, it's purely a function of time).
    var isNew: Bool {
        guard let createdDate else { return false }
        return Date().timeIntervalSince(createdDate) < 5 * 24 * 60 * 60
    }

    private static func parseSupabaseDate(_ s: String) -> Date? {
        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let dotIndex = s.firstIndex(of: ".") {
            let afterDot = s.index(after: dotIndex)
            var endIndex = afterDot
            while endIndex < s.endIndex, s[endIndex].isNumber { endIndex = s.index(after: endIndex) }
            let fractional = String(s[afterDot..<endIndex].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            let normalized = s[s.startIndex..<dotIndex] + "." + fractional + s[endIndex...]
            if let d = isoWithFraction.date(from: String(normalized)) { return d }
        }
        if let d = isoWithFraction.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    /// All usable download links for this product — the new multi-link
    /// `links` array if the admin filled it in, else falls back to the
    /// legacy single `external_url` column (wrapped with no label) so old
    /// rows keep working without a migration pass.
    var downloadLinks: [AtlasCatalogLink] {
        let fromArray = (links ?? []).filter { !$0.url.isEmpty && $0.appliesToThisPlatform }
        if !fromArray.isEmpty { return fromArray }
        if let url = externalUrl, !url.isEmpty { return [AtlasCatalogLink(label: nil, url: url, platform: nil)] }
        return []
    }

    /// False only when the admin explicitly marked it unavailable, or there's
    /// no download link yet — either way, Browser shows "Available Soon"
    /// instead of a Download button.
    var isReadyForDownload: Bool {
        (isAvailable ?? true) && !downloadLinks.isEmpty
    }
}

struct AtlasCatalogLink: Decodable, Identifiable {
    let label: String?
    let url: String
    let platform: String?   // "mac" | "win" | "both" | nil — nil/both applies to every platform

    var id: String { url }

    /// macOS build only shows "both"/nil and "mac" links — mirrors
    /// AtlasCatalogItem.appliesToThisPlatform, just per-link instead of
    /// per-product, since one product can now carry both a Mac and a
    /// Windows link side by side.
    var appliesToThisPlatform: Bool {
        platform == nil || platform == "both" || platform == "mac"
    }
}

enum AtlasBrowserService {

    private static let endpoint = URL(string: "https://www.interlinked.digital/api/atlas/catalog")!
    private static let timeoutSeconds: TimeInterval = 10

    /// Fetches the full catalog. Platform filtering (mac vs win) happens on
    /// the caller's side — see `AtlasCatalogItem.appliesToThisPlatform` — not
    /// here, since the endpoint returns everything and the list is small.
    /// Returns an empty array on any failure; the Browser view shows its own
    /// "couldn't load" state rather than this throwing.
    static func fetchCatalog() async -> [AtlasCatalogItem] {
        var req = URLRequest(url: endpoint, timeoutInterval: timeoutSeconds)
        req.httpMethod = "GET"

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else { return [] }

        return (try? JSONDecoder().decode([AtlasCatalogItem].self, from: data)) ?? []
    }

    private static let statusEndpoint = URL(string: "https://www.interlinked.digital/api/atlas/catalog/status")!

    /// Checked before the catalog itself — admin can flip this on to show
    /// "ATLAS Browser is Currently being Upgraded. Please Try Again Later."
    /// instead of the grid. Fails open (false) on any network error so a
    /// blip never blocks the Browser.
    static func fetchMaintenanceMode() async -> Bool {
        var req = URLRequest(url: statusEndpoint, timeoutInterval: timeoutSeconds)
        req.httpMethod = "GET"

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) else { return false }

        return decoded["maintenance"] ?? false
    }
}

/// Live sync for the admin's Browser enable/disable toggle. Previously
/// maintenance mode was only checked when AtlasBrowserView's own .task
/// ran — fine when Browser was an in-window overlay recreated on every
/// open, but after it became its own persistent window (v1.7.9) that
/// state could go stale for the rest of the session, and even the
/// per-open refresh added in v1.7.10 meant an admin toggle mid-session
/// (Browser already open) still didn't take effect until the next open.
///
/// Lightweight polling rather than a Supabase Realtime subscription —
/// same reasoning as MonthlyLimitManager's startLiveSync(): this is a
/// single public boolean with no auth involved, so a second WebSocket
/// stack isn't worth it just to shave the last few seconds off an
/// already-fast poll. Runs continuously from app launch, independent of
/// whether Browser's window has ever been opened.
@MainActor
final class BrowserMaintenanceManager: ObservableObject {
    static let shared = BrowserMaintenanceManager()
    private init() {}

    @Published private(set) var isUnderMaintenance = false

    private var pollTask: Task<Void, Never>? = nil

    func startLiveSync() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    func refreshNow() async {
        isUnderMaintenance = await AtlasBrowserService.fetchMaintenanceMode()
    }
}

extension AtlasCatalogItem {
    /// macOS build only shows "both" and "mac" rows — the Windows app will
    /// apply the identical rule against "win" instead, reading from this
    /// same endpoint, once that side is built.
    var appliesToThisPlatform: Bool {
        platform == "both" || platform == "mac"
    }

    var specLines: [String] {
        (specs ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var categoryLabel: String { Self.categoryLabel(for: category) }

    static func categoryLabel(for category: String) -> String {
        switch category {
        case "daw": return L(.browserCategoryDAWs)
        case "app": return L(.browserCategoryApps)
        case "plugin": return L(.browserCategoryPlugins)
        case "bundle": return L(.browserCategoryBundles)
        case "sample_kit": return L(.browserCategorySampleKits)
        case "expansion_pack": return L(.browserCategoryExpansionPacks)
        default: return category.capitalized
        }
    }
}
