import SwiftUI

struct TitanMissionView: View {
    @ObservedObject var mission: TitanMission
    let onBegin:  () -> Void
    let onCancel: () -> Void

    @State private var showDetails = false
    @State private var phraseIndex = 0

    var allDone:   Bool { mission.steps.allSatisfy { $0.status == .done || $0.status == .skipped } }
    var anyFailed: Bool { mission.steps.contains { $0.status == .failed } }

    private var progress: Double {
        guard !mission.steps.isEmpty else { return 0 }
        let done = mission.steps.filter {
            $0.status == .done || $0.status == .skipped || $0.status == .failed
        }.count
        return Double(done) / Double(mission.steps.count)
    }

    private var pct: Int { Int(progress * 100) }

    private let phrases = [
        "Unpacking files…",
        "Writing to disk…",
        "Registering software…",
        "Applying patch…",
        "Verifying components…",
        "Configuring the installation…",
        "Finalizing changes…",
        "Almost there…",
    ]

    private var statusLine: String {
        if mission.isComplete { return anyFailed ? "Some steps failed." : "Installation complete." }
        if mission.isRunning {
            if !mission.currentNote.isEmpty && mission.currentNote.count < 60 {
                return mission.currentNote
            }
            return phrases[phraseIndex % phrases.count]
        }
        return "Ready to begin."
    }

    private var accentColor: Color {
        if anyFailed          { return Color(hex: "#E05555") }
        if mission.isComplete { return Color(hex: "#3ECFB2") }
        return Color(hex: "#5B8DEF")
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header bar ────────────────────────────────────────────────
            HStack(spacing: 8) {
                AtlasStarView(size: 13, isAnimating: mission.isRunning)
                Text("TITAN CORE")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(hex: "#3ECFB2").opacity(0.75))
                Spacer()
                Text(mission.isComplete ? (anyFailed ? "Failed" : "Done") : "\(pct)%")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(accentColor)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)

            // ── Progress bar ──────────────────────────────────────────────
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(hex: "#0E1020"))
                        .frame(height: 8)

                    // Fill
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(
                            colors: [accentColor.opacity(0.8), accentColor],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(
                            width: mission.isComplete
                                ? geo.size.width
                                : max(8, geo.size.width * (mission.isRunning ? progress : 0)),
                            height: 8)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: progress)
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: mission.isComplete)
                }
            }
            .frame(height: 8)
            .padding(.horizontal, 20)

            // ── Status text ───────────────────────────────────────────────
            HStack {
                Text(statusLine)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A92BC"))
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.25), value: statusLine)
                Spacer()
                if mission.isRunning || mission.isComplete {
                    let done = mission.steps.filter {
                        $0.status == .done || $0.status == .skipped
                    }.count
                    Text("\(done) of \(mission.steps.count) steps")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "#353860"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            // ── Under the hood ────────────────────────────────────────────
            // Shows the current running step inline; user can expand for all steps.
            VStack(spacing: 0) {

                // Current step live readout (always visible)
                if let running = mission.steps.first(where: { $0.status == .running }) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#5B8DEF")))
                            .frame(width: 14, height: 14)
                        Text(running.title)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#5B8DEF"))
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                } else if mission.isComplete {
                    HStack(spacing: 8) {
                        Image(systemName: anyFailed ? "xmark.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor)
                        Text(anyFailed
                             ? "\(mission.steps.filter { $0.status == .failed }.count) step(s) failed"
                             : "All \(mission.steps.count) steps completed")
                            .font(.system(size: 10))
                            .foregroundColor(accentColor.opacity(0.85))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                } else if !mission.isRunning {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#353860"))
                        Text("\(mission.steps.count) steps planned")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#353860"))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }

                // Expand/collapse toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(showDetails ? "Hide details" : "Show details")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#353860"))
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Color(hex: "#353860"))
                        Spacer()
                        // Dot mini-map
                        HStack(spacing: 3) {
                            ForEach(mission.steps.prefix(18)) { step in
                                Circle()
                                    .fill(dotColor(step.status))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                // Full step list
                if showDetails {
                    Rectangle().fill(Color(hex: "#0D0F1C")).frame(height: 1)
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(mission.steps.enumerated()), id: \.element.id) { i, step in
                                    StepRow(step: step, index: i + 1)
                                        .id(step.id)
                                    if i < mission.steps.count - 1 {
                                        Rectangle()
                                            .fill(Color(hex: "#0F1020"))
                                            .frame(height: 1)
                                            .padding(.leading, 42)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                        .onChange(of: mission.currentNote) { _ in
                            if let r = mission.steps.first(where: { $0.status == .running }) {
                                withAnimation { proxy.scrollTo(r.id, anchor: .center) }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(Color(hex: "#090B16"))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(hex: "#161828"), lineWidth: 0.75))
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // ── Buttons ───────────────────────────────────────────────────
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
                        .opacity(mission.isRunning ? 0.3 : 1)
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
                    colors: [accentColor.opacity(0.15), Color.clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 0.75))
        .onAppear { startPhraseCycling() }
    }

    private func startPhraseCycling() {
        DispatchQueue.global(qos: .background).async {
            while true {
                Thread.sleep(forTimeInterval: mission.isRunning ? 3.5 : 6.0)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.25)) { phraseIndex += 1 }
                }
            }
        }
    }

    private func dotColor(_ status: TitanMissionStep.Status) -> Color {
        switch status {
        case .pending:  return Color(hex: "#1A1D30")
        case .running:  return Color(hex: "#5B8DEF")
        case .done:     return Color(hex: "#3ECFB2")
        case .failed:   return Color(hex: "#E05555")
        case .skipped:  return Color(hex: "#2A2D40")
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
                        .scaleEffect(0.5)
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#5B8DEF")))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 8, weight: .bold))
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
        case .skipped:  return Color(hex: "#303350")
        }
    }
}
