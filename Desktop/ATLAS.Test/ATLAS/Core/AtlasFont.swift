import SwiftUI

// ============================================================
// MARK: - Atlas Font (Stage B-0 — shared text-scaling helper)
// ============================================================
//
// Drop-in replacement for `.font(.system(size:weight:design:))` that also
// applies the user's current Text Size preference (Settings → Appearance →
// Text Size), sourced from TextSizeManager — the single source of truth for
// this setting, unchanged from Stage A.
//
// `.standard` (Default) has `scale == 1.0`, so `size * scale == size`:
// any view migrated to this helper renders pixel-identical to its original
// `.font(.system(size:))` call as long as the user hasn't changed the
// setting from Default. This file only adds the helper itself — introducing
// it does not change any existing UI on its own; a view only scales once it
// is explicitly migrated to call `.atlasFont(...)` instead of
// `.system(size:)`.

@MainActor
extension Font {
    static func atlasFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scale = TextSizeManager.shared.size.scale
        return .system(size: size * scale, weight: weight, design: design)
    }
}
