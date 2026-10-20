import Foundation
import AppKit

struct ATLASUpdateInfo {
    let version:      String
    let downloadURL:  String
    let releaseNotes: String
}

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    private init() {}

    @Published var updateInfo: ATLASUpdateInfo? = nil
    @Published var dismissed = false

    var showBanner: Bool { updateInfo != nil && !dismissed }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    func check() {
        let version = currentVersion
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/version?platform=mac&current=\(version)") else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let available = json["update_available"] as? Bool, available,
                      let newVersion = json["version"] as? String,
                      let dlURL = json["download_url"] as? String
                else { return }
                updateInfo = ATLASUpdateInfo(
                    version:      newVersion,
                    downloadURL:  dlURL,
                    releaseNotes: json["release_notes"] as? String ?? ""
                )
            } catch { }
        }
    }

    func dismiss() { dismissed = true }

    func openDownload() {
        guard let url = URL(string: updateInfo?.downloadURL ?? "https://interlinked.digital/atlas") else { return }
        NSWorkspace.shared.open(url)
    }
}
