import SwiftUI

// Shared directional transfer animation — same visual language as the
// interlinked.digital/atlas launch-page hero animation (ATLAS app window,
// a Mac screen, small file/program icon chips flowing along a curved path
// between them, with the destination glowing softly each time an icon
// arrives), ported natively here via Canvas instead of CSS.
//
// .install            → files flow UP from the ATLAS app into the Mac screen
// .uninstall/.recovery → same two endpoints, reversed: files flow back DOWN
//                        from the screen into the app
//
// Purely decorative Canvas view. No engine dependency. All inputs are
// primitives (mode, isAnimating) — identical public interface to before,
// so every call site (QueueView, TitanMissionView, StandardInstallProgressView,
// ContentView) needs no changes.

enum ATLASTransferMode {
    case install
    case uninstall
    case recovery
}

struct ATLASTransferAnimation: View {
    let mode: ATLASTransferMode
    let isAnimating: Bool   // particles flow when true, freeze when false

    private let particleCount = 6
    private let cycleDuration: Double = 3.6   // one full particle's travel time
    private var staggerInterval: Double { cycleDuration / Double(particleCount) }

    // Files flow screen→app for uninstall/recovery (reversed from install).
    private var reversed: Bool { mode != .install }

    private var accentColor: Color {
        switch mode {
        case .install:   return Color(hex: "#3ECFB2")
        case .uninstall: return Color(hex: "#E05555")
        case .recovery:  return Color(hex: "#5B8DEF")
        }
    }

    private static let iconPalette: [Color] = [
        Color(hex: "#3ECFB2"), Color(hex: "#5E6AD2"), Color(hex: "#F0A030"),
        Color(hex: "#E8ECFF"), Color(hex: "#E05555"), Color(hex: "#3ECFB2"),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { tl in
            Canvas { ctx, size in
                let t = isAnimating ? tl.date.timeIntervalSinceReferenceDate : 0

                let screenCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.20)
                let appCenter    = CGPoint(x: size.width * 0.5, y: size.height * 0.84)

                // Arrival-synced glow on whichever endpoint files are flowing
                // INTO — screen for install, app for uninstall/recovery. Peaks
                // briefly every staggerInterval, same as a particle arriving.
                let cyclePos = (t.truncatingRemainder(dividingBy: staggerInterval)) / staggerInterval
                let glowPulse = cyclePos > 0.7 ? easeInOut((cyclePos - 0.7) / 0.3) : 0
                let destCenter = reversed ? appCenter : screenCenter
                drawGlow(&ctx, at: destCenter, radius: 34 + glowPulse * 10,
                         color: accentColor, intensity: 0.25 + glowPulse * 0.55)

                drawMacScreen(&ctx, center: screenCenter, accent: accentColor)
                drawAppWindow(&ctx, center: appCenter)

                for i in 0..<particleCount {
                    let phaseOffset = Double(i) / Double(particleCount)
                    let rawPhase = (t / cycleDuration + phaseOffset)
                        .truncatingRemainder(dividingBy: 1.0)

                    let alpha: Double
                    if rawPhase < 0.10      { alpha = rawPhase / 0.10 }
                    else if rawPhase > 0.85 { alpha = max(0, (1.0 - rawPhase) / 0.15) }
                    else                    { alpha = 0.95 }

                    // Smooth curved path (quadratic bezier with a gentle side
                    // bow), not a straight line — matches the website's
                    // offset-path curve, just computed per-frame instead of
                    // via CSS.
                    let travelPhase = reversed ? rawPhase : rawPhase
                    let start = reversed ? screenCenter : appCenter
                    let end   = reversed ? appCenter    : screenCenter
                    let bow: CGFloat = (i % 2 == 0 ? 1 : -1) * size.width * 0.16
                    let control = CGPoint(x: (start.x + end.x) / 2 + bow,
                                           y: (start.y + end.y) / 2)
                    let p = quadraticPoint(start, control, end, t: CGFloat(travelPhase))

                    let scale = 0.7 + CGFloat(rawPhase) * 0.5
                    var iconCtx = ctx
                    iconCtx.opacity = alpha
                    iconCtx.translateBy(x: p.x, y: p.y)
                    iconCtx.scaleBy(x: scale, y: scale)
                    drawFileIcon(&iconCtx, kind: i % 6, color: Self.iconPalette[i % Self.iconPalette.count])
                }
            }
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
    }

    private func easeInOut(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c < 0.5 ? 2 * c * c : 1 - pow(-2 * c + 2, 2) / 2
    }

