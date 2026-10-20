import Foundation

// ZIPPasswordBroker — bridges the async InstallEngine (which can't show UI directly)
// with ContentView's main-thread sheet system.
//
// Usage:
//   1. InstallEngine calls `ZIPPasswordBroker.shared.requestPassword(for:)` and suspends.
//   2. ContentView observes `pendingRequest` and shows ZIPPasswordView as a sheet.
//   3. User types password and taps "Unlock" → ContentView calls `broker.submit(password:)`
//      OR taps "Cancel" → ContentView calls `broker.cancel()`.
//   4. The suspended InstallEngine resumes with either the password string or nil.

@MainActor
final class ZIPPasswordBroker: ObservableObject {

    static let shared = ZIPPasswordBroker()

    @Published var pendingRequest: ZIPPasswordRequest? = nil

    private var continuation: CheckedContinuation<String?, Never>? = nil

    private init() {}

    /// Called from InstallEngine (non-main actor) — suspends until user responds.
    func requestPassword(for fileName: String) async -> String? {
        return await withCheckedContinuation { cont in
            Task { @MainActor in
                self.continuation = cont
                self.pendingRequest = ZIPPasswordRequest(
                    fileName: fileName,
                    onSubmit: { [weak self] pwd in
                        self?.submit(password: pwd)
                    },
                    onCancel: { [weak self] in
                        self?.cancel()
                    }
                )
            }
        }
    }

    func submit(password: String) {
        pendingRequest = nil
        continuation?.resume(returning: password)
        continuation = nil
    }

    func cancel() {
        pendingRequest = nil
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
