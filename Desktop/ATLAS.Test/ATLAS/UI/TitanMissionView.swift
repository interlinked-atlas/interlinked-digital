import SwiftUI

struct TitanMissionView: View {
    @ObservedObject var mission: TitanMission
    let onBegin:  () -> Void
    let onCancel: () -> Void

    @State private var phraseIndex = 0
    @State private var showSteps   = false
    @State private var barAnim     = false

    var allDone:   Bool { mission.steps.allSatisfy { $0.status == .done || $0.status == .skipped } }
    var anyFailed: Bool { mission.steps.contains { $0.status == .failed } }

    private var progress: Double {
        guard !mission.steps.isEmpty else { return 0 }
        let done = mission.steps.filter {
            $0.status == .done || $0.status == .skipped || $0.status == .failed
        }.count
        return Double(done) / Double(mission.steps.count)
    }

    private let activePhrases = [
        "Unpacking files…",
        "Writing to disk…",
        "Registering software…",
        "Configuring the installation…",
        "Verifying components…",
        "Applying patch…",
        "Finalizing changes…",
        "Almost there…",
    ]

    private var displayPhrase: String {
        if mission.isComplete {
            return anyFailed ? "Some steps need attention." : "All done."
        }
        if mission.isRunning {
            if !mission.currentNote.isEmpty && mission.currentNote.count < 52 {
                return mission.currentNote
            }
            return activePhrases[phraseIndex % activePhrases.count]
        }
        return "Ready to begin."
    }

    private var accentColor: Color {
        if anyFailed          { return Color(hex: "#E05555") }
        if mission.isComplete { return Color(hex: "#3ECFB2") }
        if mission.isRunning  { return Color(hex: "#5B8DEF") }
        return Color(hex: "#3ECFB2")
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Progress + status ─────────────────────────────────────────
            VStack(spacing: 14) {

                // Title row
                HStack {
                    AtlasStarView(size: 14, isAnimating: mission.isRunning)
                    Text("Installing…")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#8A92BC"))
                    Spacer()
                    if mission.isRunning {
                        let done = mission.steps.filter {
                            $0.status == .done || $0.status == .skipped
                        }.count
                        Text("\(done) / \(mission.steps.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "#353860"))
                    }
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(hex: "#0F1120"))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.9), accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing)
                            )
                            .frame(
                                width: mission.isComplete
                                    ? geo.size.width
                                    : max(12, geo.size.width * (mission.isRunning ? progress : 0)),
                                height: 6)
                            .animation(.spring(response: 0.6, dampingFraction: 0.82), value: progress)
                            .animation(.spring(response: 0.6, dampingFraction: 0.82), value: mission.isComplete)

