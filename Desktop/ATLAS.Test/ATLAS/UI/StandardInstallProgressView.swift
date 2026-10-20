import SwiftUI

// Standard (non-TITAN) installation progress view.
// Adapts AppState + Logger to the shared ATLASTransferAnimation visual.
// No changes to AppState, Logger, or any engine.
struct StandardInstallProgressView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var logger: Logger

    // Parsed from log entries — presentation only, never fed back to engine
    @State private var installedFilePaths: [String] = []
    @State private var receiptIDs: [String] = []
    @State private var showDetails = false

    // MARK: - Derived display state

    private var isRunning: Bool {
        appState.phase == .installing || appState.phase == .processing ||
        appState.phase == .verifying  || appState.phase == .cleanup
    }

    private var statusText: String {
        appState.progressStep.isEmpty ? appState.statusMessage : appState.progressStep
    }

    private var fileName: String {
        appState.selectedFileURL?.deletingPathExtension().lastPathComponent ?? ""
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 16) {

                // Product name
                if !fileName.isEmpty {
                    Text(fileName)
                        .font(.atlasFont(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#C8D0F0"))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Shared transfer animation — Folder → Mac
                ATLASTransferAnimation(mode: .install, isAnimating: isRunning)
                    .padding(.horizontal, 32)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(hex: "#0F1120"))
                            .frame(height: 7)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color(hex: "#5B8DEF").opacity(0.85), Color(hex: "#3ECFB2")],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(14, geo.size.width * appState.progress), height: 7)
                            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: appState.progress)
                    }
                }
                .frame(height: 7)
                .padding(.horizontal, 32)

                // Status + percentage
                HStack {
                    Text(statusText)
                        .font(.atlasFont(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#8A92BC"))
                        .lineLimit(1)
                        .animation(.easeInOut(duration: 0.2), value: statusText)
                    Spacer()
                    Text("\(Int(appState.progress * 100))%")
                        .font(.atlasFont(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#353860"))
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 32)

            Spacer(minLength: 0)

            // Collapsible details
            VStack(spacing: 0) {
                Color.atlasSeparator.frame(height: 1)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { showDetails.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Details")
                            .font(.atlasFont(size: 11, weight: .medium))
                            .foregroundColor(Color.atlasSubtitle)
                        Spacer()
                        Image(systemName: showDetails ? "chevron.down" : "chevron.up")
                            .font(.atlasFont(size: 9, weight: .semibold))
                            .foregroundColor(Color.atlasTertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if showDetails {
                    Color.atlasSeparator.frame(height: 1)
                    detailsPanel
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .background(Color.atlasDeepBG)
        }
        .onAppear { parseLogEntries() }
        .onChange(of: logger.entries.count) { _ in parseLogEntries() }
    }

    // MARK: - Details panel

    @ViewBuilder
    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {

            if !installedFilePaths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("INSTALLED FILES")
                        .font(.atlasFont(size: 9, weight: .semibold))
                        .foregroundColor(Color.atlasTertiary)
                        .tracking(0.8)
                    ForEach(installedFilePaths, id: \.self) { path in
                        HStack(spacing: 7) {
                            Image(systemName: fileIcon(for: path))
                                .font(.atlasFont(size: 9))
                                .foregroundColor(Color.atlasAccent.opacity(0.55))
                                .frame(width: 12)
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.atlasFont(size: 10.5))
                                .foregroundColor(Color.atlasSubtitle)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            if !receiptIDs.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("RECEIPTS")
                        .font(.atlasFont(size: 9, weight: .semibold))
                        .foregroundColor(Color.atlasTertiary)
                        .tracking(0.8)
                    ForEach(receiptIDs, id: \.self) { id in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color.atlasAccent.opacity(0.45))
                                .frame(width: 4, height: 4)
                            Text(id)
                                .font(.atlasFont(size: 10, design: .monospaced))
                                .foregroundColor(Color.atlasSubtitle)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("ACTIVITY LOG")
                    .font(.atlasFont(size: 9, weight: .semibold))
                    .foregroundColor(Color.atlasTertiary)
                    .tracking(0.8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(logger.entries.indices, id: \.self) { i in
                                let (ts, msg) = split(logger.entries[i])
                                HStack(alignment: .top, spacing: 8) {
                                    Text(ts)
                                        .font(.atlasFont(size: 9, design: .monospaced))
                                        .foregroundColor(Color.atlasTertiary)
                                        .frame(width: 52, alignment: .leading)
                                        .lineLimit(1)
                                    Text(msg)
                                        .font(.atlasFont(size: 9.5, design: .monospaced))
                                        .foregroundColor(Color.atlasSubtitle)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .id(i)
                            }
                        }
                        .padding(10)
                    }
                    .frame(maxHeight: 150)
                    .background(Color.atlasBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75)
                    )
                    .onChange(of: logger.entries.count) { _ in
                        withAnimation { proxy.scrollTo(logger.entries.count - 1, anchor: .bottom) }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private func parseLogEntries() {
        var files: [String] = []
        var receipts: [String] = []
        for entry in logger.entries {
            let msg = entry.count > 11 ? String(entry.dropFirst(11)) : entry
            if msg.hasPrefix("  Installed: ") {
                let path = String(msg.dropFirst("  Installed: ".count)).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty && !files.contains(path) { files.append(path) }
            } else if msg.hasPrefix("  Receipt: ") {
                let id = String(msg.dropFirst("  Receipt: ".count)).trimmingCharacters(in: .whitespaces)
                if !id.isEmpty && !receipts.contains(id) { receipts.append(id) }
            }
        }
        installedFilePaths = files
        receiptIDs = receipts
    }

    private func split(_ entry: String) -> (String, String) {
        guard entry.hasPrefix("["), let bracket = entry.firstIndex(of: "]") else { return ("", entry) }
        let ts  = String(entry[entry.startIndex...bracket])
        let msg = String(entry[entry.index(after: bracket)...]).trimmingCharacters(in: .whitespaces)
        return (ts, msg)
    }

    private func fileIcon(for path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "component":   return "puzzlepiece.fill"
        case "vst3", "vst": return "puzzlepiece.fill"
        case "app":         return "app.fill"
        case "pkg":         return "shippingbox.fill"
        case "dylib":       return "gearshape.fill"
        case "framework":   return "gearshape.2.fill"
        default:            return "doc.fill"
        }
    }
}
