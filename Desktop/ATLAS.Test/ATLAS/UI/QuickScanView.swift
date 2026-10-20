import SwiftUI

// Read-only Quick Scan — checks only ATLAS-managed plugins for duplicate copies.
// Never crawls the filesystem. Uses InstallRecord.installedFiles as the sole source of truth.
// No trash, no delete, no Cleaner History involvement.

struct QuickScanView: View {
    @ObservedObject var store: HistoryStore
    @Environment(\.dismiss) private var dismiss

    @State private var duplicateItems: [CleanerItem] = []
    @State private var installerItems: [CleanerItem] = []
    @State private var isScanning = true
    @StateObject private var cleanerEngine = ATLASCleanerEngine()

    private var allItems: [CleanerItem] { duplicateItems + installerItems }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.atlasSeparator)

            if isScanning {
                scanningView
            } else if allItems.isEmpty {
                emptyView
            } else {
                resultsView
            }
        }
        .frame(width: 460, height: 480)
        .background(Color.atlasSessionHeader)
        .task {
            // Capture records on the main actor before going off-thread
            let active   = store.records
            let archived = store.archivedRecords
            let found = await Task.detached(priority: .utility) {
                ATLASCleanerEngine.quickScan(records: active, archivedRecords: archived)
            }.value
            duplicateItems  = found.filter { $0.category == .duplicatePlugin }
            installerItems  = found.filter { $0.category == .atlasInstallerArtifact }
            isScanning = false
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#3ECFB2"))
            VStack(alignment: .leading, spacing: 0) {
                Text("Quick Scan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                Text("ATLAS-managed plugins only")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.55))
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle)
                    .frame(width: 20, height: 20)
                    .background(Color.atlasElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().scaleEffect(0.9)
            Text("Checking ATLAS-managed plugins…")
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
            Text("No duplicate plugins found")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.atlasLabel)
            Text("All ATLAS-managed plugins appear to be unique.")
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            disclaimer
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Summary bar — duplicate count only (installer section has its own header)
            HStack {
                if duplicateItems.isEmpty {
                    Text("No duplicate plugins found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                } else {
                    Text("\(duplicateItems.count) duplicate plugin \(duplicateItems.count == 1 ? "copy" : "copies") found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                    Spacer()
                    if totalDuplicateBytes > 0 {
                        Text(formattedSize(totalDuplicateBytes))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Rectangle().fill(Color.atlasSeparator.opacity(0.6)).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    if !duplicateItems.isEmpty {
                        infoNote
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                            .padding(.bottom, 6)

                        ForEach(duplicateItems) { item in
                            duplicateRow(item)
                            if item.id != duplicateItems.last?.id {
                                Rectangle()
                                    .fill(Color.atlasSeparator.opacity(0.4))
                                    .frame(height: 1)
                                    .padding(.leading, 14)
                            }
                        }
                    }

                    if !installerItems.isEmpty {
                        installerArtifactsSection
                    }

                    disclaimer
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
            }

            Rectangle().fill(Color.atlasSeparator).frame(height: 1)
            footer
        }
    }

    // MARK: - ATLAS Installation Files section

    private var installerArtifactsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "archivebox")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
                Text("ATLAS Installation Files")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                Spacer()
                if installerTotalBytes > 0 {
                    Text(formattedSize(installerTotalBytes))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, duplicateItems.isEmpty ? 10 : 14)
            .padding(.bottom, 6)

            Rectangle().fill(Color.atlasSeparator.opacity(0.4)).frame(height: 1)

            ForEach(installerItems) { item in
                installerArtifactRow(item)
                if item.id != installerItems.last?.id {
                    Rectangle()
                        .fill(Color.atlasSeparator.opacity(0.4))
                        .frame(height: 1)
                        .padding(.leading, 14)
                }
            }
        }
    }

    private func installerArtifactRow(_ item: CleanerItem) -> some View {
        HStack(spacing: 8) {
            // Format badge
            Text(item.formatExtensions.first?.uppercased() ?? "—")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.atlasElevated)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName ?? URL(fileURLWithPath: item.path).lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                    .lineLimit(1)
                Text(compactPath(item.path))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                    .lineLimit(2)
                Text("Installer used by ATLAS")
                    .font(.system(size: 9))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.4))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let size = item.size {
                    Text(formattedSize(size))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                        .monospacedDigit()
                }

                if case .trashing = cleanerEngine.trashState {
                    ProgressView().scaleEffect(0.55).frame(width: 32)
                } else if case .success = cleanerEngine.trashResults[item.id] {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                } else {
                    Button("Trash") {
                        Task {
                            await cleanerEngine.trash(selectedIDs: [item.id], store: store)
                            installerItems.removeAll {
                                if case .success = cleanerEngine.trashResults[$0.id] { return true }
                                return false
                            }
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#E05555").opacity(0.85))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: "#E05555").opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func duplicateRow(_ item: CleanerItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Format badge
                Text(item.formatExtensions.first?.uppercased() ?? "—")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.atlasElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                Text(item.productName ?? URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                    .lineLimit(1)

                Spacer()

                if let size = item.size {
                    Text(formattedSize(size))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                        .monospacedDigit()
                }
            }

            // Duplicate copy (flagged)
            pathRow(
                label: "Duplicate",
                path: item.path,
                color: Color(hex: "#E05555").opacity(0.75)
            )

            // Kept copy
            if let kp = item.keepPath {
                pathRow(
                    label: "Kept",
                    path: kp,
                    color: Color(hex: "#3ECFB2").opacity(0.8)
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func pathRow(label: String, path: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 54, alignment: .trailing)
            Text(compactPath(path))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(Color.atlasSubtitle.opacity(0.55))
                .lineLimit(2)
        }
    }

    // MARK: - Info note and disclaimer

    private var infoNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
            Text("Quick Scan checks only plugins that ATLAS installed. Plugins installed by other tools are not included. This scan is read-only — use ATLAS CLEANER™ to remove duplicates.")
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(Color.atlasElevated.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var disclaimer: some View {
        Text("Only ATLAS-managed plugin installations are checked. Plugins installed outside ATLAS are not reported.")
            .font(.system(size: 9))
            .foregroundColor(Color.atlasSubtitle.opacity(0.35))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Color(hex: "#3ECFB2"))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Helpers

    private var totalDuplicateBytes: Int64 {
        duplicateItems.compactMap { $0.size }.reduce(0, +)
    }

    private var installerTotalBytes: Int64 {
        installerItems.compactMap { $0.size }.reduce(0, +)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB, .useKB]
        return f.string(fromByteCount: bytes)
    }

    // Trims home directory to ~ for readability
    private func compactPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
