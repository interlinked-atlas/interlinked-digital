import SwiftUI

struct PrivacyConsentView: View {
    let onAccept: () -> Void

    static let consentKey = "ATLAS.privacyConsentGiven"

    @State private var consentChecked   = false
    @State private var showPrivacyModal = false
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 24
    @State private var continueHovered  = false
    @State private var quitHovered      = false

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#0E1326").opacity(0.97), location: 0),
                    .init(color: Color(hex: "#090C1B").opacity(0.98), location: 0.5),
                    .init(color: Color(hex: "#05070D").opacity(0.99), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 36)

                // Header
                VStack(spacing: 10) {
                    AtlasStarView(size: 64, isAnimating: true)
                    AtlasTitleText(size: 32, tracking: 10)
                    Text("by InterLinked®")
                        .font(.atlasFont(size: 11, weight: .light))
                        .tracking(3)
                        .foregroundColor(Color(hex: "#696E7C"))
                }
                .opacity(cardOpacity)

                Spacer().frame(height: 30)

                // Consent card
                VStack(alignment: .leading, spacing: 20) {

                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.atlasFont(size: 13))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                        Text("Privacy Agreement")
                            .font(.atlasFont(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0F2FF"))
                    }

                    Text(privacySummary)
                        .font(.atlasFont(size: 11.5))
                        .foregroundColor(Color(hex: "#8890B0"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // What's collected callout
                    VStack(alignment: .leading, spacing: 7) {
                        Text("DATA COLLECTED")
                            .font(.atlasFont(size: 9, weight: .bold))
                            .tracking(2)
                            .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
                        ForEach(dataPoints, id: \.self) { point in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: "#3ECFB2").opacity(0.5))
                                    .frame(width: 4, height: 4)
                                Text(point)
                                    .font(.atlasFont(size: 11))
                                    .foregroundColor(Color(hex: "#7080A0"))
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(hex: "#3ECFB2").opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#3ECFB2").opacity(0.12), lineWidth: 1)
                    )

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showPrivacyModal = true }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.atlasFont(size: 10))
                            Text("Read full Privacy Policy")
                                .font(.atlasFont(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(Color(hex: "#1E2132"))
                        .frame(height: 1)

                    // Consent checkbox
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(consentChecked
                                      ? Color(hex: "#3ECFB2").opacity(0.15)
                                      : Color(hex: "#08091A"))
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(consentChecked
                                        ? Color(hex: "#3ECFB2")
                                        : Color(hex: "#2E3350"), lineWidth: 1.5)
                            if consentChecked {
                                Image(systemName: "checkmark")
                                    .font(.atlasFont(size: 10, weight: .bold))
                                    .foregroundColor(Color(hex: "#3ECFB2"))
                            }
                        }
                        .frame(width: 20, height: 20)
                        .animation(.easeInOut(duration: 0.15), value: consentChecked)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) { consentChecked.toggle() }
                        }

                        HStack(spacing: 0) {
                            Text("I agree to the ")
                                .font(.atlasFont(size: 12))
                                .foregroundColor(Color(hex: "#9EA6B4"))
                            Text("Privacy Policy")
                                .font(.atlasFont(size: 12))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .underline()
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) { showPrivacyModal = true }
                                }
                            Text(" and consent to log syncing")
                                .font(.atlasFont(size: 12))
                                .foregroundColor(Color(hex: "#9EA6B4"))
                        }
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) { consentChecked.toggle() }
                        }
                    }

                    Rectangle()
                        .fill(Color(hex: "#1E2132"))
                        .frame(height: 1)

                    // Buttons
                    HStack(spacing: 10) {
                        Button("Quit") { NSApplication.shared.terminate(nil) }
                            .font(.atlasFont(size: 12, weight: .medium))
                            .foregroundColor(quitHovered ? Color(hex: "#F0F2FF") : Color(hex: "#696E7C"))
                            .padding(.horizontal, 20).padding(.vertical, 9)
                            .background(quitHovered ? Color(hex: "#141A30") : Color(hex: "#08091A"))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                            .buttonStyle(.plain)
                            .scaleEffect(quitHovered ? 1.02 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: quitHovered)
                            .onHover { quitHovered = $0 }

                        Spacer()

                        Button {
                            guard consentChecked else { return }
                            UserDefaults.standard.set(true, forKey: Self.consentKey)
                            // Record consent in Supabase (fire-and-forget)
                            Task.detached {
                                guard let s = KeychainManager.loadSession(), !s.isExpired else { return }
                                try? await SupabaseService.shared.givePrivacyConsent(accessToken: s.accessToken)
                            }
                            onAccept()
                        } label: {
                            HStack(spacing: 6) {
                                Text("Enable Log Sync")
                                    .font(.atlasFont(size: 13, weight: .semibold))
                                Image(systemName: "arrow.right")
                                    .font(.atlasFont(size: 11, weight: .semibold))
                            }
                            .foregroundColor(consentChecked ? Color(hex: "#08090E") : Color(hex: "#696E7C"))
                            .padding(.horizontal, 22).padding(.vertical, 10)
                            .background(
                                consentChecked
                                    ? LinearGradient(
                                        colors: continueHovered
                                            ? [Color(hex: "#5CDFC4"), Color(hex: "#3ECFB2")]
                                            : [Color(hex: "#3ECFB2"), Color(hex: "#32B89E")],
                                        startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(
                                        colors: [Color(hex: "#141A30"), Color(hex: "#141A30")],
                                        startPoint: .top, endPoint: .bottom)
                            )
                            .cornerRadius(9)
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(consentChecked ? Color.clear : Color(hex: "#2E3350"), lineWidth: 1))
                            .shadow(color: consentChecked
                                    ? Color(hex: "#3ECFB2").opacity(continueHovered ? 0.45 : 0.2)
                                    : Color.clear,
                                    radius: continueHovered ? 10 : 5, y: 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(!consentChecked)
                        .scaleEffect(consentChecked && continueHovered ? 1.03 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.75), value: continueHovered)
                        .animation(.easeInOut(duration: 0.2), value: consentChecked)
                        .onHover { continueHovered = $0 }
                    }
                }
                .padding(24)
                .background(Color(hex: "#0A0D1C"))
                .cornerRadius(16)
                .overlay(RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.5), radius: 32, y: 12)
                .opacity(cardOpacity)
                .offset(y: cardOffset)
                .padding(.horizontal, 36)

                Spacer().frame(height: 36)
            }

            if showPrivacyModal {
                PrivacyPolicyModal(isPresented: $showPrivacyModal)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 480, minHeight: 580)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.76).delay(0.1)) {
                cardOpacity = 1
                cardOffset  = 0
            }
        }
    }

    private let privacySummary = """
    ATLAS syncs your installation activity to your InterLinked account dashboard. This lets you review your install history, troubleshoot issues, and lets InterLinked support assist you when needed.

    Log syncing is required to use ATLAS with your account. Your data is never sold to third parties.
    """

    private let dataPoints = [
        "App names, file types, and install results",
        "Timestamps for each install, uninstall, or failure",
        "Device name and hardware UUID",
        "macOS version and system info",
        "Full installation log output",
    ]
}

