import SwiftUI
import AppKit

// ============================================================
// MARK: - Appearance Manager
// ============================================================

@MainActor
final class AppearanceManager: ObservableObject {
    static let shared = AppearanceManager()

    private static let defaultsKey = "atlas.appearance"

    private init() {
        switch UserDefaults.standard.string(forKey: Self.defaultsKey) {
        case "dark":  _override = .init(wrappedValue: .dark)
        case "light": _override = .init(wrappedValue: .light)
        // No saved preference yet — default new/unset users to Light Mode.
        // Anyone who has ever explicitly chosen Light or Dark hits one of the
        // cases above instead, via the same persisted key, and keeps that
        // choice on every subsequent launch untouched by this default.
        default:      _override = .init(wrappedValue: .light)
        }
        // applyToNSApp() is intentionally not called here — NSApp is nil at this point.
        // .preferredColorScheme() on the root ZStack handles the SwiftUI layer at launch.
        // NSApp.appearance is set by applyToNSApp() via didSet when the user changes the theme.
    }

    @Published var override: ColorScheme? = nil {
        didSet {
            switch override {
            case .dark:  UserDefaults.standard.set("dark",  forKey: Self.defaultsKey)
            case .light: UserDefaults.standard.set("light", forKey: Self.defaultsKey)
            case .none:  UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
            applyToNSApp()
        }
    }

    func cycle(current systemScheme: ColorScheme) {
        switch override {
        case .none:
            override = (systemScheme == .dark) ? .light : .dark
        case .light:
            override = (systemScheme == .light) ? nil : .dark
        case .dark:
            override = (systemScheme == .dark) ? nil : .light
        @unknown default:
            override = nil
        }
    }

    func effective(_ system: ColorScheme) -> ColorScheme {
        override ?? system
    }

    private func applyToNSApp() {
        switch override {
        case .dark:  NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .none:  NSApp.appearance = nil
        }
    }
}

// ============================================================
// MARK: - Motion Tokens
// Linear-inspired: fast, precise, never theatrical.
// ============================================================

extension Animation {
    /// Default snap — 220ms, tightly damped. Use for buttons, toggles, chips.
    static let atlasSnap      = Animation.spring(response: 0.22, dampingFraction: 0.88)
    /// Panel spring — 280ms, slightly softer. Use for reveals and panels.
    static let atlasSpring    = Animation.spring(response: 0.28, dampingFraction: 0.85)
    /// Ease spring — 380ms. Use for large layout transitions.
    static let atlasEase      = Animation.spring(response: 0.38, dampingFraction: 0.80)
    /// Hover in — ultra-fast, 100ms.
    static let atlasHoverIn   = Animation.easeOut(duration: 0.10)
    /// Hover out — slightly slower, 160ms.
    static let atlasHoverOut  = Animation.easeOut(duration: 0.16)
    /// Fade — smooth crossfade, 180ms.
    static let atlasFade      = Animation.easeInOut(duration: 0.18)
    /// Reveal — entrance animation for panels and sheets, 340ms.
    static let atlasReveal    = Animation.spring(response: 0.34, dampingFraction: 0.82)
    /// Dismiss — exit animation. Slightly faster than reveal.
    static let atlasDismiss   = Animation.easeIn(duration: 0.20)
    /// Pulse — for ambient breathing animations that repeat forever.
    static let atlasPulse     = Animation.easeInOut(duration: 2.6).repeatForever(autoreverses: true)
}

// ============================================================
// MARK: - Spacing Scale
// Base unit: 4pt. Multiples of 4 for consistent density.
// ============================================================

enum ATLASSpacing {
    static let xxs:  CGFloat = 2
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 8
    static let md:   CGFloat = 12
    static let base: CGFloat = 16
    static let lg:   CGFloat = 20
    static let xl:   CGFloat = 24
    static let xxl:  CGFloat = 32
    static let xxxl: CGFloat = 40
    static let huge: CGFloat = 48
}

// ============================================================
// MARK: - Corner Radius System
// ============================================================

enum ATLASRadius {
    static let xs:   CGFloat = 4
    static let sm:   CGFloat = 6
    static let md:   CGFloat = 10
    static let lg:   CGFloat = 14
    static let xl:   CGFloat = 18
    static let xxl:  CGFloat = 22
    static let pill: CGFloat = 999
}

// ============================================================
// MARK: - Semantic Color Tokens
// ============================================================

extension Color {

