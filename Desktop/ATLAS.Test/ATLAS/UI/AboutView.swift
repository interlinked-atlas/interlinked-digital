import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appearance = AppearanceManager.shared

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return v.isEmpty ? "1.0.0" : v
    }

    var body: some View {
        ZStack {
            Color.atlasPanelBG.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Close button ──────────────────────────────────────
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.atlasSubtitle)
                            .frame(width: 26, height: 26)
                            .background(Color.atlasElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20).padding(.top, 16)

                // ── Static identity block ─────────────────────────────
                VStack(spacing: 10) {
                    AtlasStarView(size: 64, isAnimating: true)

                    AtlasTitleText(size: 32, tracking: 10)

                    Text("v\(appVersion)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.atlasSubtitle)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.atlasElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(spacing: 4) {
                        Text("Developed by InterLinked®")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.atlasSubtitle)

                        Button {
                            NSWorkspace.shared.open(URL(string: "https://www.interlinked.digital/")!)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "globe")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#3ECFB2"))
                                Text("interlinked.digital")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "#3ECFB2"))
                                    .underline()
                            }
                        }
                        .buttonStyle(.plain)

                        Text("© InterLinked®. All rights reserved.")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasTertiary)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 20)

                // ── Divider ───────────────────────────────────────────
                Rectangle()
                    .fill(Color.atlasBorderSubtle)
                    .frame(height: 1)
                    .padding(.horizontal, 24)

                // ── Scrolling credits ─────────────────────────────────
                AboutCreditsScroll()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.bottom, 16)
            }
        }
        .frame(width: 400, height: 500)
        .preferredColorScheme(appearance.override)
    }
}

// MARK: - Auto-scrolling credits

private struct AboutCreditsScroll: View {
    @State private var offset: CGFloat = 0
    @State private var measured: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let containerH = geo.size.height

            ZStack(alignment: .top) {
                creditsContent
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(
                                key: CreditsHeightKey.self,
                                value: inner.size.height
                            )
                        }
                    )
                    .offset(y: offset)
                    .onPreferenceChange(CreditsHeightKey.self) { h in
                        guard h > 0, measured == 0 else { return }
                        measured = h
                        // Start just below the visible container, scroll up past content
                        offset = containerH
                        let totalTravel = containerH + h
                        let speed: Double = 38  // points per second
                        withAnimation(
                            .linear(duration: totalTravel / speed)
                            .repeatForever(autoreverses: false)
                        ) {
                            offset = -h
                        }
                    }
            }
            // Fade the top and bottom edges so text appears to emerge and disappear
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear,  location: 0.00),
                        .init(color: .black,  location: 0.12),
                        .init(color: .black,  location: 0.88),
                        .init(color: .clear,  location: 1.00),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .clipped()
    }

    private var creditsContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)

            // Tagline
            creditSection {
                creditHeading("ATLAS")
                Spacer().frame(height: 8)
                creditBody("A new way to Automate.")
                creditBody("A smarter way to Install.")
            }

            creditDivider()

            // TITAN CORE™
            creditSection {
                creditLabel("Integrated with")
                Spacer().frame(height: 6)
                creditHeadingTeal("TITAN CORE™")
                Spacer().frame(height: 8)
                creditBody("The intelligent installation and diagnostics\nengine that powers ATLAS.")
                Spacer().frame(height: 6)
                creditNote("Available in All Subscription Plans.")
            }

            creditDivider()

            // Credits
            creditSection {
                creditLabel("Developed by")
                Spacer().frame(height: 4)
                creditBody("InterLinked®")
                Spacer().frame(height: 10)
                creditNote("© InterLinked®. All rights reserved.")
            }

            Spacer().frame(height: 60)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 36)
    }

    // MARK: Helpers

    private func creditSection<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 2) { content() }
            .padding(.vertical, 22)
    }

    private func creditDivider() -> some View {
        Rectangle()
            .fill(Color.atlasBorderSubtle)
            .frame(width: 40, height: 1)
    }

    private func creditHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .tracking(0.5)
            .foregroundColor(Color.atlasLabel)
    }

    private func creditHeadingTeal(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .bold))
            .tracking(1)
            .foregroundColor(Color(hex: "#3ECFB2"))
    }

    private func creditBody(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Color.atlasSubtitle)
            .lineSpacing(4)
    }

    private func creditLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.5)
            .foregroundColor(Color.atlasTertiary)
    }

    private func creditNote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .italic()
            .foregroundColor(Color.atlasTertiary)
    }
}

private struct CreditsHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
