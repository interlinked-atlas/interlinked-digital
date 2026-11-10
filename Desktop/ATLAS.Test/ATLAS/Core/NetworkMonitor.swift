import Foundation
import Network

/// Real, proactive connectivity awareness — ATLAS previously had none at
/// all (confirmed: no NWPathMonitor/reachability anywhere in the codebase).
/// Every network failure was only ever discovered reactively, one request
/// at a time, after that request's own timeout elapsed — which could take
/// up to a minute per call with no immediate feedback, reading as "the app
/// doesn't notice it's offline" even on a machine with zero connectivity.
/// This runs continuously from launch and publishes the current state
/// immediately on change, independent of any particular network call.
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isOnline: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "atlas.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: queue)
    }
}