    // MARK: Backgrounds

    /// App window background — near-black in dark, soft mid-grey in light.
    static let atlasBackground = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#0A0A0B")
            : NSColor(hex: "#ECECF0")      // light: was #F5F5F7 — slightly deeper grey
    })

    /// Card / panel surface — one step above background.
    static let atlasPanelBG = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#111113")
            : NSColor(hex: "#FFFFFF", alpha: 0.92)
    })

    /// Deepest background — input fields, code blocks, inset surfaces.
    static let atlasDeepBG = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#060608")
            : NSColor(hex: "#EFEFEF", alpha: 0.95)
    })

    /// Session / header strip background.
    static let atlasSessionHeader = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#0D0D0F")
            : NSColor(hex: "#E0E0E6", alpha: 0.98)  // light: was #E8E8EC — deeper for panel/bg contrast
    })

    /// Hover state fill — subtle, barely-there.
    static let atlasHover = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#18181B")
            : NSColor(hex: "#E2E2E6", alpha: 0.98)
    })

    /// Elevated surface — tooltips, popovers, menus.
    static let atlasElevated = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#222226")
            : NSColor(hex: "#D2D2D8")
    })

    /// Divider / separator lines.
    static let atlasSeparator = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#1C1C1F")
            : NSColor(hex: "#C8C8CE")
    })

    /// Regular border — card outlines.
    static let atlasBorder = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#222226")
            : NSColor(hex: "#C0C0C6")
    })

    /// Subtle border — inner cards, less-prominent separators.
    static let atlasBorderSubtle = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#1A1A1D")
            : NSColor(hex: "#CACACF")
    })

    // MARK: Labels

    /// Primary label — pure white / near-black.
    static let atlasLabel = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#FFFFFF")
            : NSColor(hex: "#0A0A0B")
    })

    /// Secondary label — neutral mid-gray (no blue tint).
    static let atlasSubtitle = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#8A8E9A")
            : NSColor(hex: "#52525E")
    })

    /// Tertiary label — dimmer, placeholder level.
    static let atlasTertiary = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#44444E")
            : NSColor(hex: "#888894")
    })

    // MARK: Accent — ATLAS teal (brand constant)

    /// Primary brand accent.
    static let atlasAccent      = Color(hex: "#3ECFB2")
    /// Accent with standard glow opacity — for backgrounds behind accent elements.
    static let atlasAccentGlow  = Color(hex: "#3ECFB2").opacity(0.16)
    /// Very subtle accent wash — section highlights, row tints.
    static let atlasAccentMuted = Color(hex: "#3ECFB2").opacity(0.08)
    /// Deep accent — for pressed states and lower-contrast contexts.
    static let atlasAccentDeep  = Color(hex: "#2AB89A")

    // MARK: Semantic Status Colors

    /// Success — teal-green. Install complete, positive confirmation states.
    static let atlasSuccess     = Color(hex: "#34D399")
    static let atlasSuccessGlow = Color(hex: "#34D399").opacity(0.14)

    /// Warning — amber. Stall indicators, caution notices.
    static let atlasWarning     = Color(hex: "#F0A030")
    static let atlasWarningGlow = Color(hex: "#F0A030").opacity(0.12)

    /// Danger — red. Errors, malware alerts, destructive actions.
    static let atlasDanger      = Color(hex: "#E05555")
    static let atlasDangerGlow  = Color(hex: "#E05555").opacity(0.12)

    /// Info — muted blue-gray. Neutral metadata, receipt IDs, log entries.
    static let atlasInfo        = Color(hex: "#7090B8")
    static let atlasInfoGlow    = Color(hex: "#7090B8").opacity(0.12)

    // MARK: Chrome / Liquid Glass (sampled from ATLAS.png star reference)
    //
    // Used exclusively by the glass/chrome material system (ATLASGlass.swift) for
    // window-shell and drop-zone edges, rims, and highlights. Never used as a fill
    // color and never used for semantic/status meaning — those stay on the tokens
    // above. Always composed as a 3-stop gradient (highlight → base → shadow),
    // never applied as a flat color, per the approved chrome design direction.

    /// Brightest specular catch — thin edge lines, ridge highlights, active glyphs.
    static let atlasChromeHighlight = Color(NSColor(name: nil) { app in
        NSColor(hex: "#F6F9FF")   // bright cool-white in both schemes; opacity varies at call site
    })

    /// Secondary/softer highlight — hover rim light.
    static let atlasChromeHighlightSoft = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#E4EAF2")
            : NSColor(hex: "#E4EAF2")
    })

    /// Primary chrome midtone — resting-state icon/border tone.
    static let atlasChromeBase = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#8A96A4")
            : NSColor(hex: "#6E7A88")
    })

    /// Deeper chrome shading — the fold/crevice tone.
    static let atlasChromeShadow = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#14171C")
            : NSColor(hex: "#3A4048")
    })

    /// Restrained cool blue-grey undertone — used sparingly in depth gradients/glows only.
    static let atlasChromeUndertone = Color(hex: "#5C6C82")

    /// The chrome edge gradient — top-left light source, consistent app-wide.
    /// Use for rims/strokes on glass surfaces. Never use the bare tokens above as a flat fill.
    static var chromeEdgeGradient: LinearGradient {
        LinearGradient(
            colors: [.atlasChromeHighlight, .atlasChromeBase, .atlasChromeShadow],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The primary chrome RIM gradient — a wider highlight → midtone → graphite-shadow
    /// sweep with more stops than `chromeEdgeGradient`, so a perimeter stroke reads as
    /// polished metal trim (visible banding) rather than a flat-tinted outline. This is
    /// the one to use for anything meant to look like "chrome encasing the glass" —
    /// window shell rim, Drop Zone perimeter, important modal borders.
    static var chromeRimGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .atlasChromeHighlight,      location: 0.0),
                .init(color: .atlasChromeHighlightSoft,   location: 0.22),
                .init(color: .atlasChromeBase,            location: 0.55),
                .init(color: .atlasChromeShadow,          location: 0.85),
                .init(color: .atlasChromeShadow.opacity(0.85), location: 1.0),
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Text on Glass
    //
    // The existing atlasLabel/atlasSubtitle/atlasTertiary tokens were tuned for
    // solid, flat panel backgrounds. atlasTertiary in particular is a low-contrast
    // "placeholder" level that reads fine on a flat panel but loses legibility over
    // the variable, translucent glass surfaces. These two tokens are calibrated
    // specifically for text/icons sitting directly on glass (window shell, Drop
    // Zone, splash) and should be used there instead of atlasTertiary.

    /// High-contrast primary text on glass — titles, the ATLAS wordmark's companion text.
    static let atlasOnGlassPrimary = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#F5F6F8")
            : NSColor(hex: "#101216")
    })

    /// Secondary text on glass — subtitles, captions, "by InterLinked" — still
    /// clearly legible, not a faint hint.
    static let atlasOnGlassSecondary = Color(NSColor(name: nil) { app in
        app.isDark
            ? NSColor(hex: "#C7CBD3")
            : NSColor(hex: "#3A3E46")
    })
}

