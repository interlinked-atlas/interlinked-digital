import SwiftUI

struct TitanVScanView: View {
    let result: VScanResult
    let onProceed:         () -> Void   // install anyway (suspicious/license tool)
    let onQuarantine:      () -> Void   // move to quarantine folder
    let onDelete:          () -> Void   // permanently delete
    let onStripAndInstall: () -> Void   // remove malware, install clean payload
    let onCancel:          () -> Void   // go back

    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var showDeleteConfirm    = false
    @State private var showQuarantineConfirm = false
    @State private var expandedThreats      = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.atlasSeparator)
            ScrollView {
                VStack(spacing: 16) {
                    verdictCard
                    if !result.threats.isEmpty { threatList }
                    actionButtons
                }
                .padding(20)
            }
        }
        .background(Color(hex: "#0A0A0C"))
        .frame(width: 420)
        .confirmationDialog(
            "Delete \(result.scannedFile)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L(.deletePermanently), role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the file from your Mac. This cannot be undone.")
        }
        .confirmationDialog(
            "Move to ATLAS Quarantine?",
            isPresented: $showQuarantineConfirm,
            titleVisibility: .visible
        ) {
            Button(L(.moveToQuarantine)) { onQuarantine() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file will be isolated in a secure ATLAS quarantine folder. You can review or permanently delete it later in ATLAS Settings.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            // TITAN VSCAN™ wordmark
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.atlasAccent)
                Text("TITAN VSCAN")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.atlasLabel)
                    .kerning(1.5)
                Text("™")
                    .font(.system(size: 9))
                    .foregroundColor(Color.atlasSubtitle)
                    .offset(y: -4)
                Text("PRO")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color.atlasAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.atlasAccent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            Spacer()
            Text(result.scannedFile)
                .font(.system(size: 10))
                .foregroundColor(Color.atlasTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Verdict Card

    private var verdictCard: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(verdictColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: verdictIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(verdictColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(result.verdict.label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(verdictColor)
                        .kerning(1.5)
                    if result.verdict == .licenseTool {
                        Text("ALLOWED")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "#5E6AD2"))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "#5E6AD2").opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(result.summaryLine)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.atlasLabel)
                    .fixedSize(horizontal: false, vertical: true)
                if !result.hash.isEmpty {
                    Text("SHA-256: \(String(result.hash.prefix(16)))…")
                        .font(.system(size: 9, weight: .regular).monospaced())
                        .foregroundColor(Color.atlasTertiary)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(verdictColor.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(verdictColor.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Threat List

    private var threatList: some View {
        VStack(spacing: 0) {
            // Header row
            HStack {
                Text(L(.detectedThreats))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.atlasTertiary)
                    .kerning(1.5)
                Spacer()
                if result.threats.count > 3 {
                    Button {
                        withAnimation(.atlasSnap) { expandedThreats.toggle() }
                    } label: {
                        Text(expandedThreats ? L(.showLess) : String(format: L(.showAllFmt), result.threats.count))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.atlasAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().background(Color.atlasSeparator).padding(.horizontal, 14)

            let visible = expandedThreats ? result.threats : Array(result.threats.prefix(3))
            ForEach(visible) { threat in
                threatRow(threat)
                if threat.id != visible.last?.id {
                    Divider().background(Color.atlasSeparator).padding(.horizontal, 14)
                }
            }
        }
        .background(Color(hex: "#111113"))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.atlasBorder, lineWidth: 0.75)
        )
    }

    private func threatRow(_ threat: ThreatDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: threat.type.icon)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: threat.type.color))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(threat.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.atlasLabel)
                        Text(threat.type.rawValue.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: threat.type.color))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color(hex: threat.type.color).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text("Found in: \(threat.affectedFile)")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasTertiary)
                }
                Spacer()
                if threat.canStrip {
                    Image(systemName: "scissors")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .help("Can be removed without breaking the installation")
                }
            }
            Text(threat.detail)
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 30)
        }
        .padding(14)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 8) {
            switch result.verdict {

            // ── Clean ─────────────────────────────────────────────────────────
            case .clean:
                primaryButton(
                    label: L(.continueInstall),
                    icon: "arrow.right.circle.fill",
                    color: Color.atlasAccent,
                    action: onProceed
                )

            // ── License Tool (keygen/patch, no extra malware) ─────────────────
            case .licenseTool:
                infoNote(
                    icon: "info.circle",
                    text: "This is a license tool (keygen/patch). TITAN VSCAN™ detected no additional malware. Proceed at your own discretion.",
                    color: Color(hex: "#5E6AD2")
                )
                primaryButton(
                    label: L(.proceedWithInstall),
                    icon: "arrow.right.circle.fill",
                    color: Color(hex: "#5E6AD2"),
                    action: onProceed
                )
                secondaryButton(label: L(.cancel), action: onCancel)

            // ── Suspicious ────────────────────────────────────────────────────
            case .suspicious:
                infoNote(
                    icon: "exclamationmark.triangle",
                    text: "Unusual patterns detected. These may be false positives from legitimate software. Review the threats above before proceeding.",
                    color: Color(hex: "#F0A030")
                )
                primaryButton(
                    label: L(.proceedAnyway),
                    icon: "arrow.right.circle.fill",
                    color: Color(hex: "#F0A030"),
                    action: onProceed
                )
                quarantineButton
                secondaryButton(label: L(.cancel), action: onCancel)

            // ── Bundled Threat (real software + strippable malware) ───────────
            case .bundledThreat:
                if result.canStripAndInstall {
                    infoNote(
                        icon: "scissors",
                        text: "TITAN VSCAN™ can remove the malicious components and install only the clean software. The \(result.strippableThreats.map(\.name).joined(separator: ", ")) will be stripped.",
                        color: Color.atlasAccent
                    )
                    primaryButton(
                        label: L(.stripMalwareInstall),
                        icon: "scissors.circle.fill",
                        color: Color.atlasAccent,
                        action: onStripAndInstall
                    )
                } else {
                    infoNote(
                        icon: "exclamationmark.triangle",
                        text: "Threats are embedded in the core software and cannot be removed safely.",
                        color: Color(hex: "#F0A030")
                    )
                }
                quarantineButton
                deleteButton
                secondaryButton(label: L(.cancel), action: onCancel)

            // ── Malware ───────────────────────────────────────────────────────
            case .malware:
                infoNote(
                    icon: "xmark.shield.fill",
                    text: "TITAN VSCAN™ has blocked this installation. The file contains malware and cannot be safely installed. Move it to quarantine or delete it permanently.",
                    color: Color(hex: "#EF5B5B")
                )
                quarantineButton
                deleteButton
                secondaryButton(label: L(.cancel), action: onCancel)
            }
        }
    }

    // MARK: - Button helpers

    private func primaryButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(color.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var quarantineButton: some View {
        Button { showQuarantineConfirm = true } label: {
            Label(L(.moveToQuarantine), systemImage: "lock.shield")
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(hex: "#F0A030").opacity(0.08))
                .foregroundColor(Color(hex: "#F0A030"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(hex: "#F0A030").opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var deleteButton: some View {
        Button { showDeleteConfirm = true } label: {
            Label(L(.deletePermanently), systemImage: "trash")
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Color(hex: "#EF5B5B").opacity(0.08))
                .foregroundColor(Color(hex: "#EF5B5B"))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(hex: "#EF5B5B").opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundColor(Color.atlasTertiary)
        }
        .buttonStyle(.plain)
    }

    private func infoNote(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color.atlasSubtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(color.opacity(0.15), lineWidth: 0.75))
    }

    // MARK: - Verdict colors/icons

    private var verdictColor: Color {
        switch result.verdict {
        case .clean:         return Color.atlasAccent
        case .licenseTool:   return Color(hex: "#5E6AD2")
        case .suspicious:    return Color(hex: "#F0A030")
        case .bundledThreat: return Color(hex: "#F0A030")
        case .malware:       return Color(hex: "#EF5B5B")
        }
    }

    private var verdictIcon: String {
        switch result.verdict {
        case .clean:         return "checkmark.shield.fill"
        case .licenseTool:   return "key.fill"
        case .suspicious:    return "exclamationmark.triangle.fill"
        case .bundledThreat: return "exclamationmark.shield.fill"
        case .malware:       return "xmark.shield.fill"
        }
    }
}
