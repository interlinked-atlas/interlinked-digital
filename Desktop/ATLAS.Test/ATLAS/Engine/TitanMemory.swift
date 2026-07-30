import Foundation

// TITAN MEMORY™ — ATLAS's knowledge base of confirmed install patterns.
//
// When a new install is scanned, TITAN MEMORY™ checks whether it matches
// a previously confirmed installation. If it does, it can:
//   1. Confirm correct install order without re-parsing instructions
//   2. Supply the exact hosts entries to block (no HTML/CSS misparse risk)
//   3. Supply rollback info (hosts entries to remove, dirs to delete)
//   4. Flag interpreter requirements (bash vs sh, in-place vs temp-copy)
//
// Entries are stored in Resources/TitanMemory/known_installs.json.
// New entries are added after a confirmed successful install.

struct TitanMemoryEntry: Codable {
    struct InstallStep: Codable {
        let order: Int
        let type: String          // "pkg" | "script" | "binary" | "dawInstall"
        let filePattern: String
        let auzPattern: String?   // for dawInstall: pattern to find the .auz license file
        let interpreter: String?  // "bash" | "sh" — nil means auto-detect
        let runInPlace: Bool?
        let requiresSudo: Bool?
        let note: String?
    }
    struct Rollback: Codable {
        let removeHostsEntries: [String]?
        let removeLicenseDir: String?
    }

    let id: String
    let name: String
    let matchPatterns: [String]
    let installSteps: [InstallStep]
    let hostsEntries: [String]?
    let licenseDestination: String?
    let rollback: Rollback?
    let confirmedWorking: Bool
    let dawComingSoon: Bool?
    let confirmedDate: String?
    let confirmedBy: String?
    let knownReceiptPrefixes: [String]?

    // Initialise from a raw Supabase row (column names may differ from JSON keys).
    init?(cloudRow row: [String: Any]) {
        guard let id   = row["id"]   as? String,
              let name = row["product_name"] as? String else { return nil }
        self.id   = id
        self.name = name

        // matchPatterns stored as JSON array string or native array
        if let arr = row["match_patterns"] as? [String] {
            self.matchPatterns = arr
        } else if let str = row["match_patterns"] as? String,
                  let data = str.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) {
            self.matchPatterns = arr
        } else {
            self.matchPatterns = [name.lowercased()]
        }

        // installSteps — decode from JSON string or array
        if let arr = row["steps"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: arr),
           let steps = try? JSONDecoder().decode([InstallStep].self, from: data) {
            self.installSteps = steps
        } else {
            self.installSteps = []
        }

        // hostsEntries
        self.hostsEntries = row["hosts_entries"] as? [String]

        // rollback
        if let rb = row["rollback"] as? [String: Any],
           let data = try? JSONSerialization.data(withJSONObject: rb),
           let decoded = try? JSONDecoder().decode(Rollback.self, from: data) {
            self.rollback = decoded
        } else {
            self.rollback = nil
        }

        self.licenseDestination   = row["license_destination"]    as? String
        self.confirmedWorking     = (row["confirmed_working"]      as? Bool) ?? true
        self.dawComingSoon        = row["daw_coming_soon"]         as? Bool
        self.confirmedDate        = row["confirmed_at"]            as? String
        self.confirmedBy          = row["confirmed_by"]            as? String
        self.knownReceiptPrefixes = row["known_receipt_prefixes"]  as? [String]
    }
}

class TitanMemory {

    // Shared instance — mutable so cloud sync can merge new entries at runtime.
    static let shared = TitanMemory()

    private var entries: [TitanMemoryEntry] = []
    private let queue = DispatchQueue(label: "titan.memory.queue", attributes: .concurrent)

    private init() {
        // 1. Load bundled entries (always available, no network needed)
        var bundled: [TitanMemoryEntry] = []
        if let url = Bundle.module.url(forResource: "known_installs", withExtension: "json",
                                       subdirectory: "TitanMemory"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TitanMemoryEntry].self, from: data) {
            bundled = decoded
        }

