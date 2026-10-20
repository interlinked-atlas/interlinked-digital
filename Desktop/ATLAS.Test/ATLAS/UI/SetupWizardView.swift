import SwiftUI

// MARK: - SetupWizardView
// First-run setup wizard. Shown once after auth + subscription, before mainLayout.
// Completion writes atlas.setupComplete = true via the onComplete callback in ContentView.
// Existing users are bypassed in ContentView.onAppear before this view is ever shown.

struct SetupWizardView: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var appearance = AppearanceManager.shared

    @State private var step: Int = 0
    @State private var direction: Int = 1   // +1 forward, -1 backward for slide direction

    // Step 2 — permissions live state
    @State private var permFDA:  Bool = false
    @State private var permAcc:  Bool = false
    @State private var permAuto: Bool = false
    @State private var checkingAuto = false
    @State private var permPollTimer: Timer? = nil

    // Step 3 — password entry state
    @State private var wizPassword: String = ""
    @State private var passwordSaved: Bool = false
    @State private var passwordError: String = ""
    @State private var isVerifyingPassword: Bool = false

    // Step 4 — appearance selection; nil = not yet chosen
    @State private var appearanceChoice: ColorScheme? = AppearanceManager.shared.override

    private var isDark: Bool { colorScheme == .dark }
    private var allPermsGranted: Bool { permFDA && permAcc && permAuto }

    // MARK: - Body

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(stepTransition)

                Divider()
                    .background(Color(hex: "#1E2132"))

                navigationBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: 500, height: 600)
        .onAppear {
            refreshPerms()
            startPermPoll()
            // If a password was already saved (e.g. edge-case partial install),
            // pre-satisfy Step 3 so the user is not asked to re-enter it.
            if KeychainManager.hasPassword() {
                passwordSaved = true
            }
        }
        .onDisappear { permPollTimer?.invalidate() }
        .preferredColorScheme(appearance.override)
    }

    // MARK: - Background

    private var background: Color {
        isDark ? Color(hex: "#090C1A") : Color(hex: "#F5F5F7")
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { i in
                Capsule()
                    .fill(i == step
                          ? Color(hex: "#3ECFB2")
                          : Color(hex: isDark ? "#1E2438" : "#D1D1D6"))
                    .frame(width: i == step ? 24 : 8, height: 8)
                    .animation(.atlasSpring, value: step)
            }
        }
    }

    // MARK: - Step content switcher

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: permissionsStep
        case 2: keychainStep
        case 3: appearanceStep
        case 4: readyStep
        default: welcomeStep
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion:  .opacity.combined(with: .offset(x: CGFloat(direction) * 40, y: 0)),
            removal:    .opacity.combined(with: .offset(x: CGFloat(-direction) * 40, y: 0))
        )
    }

    // MARK: - Navigation bar

    private var navigationBar: some View {
        HStack {
            if step > 0 {
                backButton
            }
            Spacer()
            continueButton
        }
    }

    private var backButton: some View {
        Button {
            navigate(to: step - 1, direction: -1)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left")
                    .font(.atlasFont(size: 11, weight: .semibold))
                Text("Back")
                    .font(.atlasFont(size: 13, weight: .medium))
            }
            .foregroundColor(Color(hex: isDark ? "#8890B0" : "#6E6E80"))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(isDark ? Color(hex: "#111320") : Color(hex: "#E5E5EA"))
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(hex: isDark ? "#1E2438" : "#D1D1D6"), lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    private var continueButton: some View {
        let isLast = step == 4
        let enabled = continueEnabled

        return Button {
            if isLast {
                // Mark onboarding complete on both flags for full compatibility.
                PermissionsManager.hasCompletedOnboarding = true
                onComplete()
            } else {
                navigate(to: step + 1, direction: 1)
            }
        } label: {
            HStack(spacing: 6) {
                Text(isLast ? "Get Started" : "Continue")
                    .font(.atlasFont(size: 13, weight: .semibold))
                if !isLast {
                    Image(systemName: "arrow.right")
                        .font(.atlasFont(size: 11, weight: .semibold))
                }
            }
            .foregroundColor(enabled ? Color(hex: "#090C1A") : Color(hex: isDark ? "#4A5070" : "#AEAEB2"))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(enabled
                        ? LinearGradient(colors: [Color(hex: "#3ECFB2"), Color(hex: "#2ABEAA")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [isDark ? Color(hex: "#16181C") : Color(hex: "#E5E5EA"),
                                                  isDark ? Color(hex: "#16181C") : Color(hex: "#E5E5EA")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            .cornerRadius(9)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .animation(.easeInOut(duration: 0.2), value: enabled)
    }

    private var continueEnabled: Bool {
        switch step {
        case 1: return allPermsGranted
        case 2: return passwordSaved
        case 3: return appearanceChoice != nil || AppearanceManager.shared.override == nil
        default: return true
        }
    }

    // MARK: - Navigation helper

    private func navigate(to newStep: Int, direction dir: Int) {
        direction = dir
        withAnimation(.atlasSpring) { step = newStep }
    }

    // MARK: ── STEP 1: Welcome ─────────────────────────────────────────────

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                InstallingStarView()
                    .frame(width: 200, height: 200)

                VStack(spacing: 10) {
                    Text("Welcome to ATLAS")
                        .font(.atlasFont(size: 26, weight: .bold))
                        .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))

                    Text("Your intelligent software installation assistant.")
                        .font(.atlasFont(size: 14, weight: .medium))
                        .foregroundColor(isDark ? Color(hex: "#9EA6B4") : Color(hex: "#6E6E80"))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.atlasFont(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                        Text("Powered by TITAN Installation Technology")
                            .font(.atlasFont(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .tracking(0.3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color(hex: "#3ECFB2").opacity(0.10))
                    .cornerRadius(20)

                    Text("ATLAS uses TITAN technology to intelligently install, organize, and manage software on your Mac.")
                        .font(.atlasFont(size: 12))
                        .foregroundColor(isDark ? Color(hex: "#696E7C") : Color(hex: "#8E8E93"))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: ── STEP 2: Permissions ─────────────────────────────────────────

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                icon: "lock.shield.fill",
                iconColor: Color(hex: "#3ECFB2"),
                title: "Permissions Setup",
                subtitle: "ATLAS requires three permissions to install software on your Mac."
            )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    wizPermCard(
                        icon: "externaldrive.fill",
                        color: Color(hex: "#3ECFB2"),
                        title: "Full Disk Access",
                        detail: "Required to install software to system folders.",
                        granted: permFDA,
                        onGrant: { PermissionsManager.openFullDiskAccessSettings() }
                    )
                    wizPermCard(
                        icon: "accessibility",
                        color: Color(hex: "#9B6DFF"),
                        title: "Accessibility",
                        detail: "Required to auto-fill password dialogs during installation.",
                        granted: permAcc,
                        onGrant: {
                            PermissionsManager.requestAccessibility()
                            PermissionsManager.openAccessibilitySettings()
                        }
                    )
                    wizPermCard(
                        icon: "gearshape.2.fill",
                        color: Color(hex: "#F0A030"),
                        title: "Automation",
                        detail: "Required to control System Events for automated installs.",
                        granted: permAuto,
                        onGrant: { PermissionsManager.requestAutomationPermission() }
                    )

                    if !allPermsGranted {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.atlasFont(size: 11))
                                .foregroundColor(Color(hex: "#696E7C"))
                            Text("Complete the required permissions above to continue.")
                                .font(.atlasFont(size: 11))
                                .foregroundColor(Color(hex: "#696E7C"))
                            Spacer()
                            Button {
                                refreshPerms()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.atlasFont(size: 10, weight: .semibold))
                                    Text("Recheck")
                                        .font(.atlasFont(size: 11, weight: .medium))
                                }
                                .foregroundColor(Color(hex: "#3ECFB2"))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(isDark ? Color(hex: "#0A0D1C") : Color(hex: "#EFEFEF"))
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(hex: isDark ? "#1E2132" : "#D1D1D6"), lineWidth: 0.75))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    @ViewBuilder
    private func wizPermCard(
        icon: String,
        color: Color,
        title: String,
        detail: String,
        granted: Bool,
        onGrant: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(granted ? Color(hex: "#2ECC8A").opacity(0.12) : color.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: granted ? "checkmark" : icon)
                    .font(.atlasFont(size: 16, weight: granted ? .bold : .medium))
                    .foregroundColor(granted ? Color(hex: "#2ECC8A") : color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.atlasFont(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))
                Text(detail)
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color(hex: isDark ? "#696E7C" : "#8E8E93"))
            }

            Spacer()

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
                        .background(color.opacity(0.10))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(color.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(isDark ? Color(hex: "#0A0D1C") : Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(granted
                          ? Color(hex: "#2ECC8A").opacity(0.25)
                          : Color(hex: isDark ? "#1E2132" : "#E5E5EA"),
                          lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: granted)
    }

    // MARK: ── STEP 3: Keychain ────────────────────────────────────────────

    private var keychainStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                stepHeader(
                    icon: "key.fill",
                    iconColor: Color(hex: "#F0A030"),
                    title: "Keychain Setup",
                    subtitle: "ATLAS securely stores your Mac password for autonomous installs."
                )

                VStack(spacing: 10) {
                    infoCard(
                        icon: "lock.shield.fill",
                        iconColor: Color(hex: "#3ECFB2"),
                        title: "Secure Credential Storage",
                        body: "ATLAS stores your Mac login password in macOS Keychain — Apple's built-in encrypted credential manager. Your password never leaves your device."
                    )
                    infoCard(
                        icon: "hand.raised.fill",
                        iconColor: Color(hex: "#9B6DFF"),
                        title: "Choose \"Always Allow\"",
                        body: "When macOS shows a Keychain access prompt, select \"Always Allow\". This lets ATLAS install software autonomously without interrupting you."
                    )
                    infoCard(
                        icon: "checkmark.shield.fill",
                        iconColor: Color(hex: "#2ECC8A"),
                        title: "Local & Private",
                        body: "Credentials are encrypted at rest and accessible only to ATLAS on this Mac. Nothing is sent to external servers."
                    )
                }
                .padding(.horizontal, 24)

                // Password entry — only shown if not already saved
                if !passwordSaved {
                    VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enter your Mac login password")
                                .font(.atlasFont(size: 12, weight: .semibold))
                                .foregroundColor(isDark ? Color(hex: "#9EA6B4") : Color(hex: "#6E6E80"))

                            SecureField("Mac login password", text: $wizPassword)
                                .textFieldStyle(.plain)
                                .font(.atlasFont(size: 13))
                                .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))
                                .tint(Color(hex: "#3ECFB2"))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(isDark ? Color(hex: "#0A0D1C") : Color(hex: "#FFFFFF"))
                                .cornerRadius(9)
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color(hex: isDark ? "#1E2438" : "#D1D1D6"), lineWidth: 0.75))
                                .onSubmit { verifyAndSavePassword() }

                            if !passwordError.isEmpty {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.atlasFont(size: 11))
                                        .foregroundColor(Color(hex: "#E05555"))
                                    Text(passwordError)
                                        .font(.atlasFont(size: 11))
                                        .foregroundColor(Color(hex: "#E05555"))
                                }
                            }
                        }

                        Button {
                            verifyAndSavePassword()
                        } label: {
                            HStack(spacing: 6) {
                                if isVerifyingPassword {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.7)
                                        .tint(Color(hex: "#090C1A"))
                                    Text("Verifying…")
                                        .font(.atlasFont(size: 13, weight: .semibold))
                                } else {
                                    Image(systemName: "lock.fill")
                                        .font(.atlasFont(size: 11, weight: .semibold))
                                    Text("Verify & Save")
                                        .font(.atlasFont(size: 13, weight: .semibold))
                                }
                            }
                            .foregroundColor(wizPassword.isEmpty || isVerifyingPassword
                                             ? Color(hex: isDark ? "#4A5070" : "#AEAEB2")
                                             : Color(hex: "#090C1A"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(wizPassword.isEmpty || isVerifyingPassword
                                        ? (isDark ? Color(hex: "#16181C") : Color(hex: "#E5E5EA"))
                                        : Color(hex: "#3ECFB2"))
                            .cornerRadius(9)
                        }
                        .buttonStyle(.plain)
                        .disabled(wizPassword.isEmpty || isVerifyingPassword)
                        .animation(.easeInOut(duration: 0.15), value: isVerifyingPassword)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                } else {
                    // Password already saved — show confirmation
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.atlasFont(size: 16))
                            .foregroundColor(Color(hex: "#2ECC8A"))
                        Text("Password saved to Keychain")
                            .font(.atlasFont(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#2ECC8A"))
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(hex: "#2ECC8A").opacity(0.08))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(hex: "#2ECC8A").opacity(0.25), lineWidth: 1))
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                }

                Spacer(minLength: 16)
            }
        }
    }

    // Verifies the password via sudo and saves to Keychain exactly once per tap.
    // isVerifyingPassword prevents double-submission.
    private func verifyAndSavePassword() {
        guard !wizPassword.isEmpty, !isVerifyingPassword else { return }
        isVerifyingPassword = true
        passwordError = ""

        DispatchQueue.global().async {
            let verified = sudoVerify(wizPassword)
            DispatchQueue.main.async {
                isVerifyingPassword = false
                if verified {
                    let saved = KeychainManager.savePassword(wizPassword)
                    if saved {
                        passwordSaved = true
                        wizPassword = ""   // clear field — no longer needed in memory
                    } else {
                        passwordError = "Could not save to Keychain. Please try again."
                    }
                } else {
                    passwordError = "Incorrect password. Please try again."
                }
            }
        }
    }

    private func sudoVerify(_ pwd: String) -> Bool {
        let process = Process()
        let inputPipe  = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-S", "true"]
        process.standardInput  = inputPipe
        process.standardOutput = outputPipe
        process.standardError  = outputPipe
        do {
            try process.run()
            inputPipe.fileHandleForWriting.write(Data((pwd + "\n").utf8))
            inputPipe.fileHandleForWriting.closeFile()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: ── STEP 4: Appearance ──────────────────────────────────────────

    private var appearanceStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                icon: "circle.lefthalf.filled",
                iconColor: Color(hex: "#F0A030"),
                title: "Appearance",
                subtitle: "Choose how ATLAS looks. You can change this anytime in Settings."
            )

            VStack(spacing: 10) {
                appearanceCard(
                    title: "Dark Mode",
                    subtitle: "Easy on the eyes in any environment.",
                    icon: "moon.fill",
                    scheme: ColorScheme.dark
                )
                appearanceCard(
                    title: "Light Mode",
                    subtitle: "Clean and bright for daytime use.",
                    icon: "sun.max.fill",
                    scheme: ColorScheme.light
                )
                appearanceCard(
                    title: "System Default",
                    subtitle: "Follows your macOS appearance setting.",
                    icon: "circle.lefthalf.filled",
                    scheme: nil
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Text("ATLAS remembers your choice for every future launch — splash, homepage, settings, and all pages.")
                .font(.atlasFont(size: 11))
                .foregroundColor(Color(hex: isDark ? "#696E7C" : "#8E8E93"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 16)

            Spacer()
        }
    }

    private func appearanceCard(title: String, subtitle: String, icon: String, scheme: ColorScheme?) -> some View {
        let isSelected: Bool = {
            if scheme == nil {
                return appearanceChoice == nil
            }
            return appearanceChoice == scheme
        }()

        return Button {
            appearanceChoice = scheme
            AppearanceManager.shared.override = scheme
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected
                              ? Color(hex: "#3ECFB2").opacity(0.12)
                              : (isDark ? Color(hex: "#0A0D1C") : Color(hex: "#F0F0F0")))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.atlasFont(size: 16, weight: .medium))
                        .foregroundColor(isSelected ? Color(hex: "#3ECFB2") : Color(hex: isDark ? "#696E7C" : "#8E8E93"))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.atlasFont(size: 13, weight: .semibold))
                        .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))
                    Text(subtitle)
                        .font(.atlasFont(size: 11))
                        .foregroundColor(Color(hex: isDark ? "#696E7C" : "#8E8E93"))
                }

                Spacer()

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color(hex: "#3ECFB2") : Color(hex: isDark ? "#2A2D45" : "#D1D1D6"), lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "#3ECFB2"))
                            .frame(width: 10, height: 10)
                    }
                }
                .animation(.atlasSnap, value: isSelected)
            }
            .padding(14)
            .background(isDark ? Color(hex: "#0A0D1C") : Color(hex: "#FFFFFF"))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected
                              ? Color(hex: "#3ECFB2").opacity(0.5)
                              : Color(hex: isDark ? "#1E2132" : "#E5E5EA"),
                              lineWidth: isSelected ? 1.5 : 1))
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }

    // MARK: ── STEP 5: Ready ───────────────────────────────────────────────

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#3ECFB2").opacity(0.10))
                        .frame(width: 80, height: 80)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.atlasFont(size: 44))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }

                VStack(spacing: 8) {
                    Text("ATLAS is Ready")
                        .font(.atlasFont(size: 24, weight: .bold))
                        .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))

                    Text("Welcome, \(NSUserName()).")
                        .font(.atlasFont(size: 14, weight: .medium))
                        .foregroundColor(isDark ? Color(hex: "#9EA6B4") : Color(hex: "#6E6E80"))
                }

                VStack(spacing: 8) {
                    summaryRow(icon: "person.circle.fill",     color: Color(hex: "#3ECFB2"), text: "Account connected")
                    summaryRow(icon: "lock.shield.fill",       color: Color(hex: "#9B6DFF"), text: "Permissions configured")
                    summaryRow(icon: "key.fill",               color: Color(hex: "#F0A030"), text: "Keychain configured")
                    summaryRow(icon: "circle.lefthalf.filled", color: Color(hex: "#3ECFB2"), text: "Appearance selected")
                }
                .padding(18)
                .background(isDark ? Color(hex: "#0A0D1C") : Color(hex: "#FFFFFF"))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(hex: isDark ? "#1E2132" : "#E5E5EA"), lineWidth: 1))
                .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    private func summaryRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.atlasFont(size: 14))
                .foregroundColor(color)
                .frame(width: 22)
            Text(text)
                .font(.atlasFont(size: 13))
                .foregroundColor(isDark ? Color(hex: "#D0D8F0") : Color(hex: "#3C3C43"))
            Spacer()
            Image(systemName: "checkmark")
                .font(.atlasFont(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#2ECC8A"))
        }
    }

    // MARK: - Shared sub-components

    private func stepHeader(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.atlasFont(size: 24, weight: .medium))
                    .foregroundColor(iconColor)
            }

            Text(title)
                .font(.atlasFont(size: 20, weight: .bold))
                .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))

            Text(subtitle)
                .font(.atlasFont(size: 12))
                .foregroundColor(Color(hex: isDark ? "#696E7C" : "#8E8E93"))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.top, 8)
        .padding(.bottom, 16)
        .padding(.horizontal, 24)
    }

    private func infoCard(icon: String, iconColor: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.atlasFont(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.atlasFont(size: 13, weight: .semibold))
                    .foregroundColor(isDark ? Color(hex: "#F0F2FF") : Color(hex: "#1C1C1E"))
                Text(body)
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color(hex: isDark ? "#696E7C" : "#8E8E93"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(isDark ? Color(hex: "#0A0D1C") : Color(hex: "#FFFFFF"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color(hex: isDark ? "#1E2132" : "#E5E5EA"), lineWidth: 1))
    }

    // MARK: - Permissions polling

    private func refreshPerms() {
        permFDA = PermissionsManager.hasFullDiskAccess
        permAcc = PermissionsManager.hasAccessibility
        if !checkingAuto {
            checkingAuto = true
            PermissionsManager.checkAutomationPermission { granted in
                permAuto     = granted
                checkingAuto = false
            }
        }
    }

    private func startPermPoll() {
        refreshPerms()
        permPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            permFDA = PermissionsManager.hasFullDiskAccess
            permAcc = PermissionsManager.hasAccessibility
            if !checkingAuto && !permAuto {
                checkingAuto = true
                PermissionsManager.checkAutomationPermission { granted in
                    permAuto     = granted
                    checkingAuto = false
                }
            }
            if allPermsGranted { permPollTimer?.invalidate() }
        }
    }
}
