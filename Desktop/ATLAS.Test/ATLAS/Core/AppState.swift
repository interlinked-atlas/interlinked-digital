import Foundation

enum InstallResult {
    case success(appName: String, postInstallNote: String? = nil)
    case failure(reason: String)
    case unsupportedDAWInstallation(dawName: String)
}

enum InstallPhase: Equatable {
    case idle
    case fileSelected
    case scanning
    case scanned
    case classifying
    case processing
    case installing
    case verifying
    case cleanup
    case success
    case failure
    case dawBlocked(dawName: String)
}

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: InstallPhase = .idle
    @Published var selectedFileURL: URL? = nil
    @Published var lastResult: InstallResult? = nil
    @Published var scanResult: ScanResult? = nil
    @Published var progress: Double = 0        // 0.0 – 1.0
    @Published var progressStep: String = ""   // current step label
    @Published var scanStep: String = ""       // what the scanner is currently doing
    @Published var scanFileDetail: String = "" // current file being inspected
    @Published var scanProgress: Double = -1   // -1 = indeterminate, 0–1 = real %
    @Published var pendingOpenURLs: [URL] = []  // URLs queued from application(_:open:)
    @Published var lastInstallSteps: [InstallStep] = []
    @Published var lastInstallHostsEntries: [String] = []
    @Published var lastInstallLog: String = ""

    var statusMessage: String {
        switch phase {
        case .idle:         return "What are we installing today?"
        case .fileSelected: return "Got it — scanning the file…"
        case .scanning:     return "Checking what's inside the installer…"
        case .scanned:      return "Scan complete. Ready when you are."
        case .classifying:  return "Figuring out the best way to install this…"
        case .processing:   return "Preparing to install…"
        case .installing:   return "Installing — sit tight, this won't take long."
        case .verifying:    return "Double-checking everything looks right…"
        case .cleanup:      return "Wrapping up and cleaning temporary files…"
        case .success:      return "All done — installation was successful."
        case .failure:      return "Something went wrong during installation."
        case .dawBlocked:   return "This installer cannot be used with ATLAS."
        }
    }

    func reset() {
        phase = .idle
        selectedFileURL = nil
        lastResult = nil
        scanResult = nil
        progress = 0
        progressStep = ""
        scanStep = ""
        scanFileDetail = ""
        scanProgress = -1
    }
}
