import Foundation

@MainActor
class HistoryStore: ObservableObject {
    @Published var records: [InstallRecord] = []

    private let storeURL: URL = {
        let appSupport = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS")
        try? FileManager.default.createDirectory(
            at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("history.json")
    }()

    init() { load() }

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

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
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

    func clearAll() {
        records = []
        save()
    }

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
}
