import SwiftUI

struct VirusScanView: View {
    let result:    VirusScanResult
    let fileName:  String
    let onProceed: () -> Void
    let onDelete:  () -> Void
    let onCancel:  () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header badge
            verdictBadge
                .padding(.top, 28)

            // Summary
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(result.summaryLine)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A8A96"))
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)

            // Engine list (only if flagged)
            if !result.engines.isEmpty {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(result.engines.prefix(6), id: \.name) { engine in
                            HStack {
                                Text(engine.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "#CCCCCC"))
                                Spacer()
                                Text(engine.result)
                                    .font(.system(size: 10))
                                    .foregroundColor(engine.isPua ? Color(hex: "#F0A030") : Color(hex: "#EF5B5B"))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(hex: "#111113"))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(maxHeight: 180)
                .padding(.top, 16)
            }

            Spacer(minLength: 20)

            // Actions
            VStack(spacing: 8) {
                if result.isBlocking {
                    // Malicious — delete or cancel only
                    Button(action: onDelete) {
                        Label("Delete File", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(hex: "#EF5B5B").opacity(0.15))
                            .foregroundColor(Color(hex: "#EF5B5B"))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "#EF5B5B").opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button(action: onCancel) {
                        Text("Cancel Install")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.05))
                            .foregroundColor(Color(hex: "#8A8A96"))
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                } else {
                    // Clean, PUA, suspicious, unknown — can proceed
                    Button(action: onProceed) {
                        Text(result.isClear ? "Continue Install →" : "Proceed Anyway →")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(proceedColor.opacity(0.15))
                            .foregroundColor(proceedColor)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(proceedColor.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if result.isWarning {
                        Button(action: onDelete) {
                            Label("Delete File", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.04))
                                .foregroundColor(Color(hex: "#8A8A96"))
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(Color(hex: "#525260"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#0E0E10"))
    }

    // MARK: - Subviews

    private var verdictBadge: some View {
        ZStack {
            Circle()
                .fill(badgeColor.opacity(0.12))
                .frame(width: 64, height: 64)
            Image(systemName: badgeIcon)
                .font(.system(size: 26, weight: .medium))
                .foregroundColor(badgeColor)
        }
    }

    private var title: String {
        switch result.verdict {
        case .clean:      return "File is clean"
        case .unknown:    return "File not recognized"
        case .pua:        return "Crack / keygen detected"
        case .suspicious: return "Suspicious file"
        case .malicious:  return "Malware detected"
        }
    }

    private var badgeIcon: String {
        switch result.verdict {
        case .clean:      return "checkmark.shield.fill"
        case .unknown:    return "questionmark.circle.fill"
        case .pua:        return "exclamationmark.triangle.fill"
        case .suspicious: return "exclamationmark.triangle.fill"
        case .malicious:  return "xmark.shield.fill"
        }
    }

    private var badgeColor: Color {
        switch result.verdict {
        case .clean:      return Color(hex: "#3ECFB2")
        case .unknown:    return Color(hex: "#8A8A96")
        case .pua:        return Color(hex: "#F0A030")
        case .suspicious: return Color(hex: "#F0A030")
        case .malicious:  return Color(hex: "#EF5B5B")
        }
    }

    private var proceedColor: Color {
        result.isClear ? Color(hex: "#3ECFB2") : Color(hex: "#F0A030")
    }
}