        // 2. Merge with disk-cached cloud entries (written on last successful sync)
        let cached = loadDiskCache()
        entries = merge(base: bundled, cloud: cached)
    }

    // MARK: - Cloud sync

    // Call once at app launch. Fetches the Supabase titan_memory table and merges
    // into the local entry list. Cloud entries with the same id replace bundled ones.
    // No auth required — reads use the public anon key.
    func syncFromCloud() {
        Task.detached(priority: .background) {
            guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/titan_memory?select=*&order=confirmed_at.desc") else { return }
            var req = URLRequest(url: url)
            req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 10

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else { return }

            // Cloud rows are raw JSON dicts — map to TitanMemoryEntry
            guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            let cloudEntries = rows.compactMap { TitanMemoryEntry(cloudRow: $0) }
            guard !cloudEntries.isEmpty else { return }

            // Persist to disk so next launch doesn't need network
            self.saveDiskCache(cloudEntries)

            // Merge into live entries (cloud wins on id conflict)
            self.queue.async(flags: .barrier) {
                let bundled: [TitanMemoryEntry]
                if let url2 = Bundle.module.url(forResource: "known_installs", withExtension: "json",
                                                subdirectory: "TitanMemory"),
                   let d = try? Data(contentsOf: url2),
                   let decoded = try? JSONDecoder().decode([TitanMemoryEntry].self, from: d) {
                    bundled = decoded
                } else { bundled = [] }
                self.entries = self.merge(base: bundled, cloud: cloudEntries)
            }
        }
    }

    // MARK: - Disk cache

    private var cacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ATLAS/titan_memory_cache.json")
    }

    private func saveDiskCache(_ entries: [TitanMemoryEntry]) {
        guard let url = cacheURL,
              let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    private func loadDiskCache() -> [TitanMemoryEntry] {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TitanMemoryEntry].self, from: data) else { return [] }
        return decoded
    }

    // MARK: - Merge

    // Cloud entries override bundled entries with the same id. New cloud ids are appended.
    private func merge(base: [TitanMemoryEntry], cloud: [TitanMemoryEntry]) -> [TitanMemoryEntry] {
        var result = base
        for cloudEntry in cloud {
            if let idx = result.firstIndex(where: { $0.id == cloudEntry.id }) {
                result[idx] = cloudEntry   // cloud wins
            } else {
                result.append(cloudEntry)  // new product
            }
        }
        return result
    }

    // MARK: - Lookup

    // Returns a confirmed entry if the directory name or file list matches a known pattern.
    func lookup(directoryName: String, files: [URL]) -> TitanMemoryEntry? {
        let dirLower = directoryName.lowercased()
        let fileNames = files.map { $0.lastPathComponent.lowercased() }.joined(separator: " ")
        let haystack  = "\(dirLower) \(fileNames)"

        return queue.sync {
            entries.first { entry in
                entry.matchPatterns.contains { pattern in
                    haystack.contains(pattern.lowercased())
                }
            }
        }
    }

    // Convenience: just match on a name string (volume name, folder name, etc.)
    func lookup(name: String) -> TitanMemoryEntry? {
        let lower = name.lowercased()
        return queue.sync {
            entries.first { entry in
                entry.matchPatterns.contains { lower.contains($0.lowercased()) }
            }
        }
    }

    // Returns the hosts entries ATLAS should block for a known install.
    // This bypasses HTML parsing entirely, eliminating any CSS misparse risk.
    func hostsEntries(for entry: TitanMemoryEntry) -> [String] {
        entry.hostsEntries ?? []
    }

    // Returns the hosts entries that should be removed on uninstall.
    func rollbackHostsEntries(for entry: TitanMemoryEntry) -> [String] {
        entry.rollback?.removeHostsEntries ?? entry.hostsEntries ?? []
    }

    // Returns the license directory to remove on uninstall (expanded ~).
    func rollbackLicenseDir(for entry: TitanMemoryEntry) -> String? {
        guard let raw = entry.rollback?.removeLicenseDir else { return nil }
        return raw.replacingOccurrences(of: "~", with: NSHomeDirectory())
    }

    // MARK: - Step override

    // MARK: - Confirmed-success feedback

    // Called when user taps "Yes, it works!" after a successful install.
    // Appends to a local JSONL log and syncs the confirmation to Supabase.
    func recordConfirmedSuccess(productName: String) {
        let entry: [String: Any] = [
            "product": productName,
            "confirmed_at": ISO8601DateFormatter().string(from: Date()),
            "device": Host.current().localizedName ?? "unknown",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        // Local append
        let logURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ATLAS/confirmed_installs.jsonl")
        if let logURL,
           let data = try? JSONSerialization.data(withJSONObject: entry),
           let line = String(data: data, encoding: .utf8) {
            try? FileManager.default.createDirectory(
                at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let appended = (line + "\n").data(using: .utf8) ?? Data()
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let handle = try? FileHandle(forWritingTo: logURL) {
                    handle.seekToEndOfFile()
                    handle.write(appended)
                    try? handle.close()
                }
            } else {
                try? appended.write(to: logURL)
            }
        }
        // Cloud sync — fire-and-forget via the install-log API endpoint
        let _: Task<Void, Never> = Task {
            guard let token = AuthManager.shared.session?.accessToken else { return }
            let uuid = atlasHardwareUUID()
            try? await SupabaseService.shared.uploadLog(
                accessToken: token,
                logType:     "confirmed-success",
                appName:     productName,
                filename:    productName,
                content:     "User confirmed install successful.",
                deviceName:  Host.current().localizedName ?? "Mac",
                hardwareUUID: uuid
            )
        }
    }

    // MARK: - Admin: Save confirmed pattern to TITAN MEMORY™

    /// Admin-only. Saves a fully confirmed install pattern to Supabase `titan_memory` table.
    /// These entries are pulled by all ATLAS clients and override local parsing.
    func saveAdminConfirmedPattern(
        productName: String,
        fileName: String,
        steps: [InstallStep],
        hostsEntries: [String],
        installLog: String
    ) {
        let stepDicts: [[String: Any]] = steps.enumerated().map { idx, step in
            var d: [String: Any] = [
                "order": idx + 1,
                "file": step.url.lastPathComponent,
                "type": stepTypeString(step.type),
                "note": step.note
            ]
            if case .folderCopy(let merge, _) = step.type { d["merge"] = merge }
            return d
        }

        let payload: [String: Any] = [
            "product_name":   productName,
            "file_name":      fileName,
            "steps":          stepDicts,
            "hosts_entries":  hostsEntries,
            "confirmed_by":   AuthManager.adminEmail,
            "confirmed_at":   ISO8601DateFormatter().string(from: Date()),
            "install_log":    String(installLog.prefix(4000)),
            "platform":       "mac"
        ]

        Task {
            guard let token = AuthManager.shared.session?.accessToken else { return }
            guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
            guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/titan_memory") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            req.httpBody = body
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    /// Admin-only. Fetches all entries from the Supabase `titan_memory` table.
    func fetchAllEntries() async -> [[String: Any]] {
        guard let url = URL(string: "\(SupabaseConfig.projectURL)/rest/v1/titan_memory?select=*&order=confirmed_at.desc") else { return [] }
        var req = URLRequest(url: url)
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        if let token = AuthManager.shared.session?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows
    }

    private func stepTypeString(_ type: InstallStep.StepType) -> String {
        switch type {
        case .installer:      return "pkg"
        case .patch:          return "patch"
        case .plugin:         return "plugin"
        case .app:            return "app"
        case .managedInstall: return "manager"
        case .manual:         return "manual"
        case .folderCopy:     return "folder_copy"
        case .dawInstall:     return "dawInstall"
        }
    }

    // Returns the confirmed install step for a given file URL, if TITAN MEMORY™
    // has a known entry. Callers can use this to skip re-classifying the file.
    func step(for fileURL: URL, in entry: TitanMemoryEntry) -> TitanMemoryEntry.InstallStep? {
        let name = fileURL.lastPathComponent.lowercased()
        return entry.installSteps.first { step in
            let pattern = step.filePattern.lowercased()
            // Try regex first, fall back to substring
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil {
                return true
            }
            return name.contains(pattern)
        }
    }
}