// MARK: - Privacy Policy Modal

struct PrivacyPolicyModal: View {
    @Binding var isPresented: Bool
    @State private var overlayOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .opacity(overlayOpacity)

            VStack(spacing: 0) {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "lock.shield.fill")
                            .font(.atlasFont(size: 11))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                        Text("Privacy Policy — ATLAS by InterLinked®")
                            .font(.atlasFont(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0F2FF"))
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.atlasFont(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#696E7C"))
                            .frame(width: 24, height: 24)
                            .background(Color(hex: "#1E2132"))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)

                Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)

                ScrollView(.vertical, showsIndicators: true) {
                    Text(PrivacyPolicyContent.fullText)
                        .font(.atlasFont(size: 11.5))
                        .foregroundColor(Color(hex: "#9EA6B4"))
                        .lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .frame(maxHeight: 340)

                Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)

                Button("Close") { dismiss() }
                    .font(.atlasFont(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "#F0F2FF"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color(hex: "#0F1327"))
                    .buttonStyle(.plain)
            }
            .background(Color(hex: "#0A0D1C"))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "#1E2132"), lineWidth: 1))
            .shadow(color: .black.opacity(0.7), radius: 40, y: 16)
            .padding(.horizontal, 32).padding(.vertical, 40)
            .opacity(overlayOpacity)
            .scaleEffect(0.97 + 0.03 * overlayOpacity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) { overlayOpacity = 1 }
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.15)) { overlayOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { isPresented = false }
    }
}

// MARK: - Privacy Policy content

enum PrivacyPolicyContent {
    static let fullText = """
    ATLAS® — Privacy Policy
    © InterLinked®. All rights reserved.
    Last updated: 2025

    1. OVERVIEW
    InterLinked® ("we", "us") built ATLAS® to help you install software efficiently. This policy explains what data ATLAS collects, why, and how it is used.

    2. WHAT WE COLLECT
    When you use ATLAS with an InterLinked account, the following data is synced to your account dashboard:

    • Installation logs — app names, file types, timestamps, and result status (success/failure)
    • Uninstall logs — apps removed and removal results
    • Crash reports — ATLAS diagnostic files from macOS, if any
    • Device information — device name, hardware UUID, macOS version, architecture, and available RAM/disk
    • Account activity — log-in timestamps and subscription status

    3. HOW WE USE YOUR DATA
    Your data is used solely for:
    • Providing your installation history in your account dashboard
    • Supporting you when you need help with ATLAS
    • Improving ATLAS features and reliability

    4. DATA STORAGE
    All data is stored securely in your ATLAS account on InterLinked® servers (Supabase, hosted in the US). Data is encrypted in transit and at rest.

    5. DATA SHARING
    We do not sell, rent, or share your personal data with third parties. Data may only be disclosed if required by law.

    6. DATA RETENTION
    Your log data is retained as long as your account is active. You may request deletion of your data at any time by emailing interlinked.digital@gmail.com.

    7. YOUR RIGHTS
    You have the right to:
    • Access your data at interlinked.digital/atlas/account
    • Request deletion of all your data
    • Withdraw consent (contact us — note: this will disable log syncing)

    8. CONSENT
    By checking the consent box in ATLAS, you agree to this Privacy Policy and authorize ATLAS to sync installation logs to your account. This consent is stored in your account and locally on your device.

    9. CONTACT
    interlinked.digital@gmail.com
    interlinked.digital
    """
}
