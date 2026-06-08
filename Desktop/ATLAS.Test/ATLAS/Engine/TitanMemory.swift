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
        let type: String          // "pkg" | "script" | "binary"
        let filePattern: String
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
    let confirmedDate: String?
}

struct TitanMemory {

    // Loaded once at app launch, immutable thereafter.
    static let shared: TitanMemory = TitanMemory()

    private let entries: [TitanMemoryEntry]

    private init() {
        if let url = Bundle.module.url(forResource: "known_installs", withExtension: "json",
                                       subdirectory: "TitanMemory"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TitanMemoryEntry].self, from: data) {
            entries = decoded
        } else {
            entries = []
        }
    }

    // MARK: - Lookup

    // Returns a confirmed entry if the directory name or file list matches a known pattern.
    func lookup(directoryName: String, files: [URL]) -> TitanMemoryEntry? {
        let dirLower = directoryName.lowercased()
        let fileNames = files.map { $0.lastPathComponent.lowercased() }.joined(separator: " ")
        let haystack  = "\(dirLower) \(fileNames)"

        return entries.first { entry in
            entry.matchPatterns.contains { pattern in
                haystack.contains(pattern.lowercased())
            }
        }
    }

    // Convenience: just match on a name string (volume name, folder name, etc.)
    func lookup(name: String) -> TitanMemoryEntry? {
        let lower = name.lowercased()
        return entries.first { entry in
            entry.matchPatterns.contains { lower.contains($0.lowercased()) }
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