// ============================================================
// MARK: - Typography System
// Use these instead of inline .font() calls throughout the UI.
// Existing ATLAS fonts (Bezmiar, SF Intellivised) are unaffected.
// These tokens apply to the system font only — body copy, UI labels.
// ============================================================

extension Font {
    /// Display — large hero text, splash screens, major modal titles.
    static let atlasDisplay      = Font.system(size: 28, weight: .bold)
    /// Title — section headlines, sheet titles.
    static let atlasTitle        = Font.system(size: 20, weight: .semibold)
    /// Title2 — card headers, panel titles.
    static let atlasTitle2       = Font.system(size: 16, weight: .semibold)
    /// Headline — product names, emphasized labels.
    static let atlasHeadline     = Font.system(size: 14, weight: .semibold)
    /// Body — primary UI text. Most labels and descriptions.
    static let atlasBody         = Font.system(size: 13, weight: .regular)
    /// Callout — emphasized body, button labels, key info.
    static let atlasCallout      = Font.system(size: 13, weight: .medium)
    /// Subheadline — secondary labels, form field labels.
    static let atlasSubhead      = Font.system(size: 12, weight: .medium)
    /// Caption — supplementary descriptions, hints.
    static let atlasCaption      = Font.system(size: 11, weight: .regular)
    /// Caption bold — badge labels, status pill text.
    static let atlasCaptionBold  = Font.system(size: 11, weight: .semibold)
    /// Micro — timestamps, metadata, counts.
    static let atlasMicro        = Font.system(size: 10, weight: .regular)
    /// Micro medium — emphasized counts, small pill labels.
    static let atlasMicroMedium  = Font.system(size: 10, weight: .medium)
    /// Nano — smallest readable labels, version strings, footnotes.
    static let atlasNano         = Font.system(size: 9, weight: .regular)
    /// Section label — all-caps overline. Pair with .atlasSectionHeader() modifier.
    static let atlasSectionLabel = Font.system(size: 9.5, weight: .semibold)
    /// Monospaced — log entries, file paths, receipt IDs.
    static let atlasMono         = Font.system(size: 10.5, weight: .regular, design: .monospaced)
    /// Monospaced small — timestamps, compact code.
    static let atlasMonoSm       = Font.system(size: 9, weight: .regular, design: .monospaced)
}

