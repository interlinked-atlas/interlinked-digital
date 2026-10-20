import SwiftUI

struct PluginScanView: View {
    let results: [PluginCheckResult]
    var onDismiss: (() -> Void)? = nil

    @State private var expanded = false

    private var presentCount: Int { results.filter(\.isPresent).count }
    private var missingCount: Int { results.filter { !$0.isPresent }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Collapsed header (always visible) ────────────────────
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#9B6DFF"))

                    Text("\(results.count) plugin\(results.count == 1 ? "" : "s") detected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)

                    // Status pills
                    if presentCount > 0 {
                        statusPill("\(presentCount) visible", color: Color(hex: "#2ECC8A"))
                    }
                    if missingCount > 0 {
                        statusPill("\(missingCount) missing", color: Color(hex: "#E05555"))
                    }

                    Spacer()

                    // Expand / collapse chevron
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle)

                    // Dismiss button
                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // ── Expanded detail ───────────────────────────────────────
            if expanded && !results.isEmpty {
                Rectangle()
                    .fill(Color.atlasSeparator)
                    .frame(height: 1)
                    .padding(.horizontal, 12)

                VStack(spacing: 6) {
                    ForEach(results) { result in
                        PluginResultRow(result: result)
                    }
                }
                .padding(10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.atlasPanelBG)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.atlasBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func statusPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(4)
    }
}

// MARK: - Plugin result row

private struct PluginResultRow: View {
    let result: PluginCheckResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: result.isPresent ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.isPresent ? Color(hex: "#2ECC8A") : Color(hex: "#E05555"))
                .font(.system(size: 11))

            Text(result.pluginName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.atlasLabel)
                .lineLimit(1)

            formatChip(result.format)

            Spacer()

            if result.isPresent && !result.compatibleDAWs.isEmpty {
                Text(result.compatibleDAWs.joined(separator: ", "))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .lineLimit(1)
            } else if !result.isPresent {
                Text("Not found")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#E05555").opacity(0.8))
            } else {
                Text("No DAWs detected")
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.7))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func formatChip(_ ext: String) -> some View {
        let color = formatColor(ext)
        Text(ext.uppercased().replacingOccurrences(of: "PLUGIN", with: ""))
            .font(.system(size: 8, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }

    private func formatColor(_ ext: String) -> Color {
        switch ext {
        case "component": return Color(hex: "#7C3AED")
        case "vst3", "vst": return Color(hex: "#3B82F6")
        case "aaxplugin": return Color(hex: "#F0A030")
        default:          return Color.atlasSubtitle
        }
    }
}
