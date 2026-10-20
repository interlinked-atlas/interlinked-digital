import SwiftUI

// Shared directional transfer animation.
// .install  → folder (top) to desktopcomputer (bottom) — files being installed onto the Mac
// .uninstall → desktopcomputer (top) to trash (bottom) — files being removed from the Mac
// Purely decorative Canvas view. No engine dependency. All inputs are primitives.

enum ATLASTransferMode {
    case install
    case uninstall
    case recovery
}

struct ATLASTransferAnimation: View {
    let mode: ATLASTransferMode
    let isAnimating: Bool   // particles flow when true, freeze when false

    private let particleCount = 6
    private let cycleDuration: Double = 2.8

    private var topSymbol: String {
        switch mode {
        case .install:   return "folder.fill"
        case .uninstall: return "desktopcomputer"
        case .recovery:  return "trash.fill"
        }
    }

    private var bottomSymbol: String {
        switch mode {
        case .install:   return "desktopcomputer"
        case .uninstall: return "trash.fill"
        case .recovery:  return "desktopcomputer"
        }
    }

    private var topColor: Color {
        switch mode {
        case .install:   return Color(hex: "#5B8DEF")
        case .uninstall: return Color(hex: "#8A92BC")
        case .recovery:  return Color(hex: "#3ECFB2")
        }
    }

    private var bottomColor: Color {
        switch mode {
        case .install:   return Color(hex: "#3ECFB2")
        case .uninstall: return Color(hex: "#E05555")
        case .recovery:  return Color(hex: "#5B8DEF")
        }
    }

    private var particleColor: Color {
        switch mode {
        case .install:   return Color(hex: "#7090B8")
        case .uninstall: return Color(hex: "#8A6080")
        case .recovery:  return Color(hex: "#3A9E8A")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top icon
            Image(systemName: topSymbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(topColor.opacity(0.85))
                .frame(height: 36)

            // Particle stream
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { tl in
                Canvas { ctx, size in
                    let t = isAnimating
                        ? tl.date.timeIntervalSinceReferenceDate
                        : 0          // frozen when not animating

                    for i in 0..<particleCount {
                        let phaseOffset = Double(i) / Double(particleCount)
                        let rawPhase = (t / cycleDuration + phaseOffset)
                            .truncatingRemainder(dividingBy: 1.0)

                        // Fade in at top, fade out at bottom
                        let alpha: Double
                        if rawPhase < 0.10      { alpha = rawPhase / 0.10 }
                        else if rawPhase > 0.80 { alpha = max(0, (1.0 - rawPhase) / 0.20) }
                        else                    { alpha = 1.0 }

                        // Horizontal scatter: gentle sine wave
                        let midX = size.width * 0.5
                        let x = midX + CGFloat(sin(rawPhase * .pi * 3.0 + Double(i)) * 10.0)
                        // Recovery: particles travel bottom→top (reversed direction)
                        let y = mode == .recovery
                            ? size.height * CGFloat(1.0 - rawPhase)
                            : size.height * CGFloat(rawPhase)

                        // Particles shrink slightly as they travel away from source
                        let scale = mode == .recovery
                            ? CGFloat(0.85 + rawPhase * 0.30)
                            : CGFloat(0.85 + (1.0 - rawPhase) * 0.30)

                        // Small document shape
                        let w: CGFloat = 7, h: CGFloat = 9, fold: CGFloat = 2.0
                        var body = Path()
                        body.move(to:    .init(x: -w/2,        y: -h/2))
                        body.addLine(to: .init(x:  w/2 - fold, y: -h/2))
                        body.addLine(to: .init(x:  w/2,        y: -h/2 + fold))
                        body.addLine(to: .init(x:  w/2,        y:  h/2))
                        body.addLine(to: .init(x: -w/2,        y:  h/2))
                        body.closeSubpath()

                        var fold2 = Path()
                        fold2.move(to:    .init(x: w/2 - fold, y: -h/2))
                        fold2.addLine(to: .init(x: w/2 - fold, y: -h/2 + fold))
                        fold2.addLine(to: .init(x: w/2,        y: -h/2 + fold))
                        fold2.closeSubpath()

                        let xform = CGAffineTransform(scaleX: scale, y: scale)
                            .concatenating(.init(translationX: x, y: y))

                        var docCtx = ctx
                        docCtx.opacity = alpha * 0.70
                        docCtx.concatenate(xform)
                        docCtx.fill(body,  with: .color(particleColor))
                        docCtx.fill(fold2, with: .color(bottomColor.opacity(0.55)))
                    }
                }
            }
            .frame(height: 72)

            // Bottom icon
            Image(systemName: bottomSymbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(bottomColor.opacity(0.85))
                .frame(height: 36)
        }
        .frame(maxWidth: .infinity)
    }
}