// ============================================================
// MARK: - Gradient System
// Named gradient helpers used across all surfaces and states.
// ============================================================

struct ATLASGradient {

    /// Window background wash applied on top of the visual effect view.
    static func windowWash(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
        ? LinearGradient(
            stops: [
                .init(color: Color(hex: "#141416").opacity(0.80), location: 0),
                .init(color: Color(hex: "#0D0D0F").opacity(0.88), location: 0.45),
                .init(color: Color(hex: "#070709").opacity(0.94), location: 1)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
        : LinearGradient(
            stops: [
                // Light: shifted deeper/greyer for a softer, less-bright appearance
                .init(color: Color(hex: "#EFEFEF").opacity(0.85), location: 0),
                .init(color: Color(hex: "#E8E8EC").opacity(0.88), location: 0.50),
                .init(color: Color(hex: "#E2E2E8").opacity(0.92), location: 1)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Subtle top-of-card accent wash — adds gentle depth to card surfaces.
    static func cardTopWash(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.atlasAccent.opacity(scheme == .dark ? 0.04 : 0.03), location: 0),
                .init(color: Color.clear, location: 0.55),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// Primary CTA button fill — teal gradient, top to bottom.
    static var accentFill: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "#4ADFBE"), location: 0),
                .init(color: Color(hex: "#2AB89A"), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// CTA hover state — slightly brighter than accentFill.
    static var accentFillHover: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "#5CEBCC"), location: 0),
                .init(color: Color(hex: "#38CDAD"), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// Success banner / completion header gradient.
    static var success: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#34D399"), Color(hex: "#2ABB88")],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Warning banner gradient.
    static var warning: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#F0A030"), Color(hex: "#D88A20")],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Danger / threat banner gradient.
    static var danger: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#E05555"), Color(hex: "#CC4040")],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Accent info banner (neutral blue-gray).
    static var info: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#7090B8"), Color(hex: "#5878A0")],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Edge-faded separator — fades out at both ends.
    static var separator: LinearGradient {
        LinearGradient(
            colors: [.clear, Color.atlasSeparator, .clear],
            startPoint: .leading, endPoint: .trailing)
    }

    /// Deep overlay background — for sheets and modal panels.
    static func deepPanel(_ scheme: ColorScheme) -> LinearGradient {
        scheme == .dark
        ? LinearGradient(
            stops: [
                .init(color: Color(hex: "#131316").opacity(0.96), location: 0),
                .init(color: Color(hex: "#0A0A0C").opacity(0.98), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
        : LinearGradient(
            stops: [
                .init(color: Color(hex: "#FFFFFF").opacity(0.96), location: 0),
                .init(color: Color(hex: "#F5F5F7").opacity(0.98), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
    }

    /// Shimmer overlay — for skeleton/loading states.
    static var shimmer: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.00), location: 0.0),
                .init(color: Color.white.opacity(0.06), location: 0.5),
                .init(color: Color.white.opacity(0.00), location: 1.0),
            ],
            startPoint: .leading, endPoint: .trailing)
    }
}

// ============================================================
// MARK: - Shadow System
// Five depth levels — applied consistently across all surfaces.
// ============================================================

enum ATLASShadowDepth {
    case subtle    // Barely-there separation (row items, dividers)
    case card      // Standard card lift (most content cards)
    case elevated  // Increased lift (modals, prominent panels)
    case floating  // Maximum lift (sheets, overlays, popovers)
    case accent    // Teal glow — active install state, CTAs

    func apply(scheme: ColorScheme) -> (color: Color, radius: CGFloat, y: CGFloat) {
        switch self {
        case .subtle:
            return (scheme == .dark ? .black.opacity(0.28) : .black.opacity(0.06), 6, 2)
        case .card:
            return (scheme == .dark ? .black.opacity(0.45) : .black.opacity(0.10), 14, 3)
        case .elevated:
            return (scheme == .dark ? .black.opacity(0.60) : .black.opacity(0.14), 24, 6)
        case .floating:
            return (scheme == .dark ? .black.opacity(0.70) : .black.opacity(0.20), 36, 10)
        case .accent:
            return (Color.atlasAccent.opacity(0.24), 12, 3)
        }
    }
}

// Backwards-compatible AtlasShadow struct — existing call sites unchanged.
struct AtlasShadow {
    static func card(_ scheme: ColorScheme) -> some ViewModifier {
        ShadowMod(
            color: scheme == .dark ? .black.opacity(0.45) : .black.opacity(0.10),
            radius: 16, y: 4
        )
    }
    static func elevated(_ scheme: ColorScheme) -> some ViewModifier {
        ShadowMod(
            color: scheme == .dark ? .black.opacity(0.65) : .black.opacity(0.18),
            radius: 32, y: 10
        )
    }
    static func accentGlow(radius: CGFloat = 8) -> some ViewModifier {
        ShadowMod(color: Color(hex: "#3ECFB2").opacity(0.22), radius: radius, y: 2)
    }
}

private struct ShadowMod: ViewModifier {
    let color: Color
    let radius: CGFloat
    var y: CGFloat = 0
    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, x: 0, y: y)
    }
}

extension View {
    // Existing API — kept unchanged for all current call sites.
    func atlasShadowCard(_ scheme: ColorScheme)     -> some View { modifier(AtlasShadow.card(scheme))      }
    func atlasShadowElevated(_ scheme: ColorScheme) -> some View { modifier(AtlasShadow.elevated(scheme))  }
    func atlasAccentGlow(radius: CGFloat = 8)       -> some View { modifier(AtlasShadow.accentGlow(radius: radius)) }

    // New depth-level API — use in new UI surfaces.
    func atlasShadow(_ depth: ATLASShadowDepth, scheme: ColorScheme) -> some View {
        let (color, radius, y) = depth.apply(scheme: scheme)
        return self.shadow(color: color, radius: radius, x: 0, y: y)
    }
}

// ============================================================
// MARK: - Surface Modifiers
// Layer 1 → Layer 2 → Layer 3 → Layer 4: increasing elevation.
// ============================================================

// Layer 1: App window background. Already `.atlasBackground()`.
struct AtlasBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        content.background(
            ZStack {
                VisualEffectView(
                    material: scheme == .dark ? .hudWindow : .sidebar,
                    blendingMode: .behindWindow
                )
                ATLASGradient.windowWash(scheme)
            }
            .ignoresSafeArea()
        )
    }
}

