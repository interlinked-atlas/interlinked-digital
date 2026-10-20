import SwiftUI

@MainActor
final class LibraryDashboardViewModel: ObservableObject {

    let store: HistoryStore

    init(store: HistoryStore) {
        self.store = store
    }

    var installedCount: Int { store.records.count }

    var archivedCount: Int { store.archivedRecords.count }

    var disabledCount: Int {
        store.records.filter { !($0.disabledFormats?.isEmpty ?? true) }.count
    }

    // Set of human-readable format labels present in active library records
    var activeFormats: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in store.records {
            for file in record.installedFiles {
                let ext = URL(fileURLWithPath: file.destinationPath).pathExtension.lowercased()
                let label: String
                switch ext {
                case "component":  label = "AU"
                case "vst3":       label = "VST3"
                case "vst":        label = "VST"
                case "aaxplugin":  label = "AAX"
                default: continue
                }
                if seen.insert(label).inserted { result.append(label) }
            }
        }
        // Sort in canonical order
        let order = ["AU", "VST3", "VST", "AAX"]
        return result.sorted { order.firstIndex(of: $0) ?? 99 < order.firstIndex(of: $1) ?? 99 }
    }

    var totalInstalledFiles: Int {
        store.records.reduce(0) { $0 + $1.installedFiles.count }
    }
}
