import Foundation

// MARK: - History entry (one trashed item)

struct CleanerHistoryEntry: Codable, Identifiable {
    let id: UUID
    let name: String
    let originalPath: String
    let trashPath: String?       // actual Trash location captured from FileManager.trashItem
    let category: String         // CleanerCategory.rawValue
    let size: Int64?
    let trashedAt: Date
    var recoveredAt: Date? = nil
}

// MARK: - Session (one trash operation)

struct CleanerSession: Codable, Identifiable {
    let id: UUID
    let sessionDate: Date
    var entries: [CleanerHistoryEntry]

    var trashedCount: Int   { entries.count }
    var recoveredCount: Int { entries.filter { $0.recoveredAt != nil }.count }
    var bytesReclaimed: Int64 { entries.compactMap { $0.size }.reduce(0, +) }
}

// MARK: - Restore result

enum CleanerRestoreResult {
    case success
    case notInTrash(originalPath: String)
    case failed(String)
}

// MARK: - Store

@MainActor
final class CleanerHistoryStore: ObservableObject {

    static let shared = CleanerHistoryStore()

    @Published private(set) var sessions: [CleanerSession] = []

    private let storeURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cleaner_history.json")
    }()

    private init() { load() }

    // MARK: - Record a trash session

    func addSession(date: Date, entries: [CleanerHistoryEntry]) {
        guard !entries.isEmpty else { return }
        let session = CleanerSession(id: UUID(), sessionDate: date, entries: entries)
        sessions.insert(session, at: 0)
        save()
    }

    // MARK: - Restore an entry from Trash

    func restore(sessionID: UUID, entryID: UUID) async -> CleanerRestoreResult {
        guard let si = sessions.firstIndex(where: { $0.id == sessionID }),
              let ei = sessions[si].entries.firstIndex(where: { $0.id == entryID })
        else { return .failed("History entry not found") }

        let entry = sessions[si].entries[ei]
        let fm = FileManager.default

        // Build candidate Trash paths to search
        let filename = URL(fileURLWithPath: entry.originalPath).lastPathComponent
        var candidates: [URL] = []
        if let tp = entry.trashPath { candidates.append(URL(fileURLWithPath: tp)) }
        // ~/.Trash/<filename>
        candidates.append(
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".Trash")
                .appendingPathComponent(filename)
        )
        // /Volumes/<vol>/.Trashes/<uid>/<filename> for external volumes
        if let volumesContents = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            let uid = getuid()
            for vol in volumesContents {
                candidates.append(URL(fileURLWithPath: "/Volumes/\(vol)/.Trashes/\(uid)/\(filename)"))
            }
        }

        let candidatesCopy = candidates
        let originalPath = entry.originalPath
        let result = await Task.detached(priority: .userInitiated) { () -> CleanerRestoreResult in
            guard let trashURL = candidatesCopy.first(where: { fm.fileExists(atPath: $0.path) }) else {
                return .notInTrash(originalPath: originalPath)
            }
            do {
                let dest = URL(fileURLWithPath: originalPath)
                try? fm.createDirectory(at: dest.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                try fm.moveItem(at: trashURL, to: dest)
                return .success
            } catch {
                return .failed(error.localizedDescription)
            }
        }.value

        if case .success = result {
            sessions[si].entries[ei].recoveredAt = Date()
            save()
        }
        return result
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path),
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([CleanerSession].self, from: data)
        else { return }
        sessions = decoded
    }
}