// Layer 2: Major content surfaces — sidebar strips, toolbar bands, section panels.
struct AtlasLayer2Modifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var cornerRadius: CGFloat = ATLASRadius.lg

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(scheme == .dark ? Color(hex: "#0E0E10") : Color(hex: "#F4F4F8"))
                    // light: was #FAFAFC — slightly deeper so Layer2 reads above the new background
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(ATLASGradient.cardTopWash(scheme))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75)
            )
            .atlasShadow(.subtle, scheme: scheme)
    }
}

// Layer 3: Standard content cards — the default card surface.
struct AtlasCardModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        content
            .background(
                scheme == .dark
                    ? Color(hex: "#111113")
                    : Color.white.opacity(0.92)
            )
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        scheme == .dark
                            ? Color(hex: "#1C1C1F")
                            : Color(hex: "#C0C0C6"),
                        lineWidth: 0.75
                    )
            )
            .shadow(
                color: scheme == .dark ? .black.opacity(0.40) : .black.opacity(0.07),
                radius: 14, x: 0, y: 3
            )
    }
}

// Layer 3 elevated: Cards with stronger presence — scan result, summary, install complete.
struct AtlasCardElevatedModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var cornerRadius: CGFloat = ATLASRadius.lg

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(scheme == .dark ? Color(hex: "#141417") : Color.white)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(ATLASGradient.cardTopWash(scheme))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(scheme == .dark ? 0.08 : 0.85), location: 0),
                                .init(color: Color.atlasBorderSubtle.opacity(scheme == .dark ? 1 : 0.5), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .atlasShadow(.elevated, scheme: scheme)
    }
}

