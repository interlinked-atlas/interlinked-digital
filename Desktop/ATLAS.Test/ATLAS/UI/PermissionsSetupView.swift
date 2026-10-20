import SwiftUI

struct PermissionsSetupView: View {
    let onComplete: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared

    @State private var acc:      Bool = false
    @State private var fda:      Bool = false
    @State private var auto:     Bool = false
    @State private var checkingAuto = false
    @State private var pollTimer: Timer? = nil
    @State private var showRestartTip = false

    private var allGranted: Bool { acc && fda && auto }
    private var runningFromDMG: Bool { PermissionsManager.isRunningFromDMG }

    var body: some View {
        VStack(spacing: 0) {

            // ── Logo + title ──────────────────────────────────
            VStack(spacing: 6) {
                AtlasStarView(size: 50)
                    .padding(.top, 24)
                AtlasTitleText(size: 20, tracking: 6)

                Text("Permissions Setup")
                    .font(.atlasFont(size: 15, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                    .padding(.top, 2)

                Text("ATLAS needs three permissions to install software on your Mac.")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color.atlasSubtitle)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 14)
            }
            .padding(.horizontal, 28)

            Divider().background(Color.atlasSeparator)

            ScrollView {
                VStack(spacing: 12) {

                    // ── DMG warning ───────────────────────────
                    if runningFromDMG {
                        dmgWarning
                    }

                    // ── Permission cards ──────────────────────
                    permCard(
                        icon: "externaldrive.fill",
                        color: Color(hex: "#3ECFB2"),
                        title: "Full Disk Access",
                        detail: "Required to install software to system folders.",
                        granted: fda,
                        onGrant: {
                            PermissionsManager.openFullDiskAccessSettings()
                        }
                    )

                    permCard(
                        icon: "accessibility",
                        color: Color(hex: "#9B6DFF"),
                        title: "Accessibility",
                        detail: "Required to auto-fill password dialogs during installation.",
                        granted: acc,
                        onGrant: {
                            PermissionsManager.requestAccessibility()
                            PermissionsManager.openAccessibilitySettings()
                        }
                    )

                    permCard(
                        icon: "gearshape.2.fill",
                        color: Color(hex: "#F0A030"),
                        title: "Automation",
                        detail: "Required to control System Events for automated installs.",
                        granted: auto,
                        onGrant: {
                            PermissionsManager.requestAutomationPermission()
                        }
                    )

                    // ── How-to steps ──────────────────────────
                    howToCard

                    // ── Restart tip ───────────────────────────
                    if showRestartTip {
                        restartCard
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }

            Divider().background(Color.atlasSeparator)

            // ── Bottom bar ────────────────────────────────────
            bottomBar
        }
        .frame(minWidth: 460, minHeight: 560)
        .background(Color.atlasPanelBG.ignoresSafeArea())
        .preferredColorScheme(appearance.override)
        .onAppear { refresh(); startPolling() }
        .onDisappear { pollTimer?.invalidate() }
    }

    // MARK: - DMG Warning

    var dmgWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(Color(hex: "#F0A030"))
                .font(.atlasFont(size: 18))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text("Install ATLAS first")
                    .font(.atlasFont(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#F0A030"))

                Text("ATLAS is running from the disk image. Drag ATLAS into Applications, open it from there, then grant permissions — otherwise macOS won't remember them.")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color(hex: "#C8A060"))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
                } label: {
                    Label("Open Applications Folder", systemImage: "folder.fill")
                        .font(.atlasFont(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#F0A030"))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(hex: "#F0A030").opacity(0.07))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(hex: "#F0A030").opacity(0.3), lineWidth: 1))
    }

    // MARK: - Permission card

    @ViewBuilder
    func permCard(
        icon: String,
        color: Color,
        title: String,
        detail: String,
        granted: Bool,
        onGrant: @escaping () -> Void,
        onManualConfirm: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(granted ? Color(hex: "#2ECC8A").opacity(0.14) : color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: granted ? "checkmark" : icon)
                        .font(.atlasFont(size: 16, weight: granted ? .bold : .medium))
                        .foregroundColor(granted ? Color(hex: "#2ECC8A") : color)
                }

                // Text
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.atlasFont(size: 13, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                    Text(detail)
                        .font(.atlasFont(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }

                Spacer()

                // Button or granted badge
                if granted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.atlasFont(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#2ECC8A"))
                } else {
                    Button(action: onGrant) {
                        Text("Open Settings →")
                            .font(.atlasFont(size: 11, weight: .bold))
                            .foregroundColor(color)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(color.opacity(0.1))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(color.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            // If granted in System Settings but not yet detected, the 2-second
            // poll will pick it up automatically. If it takes longer, use Recheck or Restart.
            if !granted {
                Divider()
                    .background(Color.atlasSeparator)
                    .padding(.top, 10)
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.atlasFont(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                    Text("After granting in System Settings, status updates here within 2 seconds.")
                        .font(.atlasFont(size: 10))
                        .foregroundColor(Color.atlasTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(Color.atlasDeepBG)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(granted
                    ? Color(hex: "#2ECC8A").opacity(0.25)
                    : Color.atlasBorder,
                        lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: granted)
    }

    // MARK: - How-to card

    var howToCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How to grant each permission", systemImage: "info.circle")
                .font(.atlasFont(size: 12, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle)

            stepRow(n: 1, text: "Click \"Open Settings →\" on any permission above.")
            stepRow(n: 2, text: "System Settings will open to the right page.")
            stepRow(n: 3, text: "Click the \"+\" button, then find and select ATLAS.app.")
            stepRow(n: 4, text: "Make sure the toggle next to ATLAS is ON (blue).")
            stepRow(n: 5, text: "Return here — status updates automatically every 2 seconds.")
            stepRow(n: 6, text: "If status doesn't update after 10s, click Recheck or Restart.")
        }
        .padding(14)
        .background(Color.atlasDeepBG)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color.atlasBorder, lineWidth: 1))
    }

    func stepRow(n: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(.atlasFont(size: 10, weight: .bold))
                .foregroundColor(Color.atlasAccent)
                .frame(width: 18, height: 18)
                .background(Color.atlasAccent.opacity(0.12))
                .clipShape(Circle())
            Text(text)
                .font(.atlasFont(size: 11))
                .foregroundColor(Color.atlasSubtitle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Restart card

    var restartCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.atlasFont(size: 22))
                .foregroundColor(Color(hex: "#9B6DFF"))

            VStack(alignment: .leading, spacing: 3) {
                Text("Try restarting ATLAS")
                    .font(.atlasFont(size: 12, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                Text("If you granted permissions but they still show as not granted, a restart will fix it.")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color.atlasSubtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Restart") {
                PermissionsManager.restartATLAS()
            }
            .font(.atlasFont(size: 11, weight: .bold))
            .foregroundColor(Color(hex: "#9B6DFF"))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(hex: "#9B6DFF").opacity(0.1))
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: "#9B6DFF").opacity(0.3), lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.atlasDeepBG)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(Color(hex: "#9B6DFF").opacity(0.2), lineWidth: 1))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        HStack(spacing: 10) {
            // Quit
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .font(.atlasFont(size: 12))
                .foregroundColor(Color.atlasSubtitle)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.atlasDeepBG)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.atlasBorder, lineWidth: 1))
                .buttonStyle(.plain)

            // Recheck
            Button {
                refresh()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.atlasFont(size: 11, weight: .semibold))
                    Text("Recheck")
                        .font(.atlasFont(size: 12, weight: .medium))
                }
                .foregroundColor(Color.atlasSubtitle)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.atlasDeepBG)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.atlasBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            // Status pill
            if !allGranted {
                let count = [acc, fda, auto].filter { !$0 }.count
                Text("\(count) permission\(count == 1 ? "" : "s") remaining")
                    .font(.atlasFont(size: 10))
                    .foregroundColor(Color(hex: "#F0A030"))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(hex: "#F0A030").opacity(0.1))
                    .cornerRadius(6)
            }

            // Continue — only enabled when all three permissions are granted.
            // ATLAS cannot perform autonomous installs without all three.
            Button {
                PermissionsManager.hasCompletedOnboarding = true
                onComplete()
            } label: {
                HStack(spacing: 6) {
                    Text("Continue")
                        .font(.atlasFont(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.atlasFont(size: 11, weight: .semibold))
                }
                .foregroundColor(allGranted ? Color(hex: "#08090E") : Color.atlasTertiary)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(allGranted ? Color.atlasAccent : Color.atlasElevated)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(allGranted ? Color.clear : Color.atlasBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!allGranted)
            .animation(.easeInOut(duration: 0.25), value: allGranted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Polling & detection

    private func refresh() {
        // Sync checks
        acc = PermissionsManager.hasAccessibility
        fda = PermissionsManager.hasFullDiskAccess

        // Async automation check
        if !checkingAuto {
            checkingAuto = true
            PermissionsManager.checkAutomationPermission { granted in
                self.auto         = granted
                self.checkingAuto = false
            }
        }

        // Show restart tip if any permission was granted but not reading yet
        // (show after the first recheck attempt)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !allGranted { showRestartTip = true }
        }
    }

    private func startPolling() {
        // Initial check
        refresh()

        // Poll every 2 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            acc = PermissionsManager.hasAccessibility
            fda = PermissionsManager.hasFullDiskAccess
            if !checkingAuto && !auto {
                checkingAuto = true
                PermissionsManager.checkAutomationPermission { granted in
                    auto          = granted
                    checkingAuto  = false
                }
            }
            if allGranted { pollTimer?.invalidate() }
        }
    }
}
