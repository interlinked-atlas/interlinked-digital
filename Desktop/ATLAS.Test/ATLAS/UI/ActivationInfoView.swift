import SwiftUI
import AppKit

// MARK: - Alert model (used by ContentView's pending queue)

struct ActivationAlert: Identifiable {
    let id = UUID()
    let productName: String
    let docInfo: InstallerDocInfo
}

// MARK: - View

/// Displays activation information extracted from installer documentation.
///
/// Used in two contexts:
/// - Post-install proactive alert (isPostInstallAlert = true): shows "Copy All" + "Got It" buttons
/// - History / queue row browse (isPostInstallAlert = false): inline dismiss via environment
struct ActivationInfoView: View {
    let productName: String
    let docInfo: InstallerDocInfo
    var isPostInstallAlert: Bool = false
    var onDismiss: (() -> Void)? = nil

    @Environment(\.dismiss) private var envDismiss
    @State private var copiedAll = false

    private func dismiss() {
        if let onDismiss { onDismiss() } else { envDismiss() }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color(hex: "#2A2D35"))
            sourceBar
            content
            Divider().background(Color(hex: "#2A2D35"))
            footer
        }
        .frame(width: 500, height: 560)
        .background(Color(hex: "#12141A"))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: "#F0C56A").opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "#F0C56A"))
            }

            VStack(alignment: .leading, spacing: 3) {
                if isPostInstallAlert {
                    Text("Installation Complete")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#2ECC8A"))
                    Text("ATLAS found activation information included with this installer.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8890B0"))
                } else {
                    Text("Activation Information")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(productName)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#696E7C"))
                }
            }

            Spacer()

            if !isPostInstallAlert {
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: "#696E7C"))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(hex: "#1A1D23"))
    }

    // MARK: - Source bar

    @ViewBuilder
    private var sourceBar: some View {
        if !docInfo.sourceFiles.isEmpty {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#444870"))
                Text("Parsed from: \(docInfo.sourceFiles.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#444870"))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 7)
            .background(Color(hex: "#0F1118"))
        }
    }

    // MARK: - Scrollable content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Product name callout (post-install only)
                if isPostInstallAlert {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#2ECC8A"))
                            .font(.system(size: 13))
                        Text("\(productName) installed successfully.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#C8CDD8"))
                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: "#2ECC8A").opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(hex: "#2ECC8A").opacity(0.18), lineWidth: 1))
                    )

                    // Activation still required hint
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(hex: "#F0C56A"))
                            .font(.system(size: 11))
                        Text("To begin using \(productName), activation is still required.")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#F0C56A"))
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: "#F0C56A").opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .stroke(Color(hex: "#F0C56A").opacity(0.15), lineWidth: 1))
                    )
                }

                // License Keys
                if !docInfo.licenseKeys.isEmpty {
                    SectionBlock(title: "License Keys", icon: "key.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(docInfo.licenseKeys, id: \.value) { key in
                                KeyRow(key: key)
                            }
                        }
                    }
                }

                // Instructions / Steps
                if !docInfo.steps.isEmpty {
                    SectionBlock(title: "Instructions", icon: "list.number") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(docInfo.steps.enumerated()), id: \.offset) { i, step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Color(hex: "#3ECFB2"))
                                        .frame(width: 18, alignment: .trailing)
                                        .padding(.top, 1)
                                    Text(step)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "#C8CDD8"))
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                            }
                        }
                    }
                }

                // Activation URLs
                if !docInfo.activationURLs.isEmpty {
                    SectionBlock(title: "Links", icon: "link") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(docInfo.activationURLs, id: \.self) { urlString in
                                URLRow(urlString: urlString)
                            }
                        }
                    }
                }

                // Notes
                if !docInfo.notes.isEmpty {
                    SectionBlock(title: "Notes", icon: "info.circle") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(docInfo.notes, id: \.self) { note in
                                Text(note)
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#696E7C"))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(hex: "#12141A"))
    }

    // MARK: - Footer buttons

    @ViewBuilder
    private var footer: some View {
        if isPostInstallAlert {
            HStack(spacing: 10) {
                // Copy All Keys button — only when keys exist
                if !docInfo.licenseKeys.isEmpty {
                    Button(action: copyAllKeys) {
                        HStack(spacing: 5) {
                            Image(systemName: copiedAll ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                            Text(copiedAll ? "Copied!" : "Copy All Keys")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(copiedAll ? Color(hex: "#2ECC8A") : Color(hex: "#F0C56A"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(copiedAll
                                      ? Color(hex: "#2ECC8A").opacity(0.12)
                                      : Color(hex: "#F0C56A").opacity(0.10))
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .stroke(copiedAll
                                            ? Color(hex: "#2ECC8A").opacity(0.3)
                                            : Color(hex: "#F0C56A").opacity(0.25), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Got It — primary dismiss
                Button(action: dismiss) {
                    Text("Got It")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: docInfo.licenseKeys.isEmpty ? .infinity : nil)
                        .padding(.horizontal, docInfo.licenseKeys.isEmpty ? 0 : 28)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: "#3ECFB2").opacity(0.18))
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .stroke(Color(hex: "#3ECFB2").opacity(0.35), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(hex: "#1A1D23"))
        }
    }

    private func copyAllKeys() {
        let allKeys = docInfo.licenseKeys.map(\.value).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(allKeys, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copiedAll = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { copiedAll = false }
        }
    }
}

// MARK: - Shared sub-views

private struct SectionBlock<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#696E7C"))
                    .tracking(0.8)
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "#1A1D23"))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#2A2D35"), lineWidth: 1))
        )
    }
}

private struct KeyRow: View {
    let key: InstallerDocInfo.LicenseKey
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#696E7C"))
                    .tracking(0.6)
                Text(key.value)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#F0C56A"))
                    .textSelection(.enabled)
            }
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key.value, forType: .string)
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { copied = false }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                    Text(copied ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(copied ? Color(hex: "#2ECC8A") : Color(hex: "#696E7C"))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: "#22252E")))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: "#12141A")))
    }
}

private struct URLRow: View {
    let urlString: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#3B82F6"))
            Text(urlString)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#3B82F6"))
                .underline()
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
        }
    }
}
