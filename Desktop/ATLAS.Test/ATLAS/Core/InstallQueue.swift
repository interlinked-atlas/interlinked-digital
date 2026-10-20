import Foundation

// InstallQueue holds a list of files waiting to be installed.
// ATLAS processes them one at a time, in order.
// Each item has its own status so the UI can show progress.
//
// Persistence: waiting items are written to disk after every mutation so a crash
// or force-quit doesn't lose the user's pending installs. On next launch, any
// surviving waiting items are offered as a "Resume?" prompt.

enum QueueItemStatus {
    case waiting
    case scanning
    case installing
    case success
    case failure(String)
    case demoWarning(String)          // installed but demo/trial signals detected
    case activationRequired(String)   // installed successfully; needs license key / in-DAW activation
    case verificationWarning(String)  // installed; soft checks (AU registration) not yet confirmed

    var icon: String {
        switch self {
        case .waiting:               return "clock"
        case .scanning:              return "magnifyingglass"
        case .installing:            return "arrow.down.to.line"
        case .success:               return "checkmark.circle.fill"
        case .failure:               return "xmark.circle.fill"
        case .demoWarning:           return "exclamationmark.triangle.fill"
        case .activationRequired:    return "key.fill"
        case .verificationWarning:   return "exclamationmark.circle.fill"
        }
    }

    var label: String {
        ATLASMessages.queueStatusLabel(self)
    }
}

struct QueueItem: Identifiable {
    let id = UUID()
    let url: URL
    var status: QueueItemStatus = .waiting
    var scanResult: ScanResult? = nil
    var progress: Double = 0
    var progressStep: String = ""
    var detailLog: [String] = []

    var fileName: String { url.lastPathComponent }
    var fileType: String { url.pathExtension.uppercased() }

    // Plugin and direct-app installs run in parallel; PKG/DMG/ISO/ZIP are serial.
    // InstallBuilder .app bundles show a GUI wizard and must be serial — prevents
    // simultaneous Setup windows when multiple DMGs are dropped at once.
    var canRunParallel: Bool {
        let ext = url.pathExtension.lowercased()
        guard ["component", "vst3", "vst", "aaxplugin", "app"].contains(ext) else { return false }
        if ext == "app" {
            let macosDir = url.appendingPathComponent("Contents/MacOS")
            if FileManager.default.fileExists(
                atPath: macosDir.appendingPathComponent("installbuilder.sh").path) {
                return false
            }
        }
        return true
    }
}

// Minimal Codable wrapper for persistence — only the file URL is needed to
// reconstruct waiting items; all transient state (progress, logs) is discarded.
private struct PersistedQueueItem: Codable {
    let urlPath: String
}

@MainActor
class InstallQueue: ObservableObject {
    static let shared = InstallQueue()

    @Published var items: [QueueItem] = []
    @Published var isProcessing = false
    @Published var currentIndex: Int? = nil

    // Pending items from a previous session that survived a crash or force-quit.
    @Published var pendingResumeURLs: [URL] = []

    // MARK: - Persistence

    private static var persistenceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ATLAS/pending_queue.json")
    }

    func persistWaitingItems() {
        let waiting = items.filter {
            if case .waiting = $0.status { return true }
            return false
        }.map { PersistedQueueItem(urlPath: $0.url.path) }

        do {
            let dir = Self.persistenceURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(waiting)
            try data.write(to: Self.persistenceURL, options: .atomic)
        } catch { /* non-fatal — queue still works in memory */ }
    }

    func clearPersistedQueue() {
        try? FileManager.default.removeItem(at: Self.persistenceURL)
        pendingResumeURLs = []
    }

    // Called at launch: loads any surviving waiting items from the last session.
    func loadPersistedQueueIfNeeded() {
        guard let data = try? Data(contentsOf: Self.persistenceURL),
              let saved = try? JSONDecoder().decode([PersistedQueueItem].self, from: data),
              !saved.isEmpty else { return }
        let urls = saved.map { URL(fileURLWithPath: $0.urlPath) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        if !urls.isEmpty { pendingResumeURLs = urls }
    }

    func resumePersistedQueue() {
        for url in pendingResumeURLs { add(url: url) }
        clearPersistedQueue()
    }

    var isEmpty: Bool { items.isEmpty }
    var hasItems: Bool { !items.isEmpty }
    var waitingCount: Int { items.filter {
        if case .waiting = $0.status { return true }
        return false
    }.count }

    var failedCount: Int { items.filter {
        if case .failure = $0.status { return true }
        return false
    }.count }

    func add(url: URL) {
        guard !items.contains(where: { $0.url == url }) else { return }
        items.append(QueueItem(url: url))
        persistWaitingItems()
    }

    func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persistWaitingItems()
    }

    func clear() {
        items.removeAll { item in
            if case .waiting = item.status { return true }
            return false
        }
        persistWaitingItems()
    }

    func updateStatus(id: UUID, status: QueueItemStatus) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].status = status
            persistWaitingItems() // removes completed/failed from the on-disk list
        }
    }

    func updateScanResult(id: UUID, result: ScanResult) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].scanResult = result
        }
    }

    func updateProgress(id: UUID, progress: Double, step: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            items[idx].progress = progress
            items[idx].progressStep = step
            if !step.isEmpty && items[idx].detailLog.last != step {
                items[idx].detailLog.append(step)
            }
        }
    }

    func appendLog(id: UUID, entry: String) {
        if let idx = items.firstIndex(where: { $0.id == id }) {
            if !entry.isEmpty && items[idx].detailLog.last != entry {
                items[idx].detailLog.append(entry)
            }
        }
    }

    func retrySingle(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }),
              case .failure = items[idx].status else { return }
        items[idx].status = .waiting
        items[idx].progress = 0
        items[idx].progressStep = ""
        items[idx].detailLog = []
    }

    func retryAllFailed() {
        for idx in items.indices {
            if case .failure = items[idx].status {
                items[idx].status = .waiting
                items[idx].progress = 0
                items[idx].progressStep = ""
                items[idx].detailLog = []
            }
        }
    }
}
