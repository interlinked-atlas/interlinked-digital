import Foundation

// MARK: - Models

struct QuarantineRecord: Codable, Identifiable {
    let id: String
    let originalPath: String
    let fileName: String
    let quarantinedAt: Date
    let verdict: String          // "malware" | "bundledThreat" | "suspicious"
    let threatTypes: [String]    // e.g. ["Information Stealer", "Persistence Mechanism"]
    let threatNames: [String]    // e.g. ["Atomic Stealer", "LaunchDaemon dropper"]
    let notes: String
}

// MARK: - Manager

@MainActor
final class QuarantineManager: ObservableObject {
    static let shared = QuarantineManager()

    @Published var records: [QuarantineRecord] = []

    private let fm = FileManager.default
    private var quarantineDir: URL {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("ATLAS/Quarantine", isDirectory: true)
    }
    private var manifestURL: URL { quarantineDir.appendingPathComponent("manifest.json") }

    private init() {
        ensureDir()
        loadManifest()
    }

    // MARK: - Quarantine

    /// Moves `fileURL` into the ATLAS quarantine folder and records it.
    func quarantine(
        fileURL: URL,
        verdict: String,
        threatTypes: [String],
        threatNames: [String],
        notes: String
    ) -> Bool {
        ensureDir()
        let id = UUID().uuidString
        let dest = quarantineDir.appendingPathComponent("\(id)_\(fileURL.lastPathComponent)")
        do {
            try fm.moveItem(at: fileURL, to: dest)
            // Strip quarantine attribute on the moved file so it can't accidentally launch
            _ = try? fm.setAttributes(
                [.posixPermissions: 0o444],
                ofItemAtPath: dest.path
            )
            let record = QuarantineRecord(
                id: id,
                originalPath: fileURL.path,
                fileName: fileURL.lastPathComponent,
                quarantinedAt: Date(),
                verdict: verdict,
                threatTypes: threatTypes,
                threatNames: threatNames,
                notes: notes
            )
            records.append(record)
            saveManifest()
            return true
        } catch {
            return false
        }
    }

    /// Permanently deletes a quarantined item.
    func deletePermanently(record: QuarantineRecord) {
        let dest = quarantineDir.appendingPathComponent("\(record.id)_\(record.fileName)")
        try? fm.removeItem(at: dest)
        records.removeAll { $0.id == record.id }
        saveManifest()
    }

    /// Restores a quarantined item to its original location.
    func restore(record: QuarantineRecord) -> Bool {
        let src = quarantineDir.appendingPathComponent("\(record.id)_\(record.fileName)")
        let dest = URL(fileURLWithPath: record.originalPath)
        do {
            try fm.moveItem(at: src, to: dest)
            records.removeAll { $0.id == record.id }
            saveManifest()
            return true
        } catch {
            return false
        }
    }

    /// Returns the on-disk URL for a quarantined record (for Finder reveal and pre-condition checks).
    func quarantineFileURL(for record: QuarantineRecord) -> URL {
        quarantineDir.appendingPathComponent("\(record.id)_\(record.fileName)")
    }

    // MARK: - Persistence

    private func ensureDir() {
        try? fm.createDirectory(at: quarantineDir, withIntermediateDirectories: true)
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([QuarantineRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }
}