// Glass: Floating panels, overlays, popovers, dialogs.
// Do NOT use for main content cards — only special floating surfaces.
struct AtlasGlassModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var cornerRadius: CGFloat = ATLASRadius.lg

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectView(
                        material: scheme == .dark ? .sidebar : .contentBackground,
                        blendingMode: .withinWindow
                    )
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(scheme == .dark ? 0.05 : 0.55), location: 0),
                            .init(color: Color.clear, location: 0.65),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(scheme == .dark ? 0.13 : 0.85), location: 0),
                                .init(color: Color.white.opacity(scheme == .dark ? 0.04 : 0.25), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            )
            .atlasShadow(.floating, scheme: scheme)
    }
}

// Inset surface: Input fields, code/log areas, deepest inset content.
struct AtlasInsetSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) var scheme
    var cornerRadius: CGFloat = ATLASRadius.sm

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(scheme == .dark ? Color(hex: "#07090F") : Color(hex: "#F0F0F2"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        scheme == .dark
                            ? Color(hex: "#16181C")
                            : Color(hex: "#D8D8DC"),
                        lineWidth: 0.75
                    )
            )
    }
}

extension View {
    func atlasBackground()  -> some View { modifier(AtlasBackgroundModifier()) }
    func atlasCard()        -> some View { modifier(AtlasCardModifier())       }

    func atlasLayer2(cornerRadius: CGFloat = ATLASRadius.lg) -> some View {
        modifier(AtlasLayer2Modifier(cornerRadius: cornerRadius))
    }
    func atlasCardElevated(cornerRadius: CGFloat = ATLASRadius.lg) -> some View {
        modifier(AtlasCardElevatedModifier(cornerRadius: cornerRadius))
    }
    func atlasGlass(cornerRadius: CGFloat = ATLASRadius.lg) -> some View {
        modifier(AtlasGlassModifier(cornerRadius: cornerRadius))
    }
    func atlasInset(cornerRadius: CGFloat = ATLASRadius.sm) -> some View {
        modifier(AtlasInsetSurfaceModifier(cornerRadius: cornerRadius))
    }
}

// ============================================================
// MARK: - Button Styles
// Primary → Secondary → Ghost → Destructive hierarchy.
// Use .buttonStyle(.atlasPrimary) etc. on Button views.
// ============================================================

