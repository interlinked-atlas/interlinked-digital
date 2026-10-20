import SwiftUI
import AppKit

struct SplashView: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) var colorScheme

    @State private var opacity: Double = 0
    @State private var scale: Double  = 0.88
    @State private var taglineOpacity: Double = 0
    @State private var completed = false

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 18) {
            LiquidMetalView(size: 220, clipToCircle: false,
                            videoFile: {
                                let override = AppearanceManager.shared.override
                                let effectivelyDark = override == .dark || (override == nil && colorScheme == .dark)
                                return effectivelyDark ? "atlas-splash" : "atlas-splash-light"
                            }(),
                            onVideoEnd: { finish() })

            VStack(spacing: 8) {
                if isDark {
                    AtlasTitleText(size: 48, tracking: 16)
                } else {
                    AtlasTitleText(size: 48, tracking: 16)
                        .colorInvert()
                }

                Text("by InterLinked\u{00AE}")
                    .font(.system(size: 12, weight: .light))
                    .foregroundColor(Color.atlasOnGlassSecondary)
                    .tracking(2.5)
                    .opacity(taglineOpacity)
            }
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same Liquid Chrome Glass shell as the main window, so the splash feels
        // like it belongs to the same app rather than a flat opaque placeholder.
        .atlasGlass(.shell, cornerRadius: 0)
        .onAppear { animate() }
    }

    private func animate() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
            opacity = 1
            scale   = 1
        }
        withAnimation(.easeIn(duration: 0.5).delay(0.5)) {
            taglineOpacity = 1
        }
        // Fallback: if video never fires onVideoEnd, dismiss after 8s
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            finish()
        }
    }

    private func finish() {
        guard !completed else { return }
        completed = true
        withAnimation(.easeIn(duration: 0.45)) {
            opacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onComplete()
        }
    }
}