                        // Shimmer while running
                        if mission.isRunning {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.14), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing)
                                )
                                .frame(
                                    width: max(12, geo.size.width * progress),
                                    height: 6)
                                .animation(
                                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                    value: barAnim)
                        }
                    }
                }
                .frame(height: 6)

                // Status phrase + percentage
                HStack {
                    Text(displayPhrase)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#C0C8E8"))
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.28), value: displayPhrase)
                    Spacer()
                    if mission.isComplete {
                        Text(anyFailed ? "Failed" : "Done")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(accentColor)
                    } else {
                        Text(mission.isRunning
                             ? "\(Int(progress * 100))%"
                             : "\(mission.steps.count) steps")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(hex: "#353860"))
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)

            // ── Collapsible step list ─────────────────────────────────────
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSteps.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text(showSteps ? "Hide Steps" : "Steps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "#353860"))
                        Image(systemName: showSteps ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "#353860"))
                        Spacer()
                        HStack(spacing: 3) {
                            ForEach(mission.steps.prefix(16)) { step in
                                Circle()
                                    .fill(stepDotColor(step.status))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if showSteps {
                    Rectangle().fill(Color(hex: "#13151F")).frame(height: 1)
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(mission.steps.enumerated()), id: \.element.id) { idx, step in
                                    StepRow(step: step, index: idx + 1)
                                        .id(step.id)
                                    if idx < mission.steps.count - 1 {
                                        Rectangle()
                                            .fill(Color(hex: "#0F1020"))
                                            .frame(height: 1)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                        .onChange(of: mission.currentNote) { _ in
                            if let running = mission.steps.first(where: { $0.status == .running }) {
                                withAnimation { proxy.scrollTo(running.id, anchor: .center) }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color(hex: "#0A0C18"))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(hex: "#1A1D30"), lineWidth: 0.75))
            .padding(.horizontal, 16)

            // ── Action buttons ────────────────────────────────────────────
            HStack(spacing: 10) {
                if !mission.isComplete {
                    Button(L(.titanCancel)) { onCancel() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#6B7399"))
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Color(hex: "#0A0D1C"))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color(hex: "#1E2240"), lineWidth: 1))
                        .buttonStyle(.plain)
                        .disabled(mission.isRunning)
                        .opacity(mission.isRunning ? 0.35 : 1)

                    Spacer()

                    Button(L(.titanBegin)) { onBegin() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(mission.isRunning ? Color(hex: "#6B7399") : Color(hex: "#08090E"))
                        .padding(.horizontal, 22).padding(.vertical, 9)
                        .background(mission.isRunning ? Color(hex: "#1A1D30") : Color(hex: "#3ECFB2"))
                        .cornerRadius(8)
                        .buttonStyle(.plain)
                        .disabled(mission.isRunning)
                } else {
                    Spacer()
                    Button("Done") { onCancel() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#08090E"))
                        .padding(.horizontal, 28).padding(.vertical, 9)
                        .background(anyFailed ? Color(hex: "#E05555") : Color(hex: "#3ECFB2"))
                        .cornerRadius(8)
                        .buttonStyle(.plain)
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(Color(hex: "#07080F"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [accentColor.opacity(0.18), Color(hex: "#5B8DEF").opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing),
                lineWidth: 0.75))
        .onAppear {
            barAnim = true
            startPhraseCycling()
        }
    }

    private func startPhraseCycling() {
        DispatchQueue.global(qos: .background).async {
            while true {
                Thread.sleep(forTimeInterval: mission.isRunning ? 3.2 : 6.0)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) { phraseIndex += 1 }
                }
            }
        }
    }

    private func stepDotColor(_ status: TitanMissionStep.Status) -> Color {
        switch status {
        case .pending:  return Color(hex: "#1E2240")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .skipped:  return Color(hex: "#353860")
        }
    }
}

// MARK: - Step row

private struct StepRow: View {
    let step:  TitanMissionStep
    let index: Int

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(bgColor).frame(width: 20, height: 20)
                if step.status == .running {
                    ProgressView()
                        .scaleEffect(0.52)
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#5B8DEF")))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(iconColor)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.system(size: 10, weight: step.status == .running ? .semibold : .regular))
                    .foregroundColor(step.status == .pending ? Color(hex: "#2A2D40") : Color(hex: "#B0B8D8"))
                    .lineLimit(1)
                if !step.resultNote.isEmpty {
                    Text(step.resultNote)
                        .font(.system(size: 9))
                        .foregroundColor(step.status == .failed ? Color(hex: "#E05555") : Color(hex: "#404468"))
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(step.status == .running ? Color(hex: "#0D1020") : Color.clear)
    }

    private var bgColor: Color {
        switch step.status {
        case .pending:  return Color(hex: "#0E1020")
        case .running:  return Color(hex: "#0D1530")
        case .done:     return Color(hex: "#3ECFB2").opacity(0.1)
        case .failed:   return Color(hex: "#E05555").opacity(0.1)
        case .skipped:  return Color(hex: "#181A28")
        }
    }
    private var iconName: String {
        switch step.status {
        case .pending:  return "circle"
        case .running:  return "circle.fill"
        case .done:     return "checkmark"
        case .failed:   return "xmark"
        case .skipped:  return "minus"
        }
    }
    private var iconColor: Color {
        switch step.status {
        case .pending:  return Color(hex: "#202238")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .skipped:  return Color(hex: "#353860")
        }
    }
}
