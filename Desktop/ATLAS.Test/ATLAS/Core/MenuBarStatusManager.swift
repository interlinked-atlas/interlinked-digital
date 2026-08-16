import Foundation
import Combine

enum ATLASMenuStatus {
    case idle, installing, success, failure
}

@MainActor
final class MenuBarStatusManager: ObservableObject {
    static let shared = MenuBarStatusManager()
    private init() {}

    @Published var menuStatus: ATLASMenuStatus = .idle
}
