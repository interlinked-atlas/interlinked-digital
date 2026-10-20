import SwiftUI

// MARK: - Recovery slot filter

private enum RecoveryFilter: String, CaseIterable {
    case all        = "All"
    case ready      = "Ready"
    case installing = "Installing"
    case installed  = "Installed"
    case failed     = "Failed"
    case pending    = "Pending"

    var localizedLabel: String {
        switch self {
        case .all:        return L(.filterAll)
        case .ready:      return L(.filterReady)
        case .installing: return L(.filterInstalling)
        case .installed:  return L(.filterInstalled)
        case .failed:     return L(.filterFailed)
        case .pending:    return L(.filterPending)
        }
    }
}

// MARK: - RecoveryModeView

struct RecoveryModeView: View {
    @ObservedObject var engine: RecoveryModeEngine
    var onExit: () -> Void
    var onViewLibrary: (() -> Void)?
    @ObservedObject private var langMgr = LanguageManager.shared

    @State private var activeFilter: RecoveryFilter = .all

    var body: some View {
        if engine.isComplete {
            completionScreen
        } else {
            mainScreen
        }
    }

    // MARK: - Main screen

    private var mainScreen: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)

            if engine.slots.count > 5 {
                filterBar
                Divider().opacity(0.3)
            }

            slotList

            Divider().opacity(0.4)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atlasBackground()
        .onAppear {
            AppDelegate.mainWindow?.setContentSize(CGSize(width: 760, height: 620))
            AppDelegate.mainWindow?.minSize = CGSize(width: 680, height: 580)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "lifepreserver")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "#3ECFB2"))
            VStack(alignment: .leading, spacing: 1) {
                Text("ATLAS RECOVERY KIT™")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.atlasLabel)
                Text("Recovery Mode")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
            Spacer()
            Text("\(engine.slots.count) product\(engine.slots.count == 1 ? "" : "s")")
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            Button("Exit") { onExit() }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.atlasElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(RecoveryFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private func filterChip(_ filter: RecoveryFilter) -> some View {
        let count = filterCount(filter)
        let isActive = activeFilter == filter

        return Button {
            activeFilter = filter
        } label: {
            HStack(spacing: 4) {
                Text(filter.localizedLabel)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                if filter != .all, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isActive ? Color(hex: "#3ECFB2") : Color.atlasSubtitle.opacity(0.4))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            isActive
                                ? Color(hex: "#3ECFB2").opacity(0.12)
                                : Color.atlasElevated.opacity(0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .foregroundColor(isActive ? Color(hex: "#3ECFB2") : Color.atlasSubtitle.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                isActive
                    ? Color(hex: "#3ECFB2").opacity(0.10)
                    : Color.atlasElevated.opacity(0.35)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func filterCount(_ filter: RecoveryFilter) -> Int {
        switch filter {
        case .all:        return engine.slots.count
        case .ready:      return engine.readyCount
        case .installing: return engine.installingCount
        case .installed:  return engine.successCount
        case .failed:     return engine.failedCount
        case .pending:    return engine.pendingCount
        }
    }

    private var filteredSlots: [RecoverySlot] {
        switch activeFilter {
        case .all:        return engine.slots
        case .ready:      return engine.slots.filter { $0.state == .ready }
        case .installing: return engine.slots.filter { $0.state.isInstalling }
        case .installed:  return engine.slots.filter { if case .success = $0.state { return true }; return false }
        case .failed:     return engine.slots.filter { if case .failure = $0.state { return true }; return false }
        case .pending:    return engine.slots.filter {
            if case .waitingForInstaller = $0.state { return true }
            if case .unsupportedFormat = $0.state { return true }
            return false
        }
        }
    }

    // MARK: - Slot list

    private var slotList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSlots) { slot in
                    RecoverySlotRow(
                        slot: slot,
                        onSetInstaller: { url in
                            engine.setInstaller(id: slot.id, url: url)
                        },
                        onInstall: {
                            Task { await engine.installSingleSlot(id: slot.id) }
                        },
                        onSkip: {
                            engine.skip(id: slot.id)
                        },
                        onRetry: {
                            engine.retrySlot(id: slot.id)
                        }
                    )
                    if slot.id != filteredSlots.last?.id {
                        Divider()
                            .padding(.horizontal, 14)
                            .opacity(0.3)
                    }
                }
                if filteredSlots.isEmpty {
                    emptyFilterState
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilterState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundColor(Color.atlasSubtitle.opacity(0.2))
            Text("No \(activeFilter.rawValue.lowercased()) products")
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            // Status counts
            HStack(spacing: 10) {
                if engine.successCount > 0 {
                    footerStat("\(engine.successCount)", label: L(.statDone), color: Color(hex: "#3ECFB2"))
                }
                if engine.failedCount > 0 {
                    footerStat("\(engine.failedCount)", label: L(.titanStepFailed), color: Color(hex: "#E05555"))
                }
                if engine.skippedCount > 0 {
                    footerStat("\(engine.skippedCount)", label: L(.statSkipped), color: Color.atlasSubtitle.opacity(0.4))
                }
                if engine.limitReachedCount > 0 {
                    footerStat("\(engine.limitReachedCount)", label: L(.statLimit), color: Color(hex: "#F0A030"))
                }
                if engine.pendingCount > 0 {
                    footerStat("\(engine.pendingCount)", label: L(.statPending), color: Color.atlasSubtitle.opacity(0.3))
                }
            }

            Spacer()

            if engine.isRunningBatch {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.65)
                    Text(L(.queueStatusInstalling))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                }
            } else if engine.readyCount > 0 {
                Button(L(.installReadyProducts)) {
                    Task { await engine.installAllReady() }
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color(hex: "#3ECFB2"))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
            } else {
                Text(L(.dropInstallersAbove))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.35))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func footerStat(_ value: String, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.45))
        }
    }

    // MARK: - Completion screen

    private var completionScreen: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 42))
                    .foregroundColor(Color(hex: "#3ECFB2"))

                VStack(spacing: 6) {
                    Text(L(.recoveryComplete))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.atlasLabel)
                    Text(completionSummary)
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                // Detail counts
                HStack(spacing: 20) {
                    completionStat(engine.successCount, label: L(.statReinstalled), color: Color(hex: "#3ECFB2"))
                    if engine.failedCount > 0 {
                        completionStat(engine.failedCount, label: L(.titanStepFailed), color: Color(hex: "#E05555"))
                    }
                    if engine.skippedCount > 0 {
                        completionStat(engine.skippedCount, label: L(.statSkipped), color: Color.atlasSubtitle.opacity(0.5))
                    }
                    if engine.limitReachedCount > 0 {
                        completionStat(engine.limitReachedCount, label: L(.stateLimitReached), color: Color(hex: "#F0A030"))
                    }
                }

                HStack(spacing: 10) {
                    if let onViewLibrary {
                        Button(L(.viewInLibrary)) { onViewLibrary() }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#3ECFB2").opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .buttonStyle(.plain)
                    }
                    Button(L(.exitRecoveryMode)) { onExit() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atlasBackground()
    }

    private var completionSummary: String {
        var parts: [String] = []
        if engine.successCount > 0 {
            parts.append("\(engine.successCount) product\(engine.successCount == 1 ? "" : "s") reinstalled successfully")
        }
        if engine.failedCount > 0 {
            parts.append("\(engine.failedCount) failed")
        }
        if engine.skippedCount > 0 {
            parts.append("\(engine.skippedCount) skipped")
        }
        return parts.joined(separator: " · ")
    }

    private func completionStat(_ count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(count)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
        }
    }
}