    private func quadraticPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let x = u*u*p0.x + 2*u*t*p1.x + t*t*p2.x
        let y = u*u*p0.y + 2*u*t*p1.y + t*t*p2.y
        return CGPoint(x: x, y: y)
    }

    private func drawGlow(_ ctx: inout GraphicsContext, at point: CGPoint, radius: CGFloat, color: Color, intensity: Double) {
        let rect = CGRect(x: point.x - radius, y: point.y - radius, width: radius*2, height: radius*2)
        let gradient = Gradient(stops: [
            .init(color: color.opacity(intensity), location: 0),
            .init(color: color.opacity(intensity * 0.35), location: 0.5),
            .init(color: color.opacity(0), location: 1),
        ])
        ctx.fill(Path(ellipseIn: rect),
                 with: .radialGradient(gradient, center: point, startRadius: 0, endRadius: radius))
    }

    private func drawMacScreen(_ ctx: inout GraphicsContext, center: CGPoint, accent: Color) {
        let w: CGFloat = 60, h: CGFloat = 40
        let rect = CGRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color(hex: "#0C0C12")))
        ctx.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(Color(hex: "#6A7090")), lineWidth: 1.6)
        let standTop = CGRect(x: center.x - 10, y: rect.maxY, width: 20, height: 5)
        ctx.fill(Path(roundedRect: standTop, cornerRadius: 1.5), with: .color(Color(hex: "#6A7090")))
        let base = CGRect(x: center.x - 16, y: rect.maxY + 6, width: 32, height: 3)
        ctx.fill(Path(roundedRect: base, cornerRadius: 1.5), with: .color(Color(hex: "#6A7090").opacity(0.8)))
    }

    private func drawAppWindow(_ ctx: inout GraphicsContext, center: CGPoint) {
        let w: CGFloat = 70, h: CGFloat = 46
        let rect = CGRect(x: center.x - w/2, y: center.y - h/2, width: w, height: h)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(Color(hex: "#15151C")))
        ctx.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(Color.white.opacity(0.12)), lineWidth: 1)
        let dotColors = [Color(hex: "#E05555"), Color(hex: "#E0B155"), Color(hex: "#55C27A")]
        for (i, c) in dotColors.enumerated() {
            let d: CGFloat = 4
            let dot = CGRect(x: rect.minX + 6 + CGFloat(i) * 8, y: rect.minY + 5, width: d, height: d)
            ctx.fill(Path(ellipseIn: dot), with: .color(c))
        }
        // Small ATLAS sparkle mark, centered
        let s: CGFloat = 12
        var mark = Path()
        let c = CGPoint(x: center.x, y: center.y + 6)
        mark.move(to: CGPoint(x: c.x, y: c.y - s/2))
        mark.addLine(to: CGPoint(x: c.x + s*0.18, y: c.y - s*0.18))
        mark.addLine(to: CGPoint(x: c.x + s/2, y: c.y))
        mark.addLine(to: CGPoint(x: c.x + s*0.18, y: c.y + s*0.18))
        mark.addLine(to: CGPoint(x: c.x, y: c.y + s/2))
        mark.addLine(to: CGPoint(x: c.x - s*0.18, y: c.y + s*0.18))
        mark.addLine(to: CGPoint(x: c.x - s/2, y: c.y))
        mark.addLine(to: CGPoint(x: c.x - s*0.18, y: c.y - s*0.18))
        mark.closeSubpath()
        ctx.fill(mark, with: .color(Color.white.opacity(0.85)))
    }

    /// Small program-icon glyphs (waveform, note, knob, file, plug, folder) —
    /// same set as the website version, just drawn as Canvas paths instead
    /// of inline SVG.
    private func drawFileIcon(_ ctx: inout GraphicsContext, kind: Int, color: Color) {
        let chipRect = CGRect(x: -8, y: -8, width: 16, height: 16)
        ctx.fill(Path(roundedRect: chipRect, cornerRadius: 4), with: .color(color))

        var glyph = Path()
        switch kind {
        case 0: // waveform
            for (dx, dy) in [(-4.0, 2.0), (-1.3, 4.0), (1.3, 5.0), (4.0, 1.0)] {
                glyph.move(to: .init(x: dx, y: dy))
                glyph.addLine(to: .init(x: dx, y: -dy))
            }
        case 1: // music note
            glyph.addEllipse(in: CGRect(x: -3.5, y: 2, width: 3, height: 2.6))
            glyph.move(to: .init(x: -1, y: 3.3))
            glyph.addLine(to: .init(x: -1, y: -4.5))
            glyph.addLine(to: .init(x: 3, y: -5.3))
        case 2: // knob/dial
            glyph.addEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
            glyph.move(to: .init(x: 0, y: 0))
            glyph.addLine(to: .init(x: 0, y: -4))
        case 3: // generic file
            glyph.move(to: .init(x: -3.5, y: -5))
            glyph.addLine(to: .init(x: 1, y: -5))
            glyph.addLine(to: .init(x: 3.5, y: -2.5))
            glyph.addLine(to: .init(x: 3.5, y: 5))
            glyph.addLine(to: .init(x: -3.5, y: 5))
            glyph.closeSubpath()
        case 4: // plug/jack
            glyph.addEllipse(in: CGRect(x: -1.6, y: -5.5, width: 3.2, height: 3.2))
            glyph.move(to: .init(x: 0, y: -2.5))
            glyph.addLine(to: .init(x: 0, y: 2))
            glyph.move(to: .init(x: -3, y: 5))
            glyph.addLine(to: .init(x: -1, y: 1))
            glyph.addLine(to: .init(x: 1, y: 1))
            glyph.addLine(to: .init(x: 3, y: 5))
        default: // folder
            glyph.addRoundedRect(in: CGRect(x: -4.5, y: -2.5, width: 9, height: 6), cornerSize: .init(width: 1, height: 1))
            glyph.move(to: .init(x: -4.5, y: -1))
            glyph.addLine(to: .init(x: 4.5, y: -1))
        }
        ctx.stroke(glyph, with: .color(color == Color(hex: "#E8ECFF") ? Color(hex: "#20244A") : .white), lineWidth: 1.3)
    }
}
