import Foundation

// ATLAS LEARN™ — Cloud install pattern memory.
//
// After every install that passes TITAN VERIFY™ with no demo signals,
// ATLAS uploads the confirmed pattern to Supabase so all users benefit.
//
// On new installs, ATLASLearn.lookup() is queried FIRST before local
// TitanMemory. Cloud patterns beat bundled ones because they are more
// recent and confirmed by real users.

actor ATLASLearn {

    static let shared = ATLASLearn()

    // In-memory cache so we don't hit the network on every scan.
    private var cache: [CloudPattern] = []
    private var cacheLoadedAt: Date? = nil
    private let cacheTTL: TimeInterval = 600 // 10 minutes

    // Disk cache — persists cloud patterns across app restarts for offline use.
    private static var diskCacheURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = support.appendingPathComponent("ATLAS", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cloud_patterns_cache.json")
    }

    // MARK: - CloudPattern model (mirrors Supabase install_patterns table)

    struct CloudPattern: Codable {
        let id: String
        let productName: String
        let matchPatterns: [String]
        let pkgReceiptIDs: [String]
        let installedPaths: [String]
        let hostsEntries: [String]
        let successCount: Int
        let lastConfirmedAt: String

        enum CodingKeys: String, CodingKey {
            case id
            case productName    = "product_name"
            case matchPatterns  = "match_patterns"
            case pkgReceiptIDs  = "pkg_receipt_ids"
            case installedPaths = "installed_paths"
            case hostsEntries   = "hosts_entries"
            case successCount   = "success_count"
            case lastConfirmedAt = "last_confirmed_at"
        }
    }

    // MARK: - Contribute (upload after verified clean install)

    func contribute(
        productName: String,
        sourceURL: URL,
        installedFiles: [InstallRecord.InstalledFile],
        pkgReceiptIDs: [String],
        hostsEntries: [String] = [],
        planSource: String = ""
    ) async {
        guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven"),
              let session = KeychainManager.loadSession(), !session.isExpired else { return }

        let matchPatterns = buildMatchPatterns(productName: productName, sourceURL: sourceURL)
        let installedPaths = installedFiles.map { $0.destinationPath }

        let body: [String: Any] = [
            "product_name":    productName,
            "match_patterns":  matchPatterns,
            "pkg_receipt_ids": pkgReceiptIDs,
            "installed_paths": installedPaths,
            "hosts_entries":   hostsEntries,
            "device_name":     deviceFriendlyName(),
            "hardware_uuid":   atlasHardwareUUID(),
            "macos_version":   ProcessInfo.processInfo.operatingSystemVersionString,
            "plan_source":     planSource
        ]

        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/learn/contribute") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15

        _ = try? await URLSession.shared.data(for: req)
        // Fire-and-forget — failure is silent, does not affect the install
    }

    // MARK: - Lookup (query before local TitanMemory)

    func lookup(directoryName: String, files: [URL]) async -> CloudPattern? {
        await ensureCacheLoaded()
        let dirLower   = directoryName.lowercased()
        let fileNames  = files.map { $0.lastPathComponent.lowercased() }.joined(separator: " ")
        let haystack   = "\(dirLower) \(fileNames)"
        return cache.first { pattern in
            pattern.matchPatterns.contains { haystack.contains($0.lowercased()) }
        }
    }

    // MARK: - Cache management

    private func ensureCacheLoaded() async {
        if let loadedAt = cacheLoadedAt, Date().timeIntervalSince(loadedAt) < cacheTTL {
            return // cache still warm
        }
        await loadCache()
    }

    private func loadCache() async {
        // Try network first
        if let patterns = await fetchFromNetwork() {
            cache = patterns
            cacheLoadedAt = Date()
            saveToDisk(patterns)
            return
        }
        // Network failed — load from disk cache (offline grace)
        if let patterns = loadFromDisk(), !patterns.isEmpty {
            cache = patterns
            cacheLoadedAt = Date() // treat as warm so we don't spam retries this session
        }
    }

    private func fetchFromNetwork() async -> [CloudPattern]? {
        guard let session = KeychainManager.loadSession(), !session.isExpired else { return nil }
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/learn/patterns") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let patterns = try? JSONDecoder().decode([CloudPattern].self, from: data) else { return nil }
        return patterns
    }

    private func saveToDisk(_ patterns: [CloudPattern]) {
        guard let url = ATLASLearn.diskCacheURL,
              let data = try? JSONEncoder().encode(patterns) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadFromDisk() -> [CloudPattern]? {
        guard let url = ATLASLearn.diskCacheURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([CloudPattern].self, from: data)
    }

    // MARK: - Helpers

    private func buildMatchPatterns(productName: String, sourceURL: URL) -> [String] {
        var patterns = Set<String>()

        // From product name: lowercase, strip version numbers
        let nameLower = productName.lowercased()
        patterns.insert(nameLower)

        // Strip trailing version like "v1.2", "1.2", "v16"
        let versionStripped = nameLower
            .replacingOccurrences(of: #"\s+v?\d[\d.]*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if !versionStripped.isEmpty && versionStripped != nameLower {
            patterns.insert(versionStripped)
        }

        // From source directory/volume name
        let dirName = sourceURL.deletingPathExtension().lastPathComponent.lowercased()
        if !dirName.isEmpty { patterns.insert(dirName) }

        // 3+ word phrases broken into meaningful substrings (e.g. "baby audio smooth operator")
        let words = versionStripped.components(separatedBy: .whitespaces).filter { $0.count > 2 }
        if words.count >= 2 {
            patterns.insert(words.prefix(3).joined(separator: " "))
        }

        return Array(patterns).filter { $0.count >= 4 }
    }
}
