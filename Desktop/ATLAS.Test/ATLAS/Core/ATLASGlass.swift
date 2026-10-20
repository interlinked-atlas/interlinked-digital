import SwiftUI
import AppKit

// ============================================================
// MARK: - ATLAS Liquid Chrome Glass — reusable material system
// ============================================================
//
// Presentation-layer only. No functional/business logic lives here.
//
// Two levels are intentionally exposed — not a component-per-view catalog —
// because per the approved design direction, almost nothing in ATLAS should
// actually be glass: only the main window shell and the Drop Zone (plus,
// at a stronger opacity, a handful of important modals). Everything else
// (Library, Settings, History, Recovery Kit, Cleaner, VScan, logs) stays on
// the existing solid atlasCard()/atlasPanelBG system untouched.
//
// Native macOS 26 "Liquid Glass" (.glassEffect/GlassEffectContainer) is not
// available in this project's SDK (Xcode SDK here is 13.1; deployment target
// stays macOS 12 per Package.swift) — those APIs do not exist to reference at
// compile time yet, so no #available branch to a native path is included.
// When the toolchain here is updated to an SDK that declares them, the correct
// place to add that branch is inside `ATLASGlassBackground.body`, gated with
// `if #available(macOS 26.0, *) { /* native .glassEffect(...) */ } else { <existing NSVisualEffectView path, unchanged> }`
// so macOS 12–25 behavior is guaranteed to be byte-for-byte unaffected by that
// future addition.

enum ATLASGlassLevel {
    /// The main window shell — the most restrained glass treatment.
    case shell
    /// A surface that visually floats above the shell — the Drop Zone, and
    /// (at a higher base opacity via `modalStrength`) important modals/sheets.
    case surface
}

/// Applies the ATLAS Liquid Chrome Glass background: a translucent
/// NSVisualEffectView base, a very subtle directional light-wash gradient,
/// and a chrome-gradient edge highlight stroke. Never a flat blur, never a
/// flat color fill.
struct ATLASGlassBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var level: ATLASGlassLevel
    var cornerRadius: CGFloat
    /// Extra opacity for modal/sheet use (per approved direction: "important
    /// dialogs should have stronger opacity and contrast"). 0 = default.
    var modalStrength: Double = 0
    /// When false, the chrome rim stroke omits its top edge. Default true
    /// preserves the existing closed-rectangle rim everywhere else (Drop
    /// Zone, modals). Used only by the main window shell, whose top edge
    /// otherwise reads as an unwanted border strip under the traffic lights.
    var topEdge: Bool = true
    /// Insets the glass/background fill (material, wash gradient, and
    /// modal tint) from the top by this many points, without affecting the
    /// foreground content's layout at all. Default 0 preserves existing
    /// behavior everywhere else (Drop Zone, modals, splash). Used only by
    /// the main window shell, whose content spans the full window height
    /// (fullSizeContentView) and otherwise paints glass directly behind the
    /// native traffic-light buttons.
    var topInset: CGFloat = 0

    private var material: NSVisualEffectView.Material {
        switch level {
        case .shell:   return .underWindowBackground
        case .surface: return .hudWindow
        }
    }

    private var washOpacity: Double {
        let base: Double = level == .shell ? 0.04 : 0.07
        return base + modalStrength
    }

    /// Chrome rim opacity — deliberately strong. This is meant to read as visible
    /// polished-metal trim, not a faint hairline. Shell stays a step subtler than
    /// Drop Zone/modal surfaces per the approved hierarchy, but both must clearly
    /// register as metal, not a "gray outline."
    private var edgeOpacity: Double {
        let base: Double = scheme == .dark ? 0.85 : 0.70
        return level == .surface ? min(base + 0.10, 1.0) : base
    }

    private var edgeWidth: CGFloat {
        level == .surface ? 2.0 : 1.5
    }

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectView(material: material, blendingMode: .behindWindow)
                    // Subtle directional light wash — top-left brighter, fading down —
                    // this is what avoids the "flat frosted card" look on its own.
                    LinearGradient(
                        colors: [
                            Color.atlasChromeHighlightSoft.opacity(washOpacity),
                            Color.clear,
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    if modalStrength > 0 {
                        Color.atlasPanelBG.opacity(modalStrength)
                    }
                }
                .padding(.top, topInset)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                Group {
                    if topEdge {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.chromeRimGradient.opacity(edgeOpacity), lineWidth: edgeWidth)
                    } else {
                        // Same rim, minus the top edge — left/right/bottom only,
                        // via an open path instead of a closed RoundedRectangle.
                        GeometryReader { geo in
                            Path { path in
                                let w = geo.size.width
                                let h = geo.size.height
                                path.move(to: CGPoint(x: 0, y: 0))
                                path.addLine(to: CGPoint(x: 0, y: h))
                                path.addLine(to: CGPoint(x: w, y: h))
                                path.addLine(to: CGPoint(x: w, y: 0))
                            }
                            .stroke(Color.chromeRimGradient.opacity(edgeOpacity), lineWidth: edgeWidth)
                        }
                    }
                }
            )
    }
}

