import SwiftUI

// Inline installation view — embedded in the main ATLAS window.
// Auto-starts the mission on appear, shows a progress bar, and a
// collapsible step-detail section (collapsed by default).
struct TitanMissionView: View {
    @ObservedObject var mission: TitanMission
    let adminPassword: String
    let onDone: () -> Void

    @State private var showDetails = true

    // MARK: - Derived state

    private var progress: Double {
        guard !mission.steps.isEmpty else { return 0 }
        let done = mission.steps.filter {
            $0.status == .done || $0.status == .skipped || $0.status == .failed
        }.count
        return Double(done) / Double(mission.steps.count)
    }

    private var anyFailed: Bool {
        mission.steps.contains { $0.status == .failed }
    }

    private var accentColor: Color {
        if anyFailed          { return Color(hex: "#E05555") }
        if mission.isComplete { return Color(hex: "#3ECFB2") }
        return Color(hex: "#5B8DEF")
    }

    private var statusText: String {
        if mission.isComplete {
            return anyFailed ? "Finished with errors" : "Installation complete"
        }
        if mission.isRunning {
            if let running = mission.steps.first(where: { $0.status == .running }) {
                return running.title
            }
            return "Working…"
        }
        return "Preparing…"
    }

    private var fileName: String {
        mission.sourceURL.deletingPathExtension().lastPathComponent
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {

            // ── Centre area: icon + name + bar + status ───────────────────
            Spacer(minLength: 0)

            VStack(spacing: 18) {
                AtlasStarView(size: 38, isAnimating: mission.isRunning && !mission.isComplete)
                    .animation(.easeInOut(duration: 0.3), value: mission.isRunning)

                Text(fileName)
                    .font(.system(size: 15, weight: .semibold))
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
                                width: max(14, geo.size.width * (mission.isComplete ? 1.0 : progress)),
                                height: 7)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: progress)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: mission.isComplete)
                    }
                }
                .frame(height: 7)
                .padding(.horizontal, 32)

                // Status + percentage
                HStack {
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#8A92BC"))
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: statusText)

                    Spacer()

                    if mission.isComplete {
                        Text(anyFailed ? "Failed" : "Done")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accentColor)
                    } else {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Color(hex: "#353860"))
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 32)

            // ── Done button ───────────────────────────────────────────────
            if mission.isComplete {
                Button(anyFailed ? "Close" : "Done") { onDone() }
                    .font(.system(size: 13, weight: .semibold))
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
                // Divider
                Color(hex: "#131628").frame(height: 1)

                // Toggle row
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Details")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#444870"))

                        // Mini dot indicators
                        HStack(spacing: 3) {
                            ForEach(mission.steps.prefix(20)) { step in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(dotColor(step.status))
                                    .frame(width: 5, height: 5)
                            }
                        }

                        Spacer()

                        Image(systemName: showDetails ? "chevron.down" : "chevron.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#333558"))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if showDetails {
                    Color(hex: "#0D0F1E").frame(height: 1)
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(mission.steps.enumerated()), id: \.element.id) { idx, step in
                                    StepRow(step: step, index: idx + 1)
                                        .id(step.id)
                                    if idx < mission.steps.count - 1 {
                                        Color(hex: "#0D0F1E").frame(height: 1)
                                            .padding(.leading, 44)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .onChange(of: mission.currentNote) { _ in
                            if let r = mission.steps.first(where: { $0.status == .running }) {
                                withAnimation { proxy.scrollTo(r.id, anchor: .center) }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .background(Color(hex: "#080A18"))
        }
        .onAppear {
            guard !mission.isRunning && !mission.isComplete else { return }
            let pw = adminPassword
            Task { await mission.execute(adminPassword: pw) }
        }
    }

    private func dotColor(_ status: TitanMissionStep.Status) -> Color {
        switch status {
        case .pending:  return Color(hex: "#1E2240")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .skipped:  return Color(hex: "#2A2D42")
        }
    }
}

// MARK: - Step row

private struct StepRow: View {
    let step: TitanMissionStep
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(iconFG)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.system(size: 10, weight: step.status == .running ? .semibold : .regular))
                    .foregroundColor(step.status == .pending ? Color(hex: "#282B40") : Color(hex: "#A8B0D0"))
                    .lineLimit(1)
                if !step.resultNote.isEmpty {
                    Text(step.resultNote)
                        .font(.system(size: 9))
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
    private var iconFG: Color {
        switch step.status {
        case .pending:  return Color(hex: "#1E2138")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .skipped:  return Color(hex: "#2E3150")
        }
    }
}
