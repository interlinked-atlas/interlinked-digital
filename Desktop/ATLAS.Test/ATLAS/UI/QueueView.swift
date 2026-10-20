import SwiftUI

struct QueueView: View {
    @ObservedObject var queue: InstallQueue
    @ObservedObject private var langMgr = LanguageManager.shared
    let onStartQueue: () -> Void
    let onRemove: (UUID) -> Void
    let onRetry: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.atlasFont(size: 12))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                Text(L(.queueInstallQueue))
                    .font(.atlasFont(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F0F2FF"))
                Spacer()
                Text("\(queue.items.count) file\(queue.items.count == 1 ? "" : "s")")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color(hex: "#696E7C"))

                if queue.isProcessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.65)
                            .tint(Color(hex: "#3ECFB2"))
                        Text(L(.queueStatusInstalling))
                            .font(.atlasFont(size: 12))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                    }
                } else {
                    Button {
                        onStartQueue()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.atlasFont(size: 11))
                            Text(L(.queueInstallAll))
                                .font(.atlasFont(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#08090E"))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#3ECFB2"))
                        .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                    .disabled(queue.waitingCount == 0)
                    .opacity(queue.waitingCount == 0 ? 0.4 : 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Item rows
            VStack(spacing: 4) {
                ForEach(queue.items) { item in
                    QueueRowView(
                        item: item,
                        isProcessing: queue.isProcessing,
                        onRemove: { onRemove(item.id) },
                        onRetry: { onRetry(item.id) }
                    )
                }
            }
            .padding(.horizontal, 10)

            // Footer actions — secondary actions only
            if !queue.isProcessing && queue.failedCount > 0 {
                HStack(spacing: 8) {
                    Button {
                        queue.clear()
                    } label: {
                        Text(L(.queueClearWaiting))
                            .font(.atlasFont(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#696E7C"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#08091A"))
                            .cornerRadius(7)
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        queue.retryAllFailed()
                        onStartQueue()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.atlasFont(size: 10))
                            Text("Retry \(queue.failedCount) failed")
                                .font(.atlasFont(size: 12, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#F0A030"))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color(hex: "#F0A030").opacity(0.1))
                        .cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7)
                            .stroke(Color(hex: "#F0A030").opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            } else if !queue.isProcessing {
                HStack {
                    Button {
                        queue.clear()
                    } label: {
                        Text(L(.queueClearWaiting))
                            .font(.atlasFont(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#696E7C"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#08091A"))
                            .cornerRadius(7)
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .background(Color.atlasPanelBG)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.18), radius: 14, y: 3)
    }
}

struct QueueRowView: View {
    let item: QueueItem
    let isProcessing: Bool
    let onRemove: () -> Void
    let onRetry: () -> Void

    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var showDetails      = false
    @State private var showActivationInfo = false

    private var isInstalling: Bool {
        if case .installing = item.status { return true }
        return false
    }

    /// Non-nil when installer documentation was parsed and has useful content.
    /// Shown regardless of exact status so users can always access it.
    private var activationDocInfo: InstallerDocInfo? {
        guard let doc = item.scanResult?.docInfo, !doc.isEmpty else { return nil }
        return doc
    }

    var body: some View {
        if case .success = item.status {
            // Minimal completed row — just checkmark + name
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "#2ECC8A"))
                    .font(.atlasFont(size: 12))
                    .frame(width: 18)

                Text(item.fileName)
                    .font(.atlasFont(size: 12))
                    .foregroundColor(Color(hex: "#8890B0"))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(L(.queueStatusInstalled))
                    .font(.atlasFont(size: 10))
                    .foregroundColor(Color(hex: "#2ECC8A").opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        } else {
            // Full row for waiting / scanning / installing / failure
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    statusIcon
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.fileName)
                            .font(.atlasFont(size: 12, weight: .medium))
                            .foregroundColor(Color.atlasLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if case .failure(let reason) = item.status {
                            Text(friendlyReason(reason))
                                .font(.atlasFont(size: 10))
                                .foregroundColor(Color(hex: "#E05555"))
                                .lineLimit(2)
                        } else if case .demoWarning(let kw) = item.status {
                            Text("Demo Mode Detected: \(kw)")
                                .font(.atlasFont(size: 10))
                                .foregroundColor(Color(hex: "#F0A030"))
                                .lineLimit(2)
                        } else if case .activationRequired = item.status {
                            Text("Installed — open in your DAW and activate")
                                .font(.atlasFont(size: 10))
                                .foregroundColor(Color(hex: "#F0A030"))
                                .lineLimit(2)
                        } else if case .verificationWarning = item.status {
                            Text("Installed — AU registration pending")
                                .font(.atlasFont(size: 10))
                                .foregroundColor(Color(hex: "#F0A030"))
                                .lineLimit(2)
                        } else if case .installing = item.status, !item.progressStep.isEmpty {
                            Text(item.progressStep)
                                .font(.atlasFont(size: 10))
                                .foregroundColor(Color(hex: "#696E7C"))
                                .lineLimit(1)
                        } else {
                            Text(statusLabel)
                                .font(.atlasFont(size: 10))
                                .foregroundColor(statusColor)
                        }
                    }

                    Spacer()

                    if item.canRunParallel, case .waiting = item.status {
                        Text("parallel")
                            .font(.atlasFont(size: 9, weight: .medium))
                            .foregroundColor(Color(hex: "#3ECFB2").opacity(0.8))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "#3ECFB2").opacity(0.1))
                            .cornerRadius(4)
                    }

                    Text(item.fileType)
                        .font(.atlasFont(size: 10, weight: .medium))
                        .foregroundColor(Color(hex: "#696E7C"))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(hex: "#0F1327"))
                        .cornerRadius(4)

                    if case .waiting = item.status {
                        Button(action: onRemove) {
                            Image(systemName: "xmark")
                                .font(.atlasFont(size: 9))
                                .foregroundColor(Color(hex: "#696E7C"))
                        }
                        .buttonStyle(.plain)
                    }

                    if case .failure = item.status, !isProcessing {
                        Button(action: onRetry) {
                            Image(systemName: "arrow.clockwise")
                                .font(.atlasFont(size: 10))
                                .foregroundColor(Color(hex: "#F0A030"))
                        }
                        .buttonStyle(.plain)
                    }

                    // Show activation info button when docs were parsed from installer media
                    if activationDocInfo != nil {
                        Button(action: { showActivationInfo = true }) {
                            HStack(spacing: 3) {
                                Image(systemName: "key.fill")
                                    .font(.atlasFont(size: 9))
                                Text("Info")
                                    .font(.atlasFont(size: 9, weight: .medium))
                            }
                            .foregroundColor(Color(hex: "#F0C56A"))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: "#F0C56A").opacity(0.12))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showActivationInfo) {
                            if let doc = activationDocInfo {
                                ActivationInfoView(
                                    productName: item.fileName,
                                    docInfo: doc
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                if case .installing = item.status {
                    // Reuses the exact same visual treatment as a single-file install
                    // (StandardInstallProgressView) — the shared transfer animation plus
                    // the identical progress-bar/status-row styling — just bound to this
                    // row's own item.progress/item.progressStep instead of the global
                    // AppState, so bulk and single-file installs look identical.
                    VStack(spacing: 10) {
                        ATLASTransferAnimation(mode: .install, isAnimating: true)
                            .frame(height: 44)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(hex: "#0F1120"))
                                    .frame(height: 7)
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "#5B8DEF").opacity(0.85), Color(hex: "#3ECFB2")],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(14, geo.size.width * item.progress), height: 7)
                                    .animation(.spring(response: 0.55, dampingFraction: 0.8), value: item.progress)
                            }
                        }
                        .frame(height: 7)

                        HStack {
                            Text(item.progressStep.isEmpty ? "Installing…" : item.progressStep)
                                .font(.atlasFont(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#8A92BC"))
                                .lineLimit(1)
                                .animation(.easeInOut(duration: 0.2), value: item.progressStep)
                            Spacer()
                            Text("\(Int(item.progress * 100))%")
                                .font(.atlasFont(size: 10, design: .monospaced))
                                .foregroundColor(Color(hex: "#353860"))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, showDetails ? 4 : 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // ── Details panel ─────────────────────────────────────────
                if isInstalling || (!item.detailLog.isEmpty && item.detailLog.count > 0) {
                    VStack(spacing: 0) {
                        // Toggle row
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(L(.logDetails))
                                    .font(.atlasFont(size: 10, weight: .medium))
                                    .foregroundColor(Color(hex: "#444870"))
                                Spacer()
                                Image(systemName: showDetails ? "chevron.down" : "chevron.up")
                                    .font(.atlasFont(size: 8, weight: .semibold))
                                    .foregroundColor(Color(hex: "#333558"))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(Color(hex: "#080A18"))

                        if showDetails {
                            Color(hex: "#0D0F1E").frame(height: 1)
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 0) {
                                    if item.detailLog.isEmpty {
                                        Text(L(.queueWaitingForSteps))
                                            .font(.atlasFont(size: 9))
                                            .foregroundColor(Color(hex: "#2A2D42"))
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                    } else {
                                        ForEach(Array(item.detailLog.enumerated()), id: \.offset) { idx, entry in
                                            HStack(alignment: .top, spacing: 6) {
                                                Circle()
                                                    .fill(idx == item.detailLog.count - 1 && isInstalling
                                                          ? Color(hex: "#7090B8") : Color(hex: "#1E2240"))
                                                    .frame(width: 4, height: 4)
                                                    .padding(.top, 3)
                                                Text(entry)
                                                    .font(.atlasFont(size: 9))
                                                    .foregroundColor(idx == item.detailLog.count - 1 && isInstalling
                                                                     ? Color(hex: "#5A80A8") : Color(hex: "#3A3D5A"))
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer()
                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 3)
                                            if idx < item.detailLog.count - 1 {
                                                Color(hex: "#0D0F1E").frame(height: 1).padding(.leading, 20)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxHeight: 120)
                            .background(Color(hex: "#060815"))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
            }
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(rowBorderColor, lineWidth: 0.75))
            .animation(.atlasFade, value: progressBarVisible)
        }
    }

    private var progressBarVisible: Bool {
        if case .installing = item.status { return true }
        return false
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .waiting:
            Image(systemName: "clock")
                .foregroundColor(Color(hex: "#696E7C"))
                .font(.atlasFont(size: 12))
        case .scanning:
            ProgressView()
                .scaleEffect(0.65)
                .tint(Color(hex: "#3B82F6"))
        case .installing:
            ProgressView()
                .scaleEffect(0.65)
                .tint(Color(hex: "#3ECFB2"))
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(Color(hex: "#2ECC8A"))
                .font(.atlasFont(size: 12))
        case .failure:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(Color(hex: "#E05555"))
                .font(.atlasFont(size: 12))
        case .demoWarning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "#F0A030"))
                .font(.atlasFont(size: 12))
        case .activationRequired:
            Image(systemName: "key.fill")
                .foregroundColor(Color(hex: "#F0A030"))
                .font(.atlasFont(size: 12))
        case .verificationWarning:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(Color(hex: "#F0A030"))
                .font(.atlasFont(size: 12))
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .waiting:                      return L(.queueStatusWaiting)
        case .scanning:                     return L(.queueStatusScanning)
        case .installing:                   return L(.queueStatusInstalling)
        case .success:                      return L(.queueStatusInstalled)
        case .failure(let r):               return r
        case .demoWarning(let kw):          return "⚠️ \(L(.queueStatusDemoWarning)): \(kw)"
        case .activationRequired:           return L(.queueStatusActivation)
        case .verificationWarning:          return L(.queueStatusVerification)
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .waiting:              return Color(hex: "#696E7C")
        case .scanning:             return Color(hex: "#3B82F6")
        case .installing:           return Color(hex: "#3ECFB2")
        case .success:              return Color(hex: "#2ECC8A")
        case .failure:              return Color(hex: "#E05555")
        case .demoWarning:          return Color(hex: "#F0A030")
        case .activationRequired:   return Color(hex: "#F0A030")
        case .verificationWarning:  return Color(hex: "#F0A030")
        }
    }

    private var rowBackground: Color {
        switch item.status {
        case .installing:   return Color.atlasAccent.opacity(0.04)
        case .failure:      return Color(hex: "#E05555").opacity(0.04)
        case .demoWarning:  return Color(hex: "#F0A030").opacity(0.04)
        default:            return Color.atlasDeepBG
        }
    }

    private var rowBorderColor: Color {
        switch item.status {
        case .installing:   return Color.atlasAccent.opacity(0.22)
        case .failure:      return Color(hex: "#E05555").opacity(0.18)
        case .demoWarning:  return Color(hex: "#F0A030").opacity(0.22)
        default:            return Color.atlasBorderSubtle
        }
    }
}