struct ATLASPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryLabel(configuration: configuration)
    }

    private struct PrimaryLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.colorScheme) var scheme
        @Environment(\.isEnabled) var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.atlasCallout)
                .foregroundStyle(Color(hex: "#081410"))
                .padding(.horizontal, ATLASSpacing.base)
                .padding(.vertical, ATLASSpacing.sm + 1)
                .background(
                    Group {
                        if configuration.isPressed { ATLASGradient.accentFill.opacity(0.78) }
                        else if hovered            { ATLASGradient.accentFillHover }
                        else                       { ATLASGradient.accentFill }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                )
                .shadow(
                    color: Color.atlasAccent.opacity(hovered ? 0.35 : 0.20),
                    radius: hovered ? 10 : 6, x: 0, y: 2
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (hovered ? 1.01 : 1.0))
                .opacity(isEnabled ? 1.0 : 0.40)
                .animation(.atlasSnap, value: hovered)
                .animation(.atlasSnap, value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

struct ATLASSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryLabel(configuration: configuration)
    }

    private struct SecondaryLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.colorScheme) var scheme
        @Environment(\.isEnabled) var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.atlasCallout)
                .foregroundStyle(hovered ? Color.atlasAccent : Color.atlasLabel)
                .padding(.horizontal, ATLASSpacing.base)
                .padding(.vertical, ATLASSpacing.sm + 1)
                .background(
                    RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                        .fill(
                            hovered
                                ? Color.atlasAccent.opacity(0.07)
                                : (scheme == .dark
                                   ? Color(hex: "#16161A").opacity(0.70)
                                   : Color.white.opacity(0.70))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                        .strokeBorder(
                            hovered ? Color.atlasAccent.opacity(0.40) : Color.atlasBorder,
                            lineWidth: 0.75
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (hovered ? 1.01 : 1.0))
                .opacity(isEnabled ? 1.0 : 0.40)
                .animation(.atlasSnap, value: hovered)
                .animation(.atlasSnap, value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

struct ATLASGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostLabel(configuration: configuration)
    }

    private struct GhostLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.atlasSubhead)
                .foregroundStyle(hovered ? Color.atlasAccent : Color.atlasSubtitle)
                .padding(.horizontal, ATLASSpacing.sm)
                .padding(.vertical, ATLASSpacing.xs + 1)
                .background(
                    RoundedRectangle(cornerRadius: ATLASRadius.xs, style: .continuous)
                        .fill(hovered ? Color.atlasAccent.opacity(0.07) : Color.clear)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
                .opacity(isEnabled ? 1.0 : 0.38)
                .animation(.atlasSnap, value: hovered)
                .onHover { hovered = $0 }
        }
    }
}

struct ATLASDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DestructiveLabel(configuration: configuration)
    }

    private struct DestructiveLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.colorScheme) var scheme
        @Environment(\.isEnabled) var isEnabled
        @State private var hovered = false

        var body: some View {
            configuration.label
                .font(.atlasCallout)
                .foregroundStyle(hovered ? Color.atlasDanger : Color.atlasLabel)
                .padding(.horizontal, ATLASSpacing.base)
                .padding(.vertical, ATLASSpacing.sm + 1)
                .background(
                    RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                        .fill(
                            hovered
                                ? Color.atlasDanger.opacity(0.10)
                                : (scheme == .dark
                                   ? Color(hex: "#1A1014").opacity(0.80)
                                   : Color.white.opacity(0.70))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous)
                        .strokeBorder(
                            hovered ? Color.atlasDanger.opacity(0.45) : Color.atlasBorder,
                            lineWidth: 0.75
                        )
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (hovered ? 1.01 : 1.0))
                .opacity(isEnabled ? 1.0 : 0.40)
                .animation(.atlasSnap, value: hovered)
                .animation(.atlasSnap, value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

extension ButtonStyle where Self == ATLASPrimaryButtonStyle {
    static var atlasPrimary: ATLASPrimaryButtonStyle { ATLASPrimaryButtonStyle() }
}
extension ButtonStyle where Self == ATLASSecondaryButtonStyle {
    static var atlasSecondary: ATLASSecondaryButtonStyle { ATLASSecondaryButtonStyle() }
}
extension ButtonStyle where Self == ATLASGhostButtonStyle {
    static var atlasGhost: ATLASGhostButtonStyle { ATLASGhostButtonStyle() }
}
extension ButtonStyle where Self == ATLASDestructiveButtonStyle {
    static var atlasDestructive: ATLASDestructiveButtonStyle { ATLASDestructiveButtonStyle() }
}

// ============================================================
// MARK: - Utility View Modifiers
// ============================================================

// Status chip — colored pill badge. Used for status labels, version tags, counts.
struct ATLASChipModifier: ViewModifier {
    let color: Color
    @Environment(\.colorScheme) var scheme

    func body(content: Content) -> some View {
        content
            .font(.atlasCaptionBold)
            .foregroundStyle(color)
            .padding(.horizontal, ATLASSpacing.sm)
            .padding(.vertical, ATLASSpacing.xxs + 1)
            .background(Capsule().fill(color.opacity(scheme == .dark ? 0.13 : 0.10)))
            .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
    }
}

// Section header — all-caps overline label style with letter-spacing.
struct ATLASSectionHeaderModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.atlasSectionLabel)
            .foregroundStyle(Color.atlasSubtitle)
            .textCase(.uppercase)
    }
}

