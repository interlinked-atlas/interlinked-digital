import SwiftUI

struct ATLASStorageSectionView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var engine: ATLASCleanerEngine
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared

    var onReviewCleaner: () -> Void = {}
    var onUpgradeCleaner: () -> Void = {}
    var onQuickScan: () -> Void = {}

    // Positional flags — lets LibraryDashboardView render disk-space and cleaner
    // as separate Library sections while sharing the same engine instance.
    // Both default to true so every existing call site is unaffected.
    var showDiskSpace: Bool = true
    var showCleaner: Bool   = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDiskSpace {
                diskSpaceRow
            }
            if showCleaner {
                Rectangle()
                    .fill(Color.atlasSeparator.opacity(0.6))
                    .frame(height: 1)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                cleanerRow
            }
        }
        .onAppear {
            // Only trigger the scan from the instance that displays cleaner data.
            if showCleaner {
                Task { await engine.scan(store: store) }
            }
        }
    }

    // MARK: - Disk space

    private var diskSpaceRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L(.available))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                Text(availableFormatted)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.atlasLabel)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(L(.total))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                Text(totalFormatted)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - ATLAS CLEANER™ entry row

    private var cleanerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(auth.isSubscribed ? Color(hex: "#3ECFB2") : Color.atlasSubtitle.opacity(0.4))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("ATLAS CLEANER™")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(auth.isSubscribed ? Color.atlasLabel : Color.atlasSubtitle.opacity(0.6))
                    if !auth.isSubscribed {
                        Text("ATLAS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: "#3ECFB2").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                cleanerSubtitle
            }

            Spacer()

            cleanerActionButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .tourAnchor("cleanerRow")
    }

    @ViewBuilder
    private var cleanerSubtitle: some View {
        switch engine.scanState {
        case .idle:
            Text(L(.scanning))
                .font(.system(size: 10))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
        case .scanning:
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 10, height: 10)
                Text(L(.scanning))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            }
        case .complete:
            if engine.items.isEmpty {
                Text(L(.nothingToClean))
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.5))
            } else {
                Text("\(formattedBytes(engine.totalReclaimableBytes)) recoverable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
        case .failed:
            Text(L(.scanUnavailable))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(0.7))
        }
    }

    @ViewBuilder
    private var cleanerActionButton: some View {
        if auth.isSubscribed {
            HStack(spacing: 6) {
                Button(L(.quickScan)) { onQuickScan() }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#3ECFB2").opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(.plain)
                if case .complete = engine.scanState, !engine.items.isEmpty {
                    Button(L(.review)) { onReviewCleaner() }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .buttonStyle(.plain)
                }
            }
        } else {
            if case .complete = engine.scanState, !engine.items.isEmpty {
                Button(L(.upgrade)) { onUpgradeCleaner() }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#3ECFB2").opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Volume stats

    private var volumeAttributes: [FileAttributeKey: Any]? {
        try? FileManager.default.attributesOfFileSystem(forPath: "/")
    }

    private var availableBytes: Int64 {
        (volumeAttributes?[.systemFreeSize] as? Int) .flatMap { Int64(exactly: $0) } ?? 0
    }

    private var totalBytes: Int64 {
        (volumeAttributes?[.systemSize] as? Int).flatMap { Int64(exactly: $0) } ?? 0
    }

    private var availableFormatted: String { formattedBytes(availableBytes) }
    private var totalFormatted: String    { formattedBytes(totalBytes) }

    private func formattedBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }
}
