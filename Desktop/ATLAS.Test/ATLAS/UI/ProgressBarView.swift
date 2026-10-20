import SwiftUI

// Looping animated bar for indeterminate operations (scan, classify)
struct IndeterminateBar: View {
    @State private var phase: CGFloat = -0.4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color(hex: "#0F1120")
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#3ECFB2").opacity(0), Color(hex: "#3ECFB2"), Color(hex: "#7090B8"), Color(hex: "#7090B8").opacity(0)],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: geo.size.width * phase)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

struct ATLASProgressBar: View {
    let progress: Double    // 0.0 – 1.0  (0.0 = indeterminate / animating bar)
    let stepLabel: String
    var danger: Bool = false

    // True when progress is 0 — show animated sweep instead of static empty bar
    private var isIndeterminate: Bool { progress < 0.01 }

    @State private var shimmerPhase: CGFloat = -0.5
    @State private var dotPulse: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var accentColor: Color {
        danger ? Color(hex: "#E05555") : Color.atlasAccent
    }

    private var defaultLabel: String {
        danger ? "Preparing…" : "Working…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Label row
            HStack(alignment: .center, spacing: 6) {
                // Animated dot when indeterminate
                if isIndeterminate {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 5, height: 5)
                        .opacity(dotPulse ? 1.0 : 0.25)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                                   value: dotPulse)
                        .onAppear { dotPulse = true }
                }
                Text(stepLabel.isEmpty ? defaultLabel : stepLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.atlasSubtitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.atlasSnap, value: stepLabel)
                Spacer()
                if isIndeterminate {
                    // Elapsed time ticker for indeterminate states
                    ElapsedTimeLabel(color: accentColor)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accentColor)
                }
            }

            // Track — indeterminate = looping sweep, determinate = fill bar
            GeometryReader { geo in
                let trackH: CGFloat = 3

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color(hex: scheme == .dark ? "#0E1020" : "#D8DCF0"))
                        .frame(height: trackH)

                    if isIndeterminate {
                        // Animated sweep (reuses IndeterminateBar logic inline)
                        IndeterminateFill(color: accentColor, height: trackH, width: geo.size.width)
                    } else {
                        let fillW = max(trackH * 2, geo.size.width * CGFloat(progress))

                        // Determinate fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: danger ? [
                                        .init(color: Color(hex: "#E05555"), location: 0),
                                        .init(color: Color(hex: "#F07040"), location: 1),
                                    ] : [
                                        .init(color: Color(hex: "#3ECFB2"), location: 0),
                                        .init(color: Color(hex: "#7090B8"), location: 0.6),
                                        .init(color: Color(hex: "#7B5DEF"), location: 1),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillW, height: trackH)
                            .shadow(color: accentColor.opacity(0.50), radius: 6, y: 0)
                            .overlay(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            stops: [
                                                .init(color: .clear, location: max(0, shimmerPhase - 0.20)),
                                                .init(color: .white.opacity(0.18), location: shimmerPhase),
                                                .init(color: .clear, location: min(1, shimmerPhase + 0.20)),
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                            .animation(.spring(response: 0.42, dampingFraction: 0.80), value: progress)
                            .clipped()

                        // Leading pulse dot
                        if progress > 0.02 && progress < 0.98 {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 6, height: 6)
                                .shadow(color: accentColor.opacity(0.80), radius: 5)
                                .offset(x: max(0, fillW - 3), y: 0)
                                .animation(.spring(response: 0.42, dampingFraction: 0.80), value: progress)
                        }
                    }
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(scheme == .dark ? Color(hex: "#07090F") : Color.white.opacity(0.65))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: danger ? [
                            Color(hex: "#E05555").opacity(0.22),
                            Color(hex: "#F07040").opacity(0.12),
                        ] : [
                            Color.atlasAccent.opacity(0.22),
                            Color(hex: "#7090B8").opacity(0.12),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 0.75
                )
        )
        .shadow(
            color: scheme == .dark ? .black.opacity(0.22) : .black.opacity(0.06),
            radius: 10, y: 2
        )
        .onAppear { startShimmer() }
        .onChange(of: progress) { _ in startShimmer() }
    }

    private func startShimmer() {
        shimmerPhase = -0.5
        withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
            shimmerPhase = 1.5
        }
    }
}

// Animated indeterminate sweep used inside ATLASProgressBar
private struct IndeterminateFill: View {
    let color: Color
    let height: CGFloat
    let width: CGFloat
    @State private var phase: CGFloat = -0.4

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [color.opacity(0), color, color.opacity(0.6), color.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .frame(width: width * 0.45, height: height)
            .shadow(color: color.opacity(0.6), radius: 5, y: 0)
            .offset(x: width * phase)
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    phase = 1.0
                }
            }
    }
}

// Shows elapsed seconds — resets when view appears
private struct ElapsedTimeLabel: View {
    let color: Color
    @State private var seconds = 0
    @State private var timer: Timer? = nil

    var body: some View {
        Text(formattedTime)
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(color.opacity(0.6))
            .onAppear {
                seconds = 0
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    seconds += 1
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }

    private var formattedTime: String {
        let m = seconds / 60
        let s = seconds % 60
        return m > 0 ? "\(m):\(String(format: "%02d", s))" : "\(s)s"
    }
}

// "ATLAS Seem Stuck?" nudge — appears after 15 s of scanning, auto-hides when done.
struct ScanStuckNudge: View {
    let onCancel: () -> Void

    @ObservedObject private var appState = AppState.shared
    @State private var visible   = false
    @State private var dismissed = false
    @State private var timer: Timer? = nil

    var body: some View {
        Group {
            if visible && !dismissed {
                HStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#F5A623"))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("ATLAS Seem Stuck?")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5D08A"))
                        Text("It's still scanning — large files like Ableton can take 20–30 seconds.")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#8A7A50"))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button("Keep Waiting") {
                            withAnimation { dismissed = true }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#6A70A0"))
                        .buttonStyle(.plain)

                        Button("Cancel") {
                            withAnimation { visible = false }
                            onCancel()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#E05555"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color(hex: "#1C1508"))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(hex: "#F5A623").opacity(0.25), lineWidth: 0.75)
                )
                .cornerRadius(9)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: visible)
        .animation(.easeInOut(duration: 0.2), value: dismissed)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
                if appState.phase == .scanning {
                    withAnimation { visible = true }
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
        .onChange(of: appState.phase) { phase in
            if phase != .scanning {
                withAnimation { visible = false }
                timer?.invalidate()
            }
        }
    }
}