// Hover row — subtle background highlight for list/table rows.
struct ATLASRowModifier: ViewModifier {
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: ATLASRadius.xs, style: .continuous)
                    .fill(hovered ? Color.atlasHover : Color.clear)
            )
            .animation(.atlasHoverIn, value: hovered)
            .onHover { hovered = $0 }
    }
}

// Divider with optional edge fade.
struct ATLASFadedDivider: View {
    var faded: Bool = true
    @Environment(\.colorScheme) var scheme

    var body: some View {
        if faded {
            Rectangle()
                .fill(ATLASGradient.separator)
                .frame(height: 0.5)
        } else {
            Divider()
        }
    }
}

extension View {
    func atlasChip(color: Color = .atlasAccent)     -> some View { modifier(ATLASChipModifier(color: color)) }
    func atlasSectionHeader()                        -> some View { modifier(ATLASSectionHeaderModifier())    }
    func atlasRow()                                  -> some View { modifier(ATLASRowModifier())              }
}

// ============================================================
// MARK: - Appearance Toggle (unchanged)
// ============================================================

struct AppearanceToggle: View {
    @ObservedObject var manager = AppearanceManager.shared
    @Environment(\.colorScheme) var systemScheme
    @State private var hovered = false

    private var effective: ColorScheme { manager.effective(systemScheme) }
    private var isAuto: Bool { manager.override == nil }

    var body: some View {
        Button { manager.cycle(current: systemScheme) } label: {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: effective == .dark ? "moon.fill" : "sun.max.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            effective == .dark
                                ? Color(hex: "#8A8E9A")
                                : Color(hex: "#F0A030")
                        )

                    if isAuto {
                        Circle()
                            .fill(Color.atlasAccent)
                            .frame(width: 4, height: 4)
                            .offset(x: 6, y: -5)
                    }
                }
                .frame(width: 16)

                Text(isAuto ? "Auto" : (effective == .dark ? "Dark" : "Light"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.atlasSubtitle)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                hovered
                    ? Color.atlasHover
                    : (effective == .dark
                        ? Color(hex: "#0D0D0F").opacity(0.70)
                        : Color.white.opacity(0.55))
            )
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.03 : 1.0)
        .animation(.atlasSnap, value: hovered)
        .onHover { hovered = $0 }
        .help(isAuto
              ? "Following system appearance — click to override"
              : "Click to cycle: light · dark · auto")
    }
}

// ============================================================
// MARK: - NSColor Helpers (unchanged)
// ============================================================

private extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        var s = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if s.count == 6 { s += "FF" }
        var val: UInt64 = 0
        Scanner(string: s).scanHexInt64(&val)
        let r = CGFloat((val >> 24) & 0xFF) / 255
        let g = CGFloat((val >> 16) & 0xFF) / 255
        let b = CGFloat((val >>  8) & 0xFF) / 255
        let a = CGFloat( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: a * alpha)
    }
}
