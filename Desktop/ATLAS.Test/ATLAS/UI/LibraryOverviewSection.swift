import SwiftUI

struct LibraryOverviewSection: View {
    @ObservedObject var viewModel: LibraryDashboardViewModel
    @ObservedObject private var langMgr = LanguageManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text(L(.overview))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 6)

            // Stat cards row — values use atlasInfo (blue) for Dashboard informational labels
            HStack(spacing: 8) {
                statCard(value: "\(viewModel.installedCount)", label: L(.queueStatusInstalled))
                statCard(value: "\(viewModel.disabledCount)", label: L(.disabled))
                statCard(value: "\(viewModel.archivedCount)", label: L(.archived))
            }
            .padding(.horizontal, 12)

            // Format pills — informational labels use atlasInfo (blue)
            if !viewModel.activeFormats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(viewModel.activeFormats, id: \.self) { fmt in
                        Text(fmt)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color.atlasInfo)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.atlasInfo.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            Rectangle()
                .fill(Color.atlasSeparator)
                .frame(height: 1)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color.atlasInfo)   // Dashboard informational → blue
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.atlasSubtitle.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.atlasElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
