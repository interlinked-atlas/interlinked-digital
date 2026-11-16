import SwiftUI

/// Shown the first time a user opens ATLAS Browser (and again afterward
/// unless they check "Don't show this again"). Carries the required
/// disclosure — ATLAS doesn't host these files and can't guarantee a
/// successful install — behind a mandatory checkbox before Continue even
/// unlocks.
struct AtlasBrowserSplashView: View {
    /// Bool param = whether "Don't show this again" was checked.
    var onContinue: (Bool) -> Void
    var onExit: (Bool) -> Void

    @State private var tosChecked = false
    @State private var dontShowAgain = false
    @State private var tosExpanded = false
    @State private var glowPulse = false

    private let tosText = """
    ATLAS Browser helps you discover third-party plugins, apps, and sample content from outside developers. Before continuing, please understand:

    • ATLAS does NOT host, store, or distribute any of these files. Every "Download Now" link sends you to the developer's or vendor's own site.

    • ATLAS does NOT guarantee a successful installation of anything downloaded through Browser. Unlike TITAN-verified installs, most third-party downloads are not something ATLAS has tested.

    • Always proceed with caution. Only download from sources you trust, verify the file before running it, and use your own judgment — ATLAS is not responsible for the content, safety, or behavior of third-party software obtained this way.
    """

    var body: some View {
        ZStack {
            glowBackground

            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 14) {
                        ATLASTransferAnimation(mode: .install, isAnimating: true, scale: 1.55)
                            .padding(.top, 14)
                            .padding(.bottom, 6)

                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                AtlasTitleText(size: 22, tracking: 6)
                                Text("BROWSER")
                                    .font(.system(size: 20, weight: .semibold))
                                    .tracking(1)
                                    .foregroundColor(Color.atlasLabel)
                                    .textCase(.uppercase)
                            }
                            .shadow(color: Color.atlasAccent.opacity(0.35), radius: 16)

                            Text("Browse plugins, apps, and sample content — all in one place.")
                                .font(.system(size: 12.5))
                                .foregroundColor(Color.atlasSubtitle)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 400)
                        }

                        Spacer(minLength: 20)

                        tosBox
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                }

                Rectangle().fill(Color.atlasSeparator).frame(height: 1)

                VStack(spacing: 10) {
                    Toggle(isOn: $dontShowAgain) {
                        Text("Don't show this again")
                            .font(.system(size: 11.5))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                    .toggleStyle(CheckboxToggleStyle())

                    HStack(spacing: 10) {
                        Button {
                            onExit(dontShowAgain)
                        } label: {
                            Text("Exit")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(Color.atlasLabel)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.atlasElevated)
                                .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onContinue(dontShowAgain)
                        } label: {
                            Text("Continue")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundColor(tosChecked ? .black : Color.atlasSubtitle.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    tosChecked
                                    ? LinearGradient(colors: [Color.atlasAccent, Color.atlasAccent.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.atlasElevated, Color.atlasElevated], startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.sm, style: .continuous))
                                .shadow(color: tosChecked ? Color.atlasAccent.opacity(0.45) : .clear, radius: 14, y: 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(!tosChecked)
                        .animation(.easeOut(duration: 0.2), value: tosChecked)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            }
        }
        .frame(width: 520, height: 600)
        .background(
            LinearGradient(colors: [Color.atlasDeepBG, Color.atlasPanelBG], startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.lg, style: .continuous))
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }

    /// Soft, slowly-breathing color blobs behind the content — same accent
    /// used throughout the app, just diffused. Opacity is low enough to
    /// read correctly in both light and dark mode without a special case.
    private var glowBackground: some View {
        ZStack {
            Circle()
                .fill(Color.atlasAccent)
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .opacity(glowPulse ? 0.22 : 0.12)
                .offset(x: -140, y: -180)

            Circle()
                .fill(Color.atlasAccent)
                .frame(width: 260, height: 260)
                .blur(radius: 80)
                .opacity(glowPulse ? 0.14 : 0.22)
                .offset(x: 150, y: 120)
        }
    }

    /// Compact by default — just the checkbox + a one-line summary, so the
    /// required disclosure doesn't dominate the page. Tapping "Read more"
    /// expands the full text inline without resizing the window.
    private var tosBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $tosChecked) {
                Text("I understand ATLAS doesn't host these files and can't guarantee a successful install.")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle)
            }
            .toggleStyle(CheckboxToggleStyle())

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { tosExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(tosExpanded ? "Hide details" : "Read the full disclosure")
                        .font(.system(size: 9.5, weight: .semibold))
                    Image(systemName: tosExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7.5, weight: .semibold))
                }
                .foregroundColor(Color.atlasAccent.opacity(0.85))
            }
            .buttonStyle(.plain)
            .padding(.leading, 26)

            if tosExpanded {
                Text(tosText)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.atlasSubtitle)
                    .lineSpacing(3)
                    .padding(.leading, 26)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color.atlasElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: ATLASRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ATLASRadius.md, style: .continuous)
                .strokeBorder(Color.atlasBorder, lineWidth: 1)
        )
    }
}

/// Theme-aware checkbox toggle — matches both light and dark mode via the
/// existing atlas* color tokens instead of hardcoded hex values.
private struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? Color.atlasAccent.opacity(0.15) : Color.atlasDeepBG)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(configuration.isOn ? Color.atlasAccent : Color.atlasBorder, lineWidth: 1.5)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.atlasAccent)
                }
            }
            .frame(width: 18, height: 18)
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)

            configuration.label
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { configuration.isOn.toggle() }
        }
    }
}

/// Wraps the splash + the real Browser grid: shows the splash first unless
/// the user already dismissed it for good, then hands off to AtlasBrowserView.
struct AtlasBrowserEntryView: View {
    var onExit: () -> Void
    /// Called whenever the size this view actually needs changes (splash
    /// vs. the real Browser grid are two different fixed sizes) — the
    /// caller is responsible for resizing the window to match. Fired on
    /// first appear AND on every splash->browser transition, since the
    /// caller's own .onAppear only fires once for this whole entry view
    /// and would otherwise keep the window sized for whichever child
    /// happened to be visible first.
    var onResize: (CGSize) -> Void
    var reloadSignal: AtlasBrowserReloadSignal = AtlasBrowserReloadSignal()

    @AppStorage("atlasBrowserSplashDismissed") private var splashDismissed = false
    @State private var proceeded = false

    private var showingSplash: Bool { !(splashDismissed || proceeded) }

    var body: some View {
        Group {
            if showingSplash {
                AtlasBrowserSplashView(
                    onContinue: { dontShowAgain in
                        if dontShowAgain { splashDismissed = true }
                        proceeded = true
                    },
                    onExit: { dontShowAgain in
                        if dontShowAgain { splashDismissed = true }
                        onExit()
                    }
                )
            } else {
                AtlasBrowserView(onClose: onExit, reloadSignal: reloadSignal)
            }
        }
        .onAppear { onResize(showingSplash ? CGSize(width: 520, height: 600) : CGSize(width: 860, height: 620)) }
        .onChange(of: showingSplash) { isSplash in
            onResize(isSplash ? CGSize(width: 520, height: 600) : CGSize(width: 860, height: 620))
        }
    }
}
