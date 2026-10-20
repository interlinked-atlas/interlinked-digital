import SwiftUI

// ============================================================
// MARK: - Text Size Manager (Stage A — infrastructure only)
// ============================================================
//
// This stores and persists the user's preferred ATLAS text-size level.
// Stage A deliberately does NOT read this value from any existing screen —
// no font call site in the app is migrated yet. Selecting a non-Default
// level here currently has no visible effect anywhere in ATLAS; it only
// persists the choice for a future, separately-approved migration stage.

enum AtlasTextSize: String, CaseIterable, Identifiable {
    case standard
    case large
    case larger

    var id: String { rawValue }

    /// Multiplier a future migrated screen would apply on top of its
    /// existing base point size. `.standard` is exactly today's sizing
    /// (1.0× — no change).
    var scale: CGFloat {
        switch self {
        case .standard: return 1.0
        case .large:    return 1.12
        case .larger:   return 1.25
        }
    }

    var displayName: String {
        switch self {
        case .standard: return "Default"
        case .large:    return "Large"
        case .larger:   return "Larger"
        }
    }
}

@MainActor
final class TextSizeManager: ObservableObject {
    static let shared = TextSizeManager()

    private static let defaultsKey = "atlas.textSize"

    @Published var size: AtlasTextSize {
        didSet {
            UserDefaults.standard.set(size.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.defaultsKey)
        size = AtlasTextSize(rawValue: saved ?? "") ?? .standard
    }
}