extension View {
    /// Applies the ATLAS Liquid Chrome Glass material. See `ATLASGlassLevel` —
    /// only the window shell and the Drop Zone (plus select modals) should use this.
    func atlasGlass(_ level: ATLASGlassLevel, cornerRadius: CGFloat = ATLASRadius.xl, modalStrength: Double = 0, topEdge: Bool = true, topInset: CGFloat = 0) -> some View {
        modifier(ATLASGlassBackground(level: level, cornerRadius: cornerRadius, modalStrength: modalStrength, topEdge: topEdge, topInset: topInset))
    }
}

/// A restrained glow used behind the Drop Zone icon on hover/drag-over.
/// Chrome-toned (cool blue-grey), not the teal accent glow used elsewhere in the app.
struct ATLASChromeGlow: ViewModifier {
    var active: Bool
    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(Color.atlasChromeUndertone.opacity(active ? 0.18 : 0))
                    .blur(radius: 20)
                    .animation(.easeInOut(duration: 0.18), value: active)
            )
    }
}

extension View {
    func atlasChromeGlow(active: Bool) -> some View {
        modifier(ATLASChromeGlow(active: active))
    }
}

/// A narrow specular chrome highlight that sweeps right-to-left once every ~10s.
/// Self-contained: draws only a masked overlay band and owns its own timer —
/// does not read or affect any application state. Intended use is
/// `.mask(someTextOrShapeView)` applied to this view, layered as an overlay on
/// top of the content it should appear to sweep across (see `atlasChromeSweep()`).
struct ATLASChromeSweepOverlay: View {
    // Fraction of the content width, so the sweep scales with whatever it masks.
    // Starts fully off the right edge, animates to fully off the left edge.
    @State private var xFraction: CGFloat = 1.4

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                stops: [
                    .init(color: .clear,                                    location: 0.0),
                    .init(color: Color.atlasChromeHighlightSoft.opacity(0.5), location: 0.38),
                    .init(color: Color.atlasChromeHighlight.opacity(0.95),    location: 0.5),
                    .init(color: Color.atlasChromeHighlightSoft.opacity(0.5), location: 0.62),
                    .init(color: .clear,                                    location: 1.0),
                ],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: max(w * 0.30, 14))
            .offset(x: w * xFraction)
        }
        .allowsHitTesting(false)
        .onAppear { scheduleSweep() }
    }

    private func scheduleSweep() {
        xFraction = 1.4
        withAnimation(.easeInOut(duration: 1.0)) {
            xFraction = -0.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            scheduleSweep()
        }
    }
}

extension View {
    /// Overlays a right-to-left chrome specular sweep masked to this view's own
    /// shape (e.g. text glyphs), so only the content itself appears to catch the
    /// light — nothing outside its bounds is affected. Fires once every ~10s.
    func atlasChromeSweep() -> some View {
        overlay(ATLASChromeSweepOverlay().mask(self))
    }
}

/// A second, inset chrome stroke — sits just inside the primary rim so a glass
/// surface reads as physically constructed (outer chrome trim + inner reveal)
/// rather than a single flat outline. Used by the Drop Zone, the strongest
/// expression of the material per the approved hierarchy.
struct ATLASChromeInnerRim: ViewModifier {
    var cornerRadius: CGFloat
    var inset: CGFloat = 3
    var opacity: Double = 0.35

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: max(cornerRadius - inset, 0), style: .continuous)
                .strokeBorder(Color.chromeRimGradient.opacity(opacity), lineWidth: 0.75)
                .padding(inset)
        )
    }
}

extension View {
    func atlasChromeInnerRim(cornerRadius: CGFloat, inset: CGFloat = 3, opacity: Double = 0.35) -> some View {
        modifier(ATLASChromeInnerRim(cornerRadius: cornerRadius, inset: inset, opacity: opacity))
    }
}
