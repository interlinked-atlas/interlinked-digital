import Foundation

@MainActor
class HistoryStore: ObservableObject {
    @Published var records: [InstallRecord] = []
    @Published var archivedRecords: [InstallRecord] = []

    private let storeURL: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS")
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("history.json")
    }()

    private let archiveURL: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS")
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("archived.json")
    }()

    init() {
        load()
        loadArchive()
    }

    func add(_ record: InstallRecord) {
        records.insert(record, at: 0)
        enforceLimit()
        save()
    }

    // Trims stored records to the Standard plan limit.
    // Called on add and after plan changes so the cap is always current.
    func enforceLimit() {
        guard !AuthManager.shared.isPro else { return }
        let limit = Features.standardHistoryLimit
        if records.count > limit {
            records = Array(records.prefix(limit))
        }
    }

    // Moves a record from the active Library to Archive.
    // reason: "clear_all" | "removed"
    func remove(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var record = records[idx]
        record.archivedAt = Date()
        record.archiveReason = "removed"
        records.remove(at: idx)
        archivedRecords.insert(record, at: 0)
        save()
        saveArchive()
    }

    func markUninstalled(id: UUID, backupPath: String?) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].status = .uninstalled
        records[idx].rollbackBackupPath = backupPath
        records[idx].disabledFormats = nil  // disabled files were trashed as part of uninstall
        save()
    }

    // MARK: - Enable/Disable (ATLAS Library — Pro only)

    func markFormatDisabled(id: UUID, entry: DisabledFormatEntry) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var existing = records[idx].disabledFormats ?? []
        existing.removeAll { $0.originalPath == entry.originalPath }
        existing.append(entry)
        records[idx].disabledFormats = existing
        save()
    }

    func markFormatEnabled(id: UUID, originalPath: String) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].disabledFormats?.removeAll { $0.originalPath == originalPath }
        if records[idx].disabledFormats?.isEmpty == true { records[idx].disabledFormats = nil }
        save()
    }

    // MARK: - Feedback tracking (ATLAS Library)

    func markFeedbackSubmitted(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].feedbackSubmittedAt = Date()
        save()
    }

    func updateRuntimePaths(id: UUID, newPaths: [String]) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        let existing = Set(records[idx].runtimeCreatedPaths ?? [])
        let merged = Array(existing.union(newPaths))
        guard merged.count > (records[idx].runtimeCreatedPaths?.count ?? 0) else { return }
        records[idx].runtimeCreatedPaths = merged
        save()
    }

    func markRestored(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        records[idx].status = .success
        records[idx].rollbackBackupPath = nil
        save()
    }

    // Moves all active Library records to Archive.
    // Preserves every record — including .uninstalled ones with recovery data — in Archive.
    // The panel closes if there is also nothing in Archive after the clear.
    func clearAll() {
        let now = Date()
        for var record in records {
            record.archivedAt = now
            record.archiveReason = "clear_all"
            archivedRecords.insert(record, at: 0)
        }
        records = []
        save()
        saveArchive()
    }

    // MARK: - Archive operations

    // Moves a record from Archive back to the active Library.
    // Strips the archive metadata so it reappears as an ordinary active record.
    func unarchive(id: UUID) {
        guard let idx = archivedRecords.firstIndex(where: { $0.id == id }) else { return }
        var record = archivedRecords[idx]
        record.archivedAt = nil
        record.archiveReason = nil
        archivedRecords.remove(at: idx)
        records.insert(record, at: 0)
        save()
        saveArchive()
    }

    // Permanently deletes an archive record (historical metadata only — no files affected).
    func deleteArchivedRecord(id: UUID) {
        archivedRecords.removeAll { $0.id == id }
        saveArchive()
    }

    // Permanently deletes all archive records.
    // Does NOT touch Logs (local, website, or admin copies).
    func deleteAllArchivedRecords() {
        archivedRecords = []
        saveArchive()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            print("[ATLAS] Could not save history: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            records = try JSONDecoder().decode([InstallRecord].self, from: data)
            enforceLimit()
            // Repair any stale DisabledFormatEntry records (e.g. from an interrupted enable/disable)
            if PluginToggleEngine.repairDisabledEntries(in: &records) {
                save()
            }
        } catch {
            print("[ATLAS] Could not load history: \(error)")
            records = []
        }
    }

    private func saveArchive() {
        do {
            let data = try JSONEncoder().encode(archivedRecords)
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            print("[ATLAS] Could not save archive: \(error)")
        }
    }

    private func loadArchive() {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
        do {
            let data = try Data(contentsOf: archiveURL)
            archivedRecords = try JSONDecoder().decode([InstallRecord].self, from: data)
        } catch {
            print("[ATLAS] Could not load archive: \(error)")
            archivedRecords = []
        }
    }
}
