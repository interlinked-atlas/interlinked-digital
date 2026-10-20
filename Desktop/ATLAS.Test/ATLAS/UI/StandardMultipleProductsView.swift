import SwiftUI
import AppKit

struct StandardMultipleProductsView: View {
    let installableSteps: [TitanMissionStep]
    let onInstallOne: (TitanMissionStep) -> Void
    let onCancel: () -> Void

    @State private var selectedID: UUID?

    private var selectedStep: TitanMissionStep? {
        installableSteps.first { $0.id == selectedID }
    }

    var body: some View {
        ZStack {
            Color(hex: "#07080F").ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ──────────────────────────────────────────────────
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#F0A030").opacity(0.10))
                            .frame(width: 56, height: 56)
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "#F0A030"))
                    }

                    Text("Multiple Installations Detected")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(hex: "#F0F2FF"))

                    Text("This package contains \(installableSteps.count) items. An ATLAS subscription is required to install multiple items at once. Select which one to install below.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8A8A96"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(.top, 28)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                Divider().background(Color(hex: "#1E2030"))

                // ── Item list ────────────────────────────────────────────────
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(installableSteps) { step in
                            itemRow(step)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(maxHeight: 220)

                Divider().background(Color(hex: "#1E2030"))

                // ── Actions ──────────────────────────────────────────────────
                VStack(spacing: 10) {

                    // Primary install button
                    Button {
                        if let step = selectedStep { onInstallOne(step) }
                    } label: {
                        let label = selectedStep.map { displayName(for: $0) } ?? "Select an Item Above"
                        Text(selectedStep != nil ? "Install \(label)" : label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedStep != nil ? Color(hex: "#07080F") : Color(hex: "#44444E"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(
                                selectedStep != nil
                                    ? AnyView(LinearGradient(
                                        colors: [Color(hex: "#3ECFB2"), Color(hex: "#2ABEAA")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyView(Color(hex: "#111116"))
                            )
                            .cornerRadius(9)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(selectedStep != nil
                                                  ? Color.clear
                                                  : Color(hex: "#222228"), lineWidth: 0.75)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedStep == nil)
                    .animation(.atlasSnap, value: selectedStep?.id)

                    // Upgrade link
                    HStack(spacing: 3) {
                        Text("Need all of them? Subscribe to ATLAS")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7090"))
                        Button {
                            NSWorkspace.shared.open(
                                URL(string: "https://interlinked.digital/atlas")!)
                        } label: {
                            Text("Here")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .underline()
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Cancel") { onCancel() }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#44444E"))
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 420)
        .onAppear { selectedID = installableSteps.first?.id }
    }

    // MARK: - Row

    @ViewBuilder
    private func itemRow(_ step: TitanMissionStep) -> some View {
        let isSelected = selectedID == step.id
        Button { selectedID = step.id } label: {
            HStack(spacing: 12) {
                // Radio dot
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color(hex: "#3ECFB2") : Color(hex: "#333338"),
                            lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "#3ECFB2"))
                            .frame(width: 9, height: 9)
                    }
                }
                .animation(.atlasSnap, value: isSelected)

                // File icon
                Image(systemName: step.icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Color(hex: "#3ECFB2") : Color(hex: "#555566"))
                    .frame(width: 18)

                // Name + detail
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(for: step))
                        .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? Color(hex: "#F0F2FF") : Color(hex: "#9090A0"))
                    if !step.detail.isEmpty && step.detail != step.title {
                        Text(step.detail)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#44444E"))
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected
                        ? Color(hex: "#3ECFB2").opacity(0.06)
                        : Color(hex: "#0F1020"))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color(hex: "#3ECFB2").opacity(0.35) : Color(hex: "#1E2030"),
                        lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .animation(.atlasSnap, value: isSelected)
    }

    // Strip the "Install package: " prefix — show just the filename
    private func displayName(for step: TitanMissionStep) -> String {
        let parts = step.title.components(separatedBy: ": ")
        return parts.count > 1 ? parts.dropFirst().joined(separator: ": ") : step.title
    }
}
