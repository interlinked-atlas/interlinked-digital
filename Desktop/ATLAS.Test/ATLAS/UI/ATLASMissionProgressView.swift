import SwiftUI

// Shared installation progress presentation.
// Driven entirely by MissionDisplayState — no TitanMission or AppState dependency.
// Used by both TITAN (complex) and Standard installation paths.
struct ATLASMissionProgressView: View {

    // Presentation state — passed in by callers, updated via onChange/let rebinding
    let state: MissionDisplayState

    // Called when the user taps "Begin Install".
    // nil → no button shown (standard/automatic installs).
    let onBeginInstall: (() -> Void)?

    // Called when the user taps "Done" or "Close" after completion.
    let onDone: () -> Void

    // Optional extra detail content shown inside the collapsible Details panel
    // when state.steps is empty (used by the standard install path for log/file info).
    let detailsContent: AnyView?

    @State private var showDetails = true

    // MARK: - Derived

    private var accentColor: Color {
        if state.anyFailed          { return Color(hex: "#E05555") }
        if state.isComplete         { return Color(hex: "#3ECFB2") }
        return Color(hex: "#5B8DEF")
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            Spacer(minLength: 0)

            VStack(spacing: 18) {
                AtlasStarView(size: 38, isAnimating: state.isRunning && !state.isComplete)
                    .animation(.easeInOut(duration: 0.3), value: state.isRunning)

                Text(state.fileName)
                    .font(.atlasFont(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#C8D0F0"))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: "#0F1120"))
                            .frame(height: 7)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(
                                colors: [accentColor.opacity(0.85), accentColor],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(
                                width: max(14, geo.size.width * (state.isComplete ? 1.0 : state.progress)),
                                height: 7)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: state.progress)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: state.isComplete)
                    }
                }
                .frame(height: 7)
                .padding(.horizontal, 32)

                // Status + percentage
                HStack {
                    Text(state.statusText)
                        .font(.atlasFont(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#8A92BC"))
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: state.statusText)

                    Spacer()

                    if state.isComplete {
                        Text(state.anyFailed ? "Failed" : "Done")
                            .font(.atlasFont(size: 11, weight: .semibold))
                            .foregroundColor(accentColor)
                    } else {
                        Text("\(Int(state.progress * 100))%")
                            .font(.atlasFont(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#353860"))
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 32)

            // ── Action button ─────────────────────────────────────────────
            if let beginInstall = onBeginInstall {
                Button("Begin Install") { beginInstall() }
                    .font(.atlasFont(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#08090E"))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#5B8DEF"))
                    .cornerRadius(9)
                    .buttonStyle(.plain)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if state.isComplete {
                Button(state.anyFailed ? "Close" : "Done") { onDone() }
                    .font(.atlasFont(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#08090E"))
                    .padding(.horizontal, 36)
                    .padding(.vertical, 10)
                    .background(accentColor)
                    .cornerRadius(9)
                    .buttonStyle(.plain)
                    .padding(.bottom, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            Spacer(minLength: 0)

            // ── Collapsible details ───────────────────────────────────────
            VStack(spacing: 0) {
                Color(hex: "#131628").frame(height: 1)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Details")
                            .font(.atlasFont(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#444870"))

                        // Dot indicators (from step array if available)
                        HStack(spacing: 3) {
                            ForEach(state.steps.prefix(20)) { step in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(dotColor(step.status))
                                    .frame(width: 5, height: 5)
                            }
                        }

                        Spacer()

                        Image(systemName: showDetails ? "chevron.down" : "chevron.up")
                            .font(.atlasFont(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#333558"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if showDetails {
                    Color(hex: "#0D0F1E").frame(height: 1)

                    if !state.steps.isEmpty {
                        // Named step list (TITAN path)
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(state.steps.enumerated()), id: \.element.id) { idx, step in
                                    MissionStepRow(step: step, index: idx + 1)
                                        .id(step.id)
                                    if idx < state.steps.count - 1 {
                                        Color(hex: "#0D0F1E").frame(height: 1)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let extra = detailsContent {
                        // Log/file panel (standard path)
                        extra
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            }
            .background(Color(hex: "#080A18"))
        }
    }

    private func dotColor(_ status: StepDisplayStatus) -> Color {
        switch status {
        case .pending:  return Color(hex: "#1E2240")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .warning:  return Color(hex: "#F0A030")
        case .skipped:  return Color(hex: "#2A2D42")
        }
    }
}

// MARK: - Step row

struct MissionStepRow: View {
    let step: MissionStepDisplay
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(iconBG).frame(width: 20, height: 20)
                if step.status == .running {
                    ProgressView()
                        .scaleEffect(0.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#5B8DEF")))
                } else {
                    Image(systemName: iconName)
                        .font(.atlasFont(size: 9, weight: .bold))
                        .foregroundColor(iconFG)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.atlasFont(size: 10, weight: step.status == .running ? .semibold : .regular))
                    .foregroundColor(step.status == .pending ? Color(hex: "#282B40") : Color(hex: "#A8B0D0"))
                    .lineLimit(1)
                if !step.resultNote.isEmpty {
                    Text(step.resultNote)
                        .font(.atlasFont(size: 9))
                        .foregroundColor(step.status == .failed ? Color(hex: "#E05555") : Color(hex: "#3A3D5A"))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(step.status == .running ? Color(hex: "#0C0F22") : Color.clear)
    }

    private var iconBG: Color {
        switch step.status {
        case .pending:  return Color(hex: "#0E1020")
        case .running:  return Color(hex: "#0D1530")
        case .done:     return Color(hex: "#3ECFB2").opacity(0.1)
        case .failed:   return Color(hex: "#E05555").opacity(0.12)
        case .warning:  return Color(hex: "#F0A030").opacity(0.10)
        case .skipped:  return Color(hex: "#181A28")
        }
    }
    private var iconName: String {
        switch step.status {
        case .pending:  return "circle"
        case .running:  return "circle.fill"
        case .done:     return "checkmark"
        case .failed:   return "xmark"
        case .warning:  return "exclamationmark"
        case .skipped:  return "minus"
        }
    }
    private var iconFG: Color {
        switch step.status {
        case .pending:  return Color(hex: "#1E2138")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .warning:  return Color(hex: "#F0A030")
        case .skipped:  return Color(hex: "#2E3150")
        }
    }
}
