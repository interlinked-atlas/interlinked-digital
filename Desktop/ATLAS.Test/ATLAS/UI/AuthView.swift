import SwiftUI

struct AuthView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var fieldFocused: Field? = nil
    @State private var showForgotPassword = false
    @State private var forgotEmail = ""
    @State private var forgotSent = false
    @State private var tosAgreed = false
    @State private var showTosModal = false
    @State private var showPassword = false

    enum Mode { case signIn, signUp }
    enum Field { case email, password, forgotEmail }

    // Live theme — follows the same AppearanceManager the rest of ATLAS uses.
    // No separate theme system for auth; this only reads the existing one.
    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.colorScheme) private var systemScheme
    private var effectiveScheme: ColorScheme { appearance.effective(systemScheme) }
    private var p: AuthPalette { AuthPalette.forScheme(effectiveScheme) }

    var body: some View {
        ZStack {
            p.pageBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo + title
                VStack(spacing: 10) {
                    AtlasStarView(size: 52, isAnimating: true)
                    AtlasTitleText(size: 28, tracking: 7)
                    Text("The Future of Installation.")
                        .font(.atlasFont(size: 11, weight: .regular))
                        .foregroundColor(p.textSecondary)
                        .tracking(0.3)
                    Text("Developed by InterLinked®")
                        .font(.atlasFont(size: 10, weight: .light))
                        .foregroundColor(p.textMain.opacity(0.85))
                        .tracking(0.3)
                }
                .padding(.bottom, 32)

                if showForgotPassword {
                    forgotPasswordCard
                } else if mode == .signIn {
                    signInCard
                } else {
                    signUpCard
                }

                Spacer()

                // Footer
                Text("InterLinked© · All rights reserved")
                    .font(.atlasFont(size: 10))
                    .foregroundColor(p.footerText)
                    .padding(.bottom, 20)
            }

            // ToS modal overlay
            if showTosModal {
                TermsOfServiceModal(isPresented: $showTosModal)
                    .transition(.opacity)
            }
        }
        .frame(width: 480, height: 560)
        // Explicitly pins the native color scheme to whatever ATLAS's own
        // theme resolves to for this screen, so system-drawn chrome (most
        // notably the text-insertion caret in the fields below) renders
        // correctly against our custom palette instead of following a
        // possibly-mismatched system appearance.
        .colorScheme(effectiveScheme)
        .onChange(of: mode) { _ in tosAgreed = false }
    }

    // MARK: - Sign In card

    private var signInCard: some View {
        VStack(spacing: 0) {
            // Mode toggle
            HStack(spacing: 0) {
                modeTab("Sign In",  target: .signIn)
                modeTab("Sign Up",  target: .signUp)
            }
            .background(p.cardHeaderBackground)
            .cornerRadius(10, corners: [.topLeft, .topRight])

            Divider().background(p.borderIdle)

            VStack(spacing: 14) {
                // Error banner
                if auth.authErrorIsDeviceLimit {
                    deviceLimitBanner
                } else if auth.authErrorIsEmailUnconfirmed {
                    emailUnconfirmedBanner(email: email)
                } else if let err = auth.authError {
                    errorBanner(err)
                }

                authField(icon: "envelope", placeholder: "Email address",
                          text: $email, focused: $fieldFocused, field: .email, secure: false,
                          onSubmit: { guard !auth.isLoading && !email.isEmpty && !password.isEmpty else { return }; auth.authError = nil; Task { await auth.signIn(email: email, password: password) } })

                authField(icon: "lock", placeholder: "Password",
                          text: $password, focused: $fieldFocused, field: .password, secure: true,
                          onSubmit: { guard !auth.isLoading && !email.isEmpty && !password.isEmpty else { return }; auth.authError = nil; Task { await auth.signIn(email: email, password: password) } })

                // Forgot Password link
                HStack {
                    Spacer()
                    Button {
                        forgotEmail = email
                        forgotSent = false
                        auth.authError = nil
                        withAnimation(.atlasSnap) { showForgotPassword = true }
                    } label: {
                        Text("Forgot Password?")
                            .font(.atlasFont(size: 11))
                            .foregroundColor(Color(hex: "#3ECFB2").opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }

                // Sign In button
                primaryButton("Sign In",
                              disabled: auth.isLoading || email.isEmpty || password.isEmpty) {
                    auth.authError = nil
                    Task { await auth.signIn(email: email, password: password) }
                }
            }
            .padding(20)
            .background(p.cardBodyBackground)
            .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.borderIdle, lineWidth: 0.75))
        .frame(width: 340)
    }

    // MARK: - Sign Up card (redirects to website)

    private var signUpCard: some View {
        VStack(spacing: 0) {
            // Mode toggle
            HStack(spacing: 0) {
                modeTab("Sign In",  target: .signIn)
                modeTab("Sign Up",  target: .signUp)
            }
            .background(p.cardHeaderBackground)
            .cornerRadius(10, corners: [.topLeft, .topRight])

            Divider().background(p.borderIdle)

            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.atlasFont(size: 28))
                        .foregroundColor(Color(hex: "#3ECFB2"))

                    Text("Create your account on our website")
                        .font(.atlasFont(size: 13, weight: .semibold))
                        .foregroundColor(p.textMain)
                        .multilineTextAlignment(.center)

                    Text("Choose your plan, create an account, and complete payment at interlinked.digital/atlas. Then return here to sign in.")
                        .font(.atlasFont(size: 11))
                        .foregroundColor(p.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // ToS checkbox
                tosCheckboxRow

                Button {
                    guard tosAgreed else { return }
                    if let url = URL(string: "https://interlinked.digital/atlas") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.atlasFont(size: 13))
                        Text("Open interlinked.digital/atlas")
                            .font(.atlasFont(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#0A0A0B"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "#3ECFB2"), Color(hex: "#2ABEAA")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(9)
                }
                .buttonStyle(.plain)
                .disabled(!tosAgreed)
                .opacity(tosAgreed ? 1 : 0.5)

                Button {
                    withAnimation(.atlasSnap) { mode = .signIn }
                } label: {
                    Text("Already have an account? Sign In →")
                        .font(.atlasFont(size: 11))
                        .foregroundColor(Color(hex: "#3ECFB2").opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(p.cardBodyBackground)
            .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.borderIdle, lineWidth: 0.75))
        .frame(width: 340)
    }

    // MARK: - Forgot Password card

    private var forgotPasswordCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    withAnimation(.atlasSnap) {
                        showForgotPassword = false
                        forgotSent = false
                        auth.authError = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.atlasFont(size: 11, weight: .semibold))
                        Text("Back to Sign In")
                            .font(.atlasFont(size: 12))
                    }
                    .foregroundColor(p.textSecondary)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(p.cardHeaderBackground)
            .cornerRadius(10, corners: [.topLeft, .topRight])

            Divider().background(p.borderIdle)

            VStack(spacing: 14) {
                if forgotSent {
                    // Success state
                    VStack(spacing: 10) {
                        Image(systemName: "envelope.badge.checkmark")
                            .font(.atlasFont(size: 28))
                            .foregroundColor(Color(hex: "#3ECFB2"))

                        Text("Check your email")
                            .font(.atlasFont(size: 13, weight: .semibold))
                            .foregroundColor(p.textMain)

                        Text("A password reset link has been sent to\n\(forgotEmail)")
                            .font(.atlasFont(size: 11))
                            .foregroundColor(p.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 8)
                } else {
                    // Error banner
                    if let err = auth.authError {
                        errorBanner(err)
                    }

                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.atlasFont(size: 11))
                        .foregroundColor(p.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    authField(icon: "envelope", placeholder: "Email address",
                              text: $forgotEmail, focused: $fieldFocused, field: .forgotEmail, secure: false)

                    primaryButton("Send Reset Link",
                                  disabled: auth.isLoading || forgotEmail.isEmpty) {
                        auth.authError = nil
                        Task {
                            await auth.forgotPassword(email: forgotEmail)
                            if auth.authError == nil {
                                await MainActor.run { forgotSent = true }
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(p.cardBodyBackground)
            .cornerRadius(10, corners: [.bottomLeft, .bottomRight])
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(p.borderIdle, lineWidth: 0.75))
        .frame(width: 340)
    }

    // MARK: - ToS checkbox

    private var tosCheckboxRow: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(tosAgreed
                          ? Color(hex: "#3ECFB2").opacity(0.12)
                          : p.inputFill)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(tosAgreed
                            ? Color(hex: "#3ECFB2")
                            : p.borderIdle, lineWidth: 1.5)
                if tosAgreed {
                    Image(systemName: "checkmark")
                        .font(.atlasFont(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
            }
            .frame(width: 18, height: 18)
            .animation(.atlasSnap, value: tosAgreed)
            .onTapGesture {
                withAnimation(.atlasSnap) { tosAgreed.toggle() }
            }

            HStack(spacing: 0) {
                Text("I agree to the ")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(p.textSecondary)
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showTosModal = true }
                } label: {
                    Text("Terms of Service")
                        .font(.atlasFont(size: 11))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .onTapGesture {
                withAnimation(.atlasSnap) { tosAgreed.toggle() }
            }

            Spacer()
        }
    }

    // MARK: - Shared components

    private var deviceLimitBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color(hex: "#E05555"))
                Text("Device limit reached")
                    .font(.atlasFont(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#E05555"))
                Spacer()
            }
            Text("Your ATLAS subscription allows up to 3 devices. Sign out on your other device first, or")
                .font(.atlasFont(size: 11))
                .foregroundColor(Color(hex: "#E05555"))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                NSWorkspace.shared.open(
                    URL(string: "https://interlinked.digital/atlas")!)
            } label: {
                Text("upgrade to Pro →")
                    .font(.atlasFont(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "#E05555").opacity(p.bannerBgOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: "#E05555").opacity(p.bannerBorderOpacity), lineWidth: 0.75))
    }

    @ViewBuilder
    private func emailUnconfirmedBanner(email: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "envelope.badge.fill")
                    .font(.atlasFont(size: 11))
                    .foregroundColor(Color(hex: "#F0A030"))
                Text("Email not confirmed")
                    .font(.atlasFont(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F0A030"))
                Spacer()
            }
            Text("Check your inbox for a confirmation link from interlinked.digital and click it before signing in.")
                .font(.atlasFont(size: 10))
                .foregroundColor(p.warningSubtext)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                auth.authErrorIsEmailUnconfirmed = false
                auth.authError = nil
                withAnimation(.atlasSnap) { showForgotPassword = false }
                Task { await auth.forgotPassword(email: email) }
            } label: {
                Text("Resend confirmation email →")
                    .font(.atlasFont(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#F0A030"))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "#F0A030").opacity(p.bannerBgOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: "#F0A030").opacity(p.bannerBorderOpacity), lineWidth: 0.75))
    }

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.atlasFont(size: 11))
                .foregroundColor(Color(hex: "#E05555"))
            Text(message)
                .font(.atlasFont(size: 11))
                .foregroundColor(Color(hex: "#E05555"))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Color(hex: "#E05555").opacity(p.bannerBgOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: "#E05555").opacity(p.bannerBorderOpacity), lineWidth: 0.75))
    }

    @ViewBuilder
    private func primaryButton(_ label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "#3ECFB2"), Color(hex: "#2ABEAA")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                if auth.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.75)
                        .tint(.white)
                } else {
                    Text(label)
                        .font(.atlasFont(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(height: 40)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Mode tab

    @ViewBuilder
    private func modeTab(_ title: String, target: Mode) -> some View {
        let active = mode == target
        Button {
            withAnimation(.atlasSnap) {
                mode = target
                auth.authError = nil
            }
        } label: {
            Text(title)
                .font(.atlasFont(size: 12, weight: active ? .semibold : .regular))
                .foregroundColor(active ? Color(hex: "#3ECFB2") : p.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(active ? p.cardHeaderBackground : Color.clear)
                .overlay(
                    Rectangle()
                        .fill(active ? Color(hex: "#3ECFB2") : Color.clear)
                        .frame(height: 2),
                    alignment: .bottom
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Field

    @ViewBuilder
    private func authField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        focused: Binding<Field?>,
        field: Field,
        secure: Bool,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        let isFocused = focused.wrappedValue == field
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.atlasFont(size: 13))
                .foregroundColor(isFocused ? Color(hex: "#3ECFB2") : p.iconIdle)
                .frame(width: 20)

            if secure && !showPassword {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.atlasFont(size: 13))
                    .foregroundColor(p.textMain)
                    .tint(Color(hex: "#3ECFB2"))
                    .onTapGesture { focused.wrappedValue = field }
                    .onSubmit { onSubmit?() }
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.atlasFont(size: 13))
                    .foregroundColor(p.textMain)
                    .tint(Color(hex: "#3ECFB2"))
                    .onTapGesture { focused.wrappedValue = field }
                    .onSubmit { onSubmit?() }
            }

            if secure {
                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.atlasFont(size: 12))
                        .foregroundColor(p.iconIdle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(p.inputFill)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isFocused ? Color(hex: "#3ECFB2").opacity(0.6) : p.borderIdle, lineWidth: 0.75)
        )
        .animation(.atlasSnap, value: isFocused)
    }
}

// MARK: - Auth palette (Light/Dark, driven by AppearanceManager)

/// Colors for the sign-in/sign-up screen only. Not a separate theme system —
/// this is computed from the same AppearanceManager.effective(_:) result the
/// rest of ATLAS uses; it just maps that single Light/Dark decision onto this
/// screen's specific hex palette. The teal accent (#3ECFB2) and error/warning
/// hues are intentionally identical in both themes — only their container
/// opacities and the neutral chrome (backgrounds/borders/text) change.
private struct AuthPalette {
    let pageBackground: Color
    let cardHeaderBackground: Color
    let cardBodyBackground: Color
    let inputFill: Color
    let borderIdle: Color
    let iconIdle: Color
    let textMain: Color
    let textSecondary: Color
    let footerText: Color
    let warningSubtext: Color
    let bannerBgOpacity: Double
    let bannerBorderOpacity: Double

    static func forScheme(_ scheme: ColorScheme) -> AuthPalette {
        switch scheme {
        case .dark:
            return AuthPalette(
                pageBackground:       Color(hex: "#0A0A0B"),
                cardHeaderBackground: Color(hex: "#0D0D0F"),
                cardBodyBackground:   Color(hex: "#111113"),
                inputFill:            Color(hex: "#0A0A0B"),
                borderIdle:           Color(hex: "#222226"),
                iconIdle:             Color(hex: "#44444E"),
                textMain:             Color(hex: "#FFFFFF"),
                textSecondary:        Color(hex: "#8A8A96"),
                footerText:           Color(hex: "#44444E"),
                warningSubtext:       Color(hex: "#C8902A"),
                bannerBgOpacity:      0.08,
                bannerBorderOpacity:  0.25
            )
        default: // .light (and any future case falls back to light, never dark)
            return AuthPalette(
                pageBackground:       Color(hex: "#F4F5F7"),
                cardHeaderBackground: Color(hex: "#EDEFF3"),
                cardBodyBackground:   Color(hex: "#FFFFFF"),
                inputFill:            Color(hex: "#F0F1F5"),
                borderIdle:           Color.black.opacity(0.10),
                iconIdle:             Color(hex: "#9497A3"),
                textMain:             Color(hex: "#14161A"),
                textSecondary:        Color(hex: "#6B6F7D"),
                footerText:           Color(hex: "#9497A3"),
                warningSubtext:       Color(hex: "#A9701E"),
                bannerBgOpacity:      0.06,
                bannerBorderOpacity:  0.20
            )
        }
    }
}

// MARK: - Corner radius helper

private extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }

    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft     = RectCorner(rawValue: 1 << 0)
    static let topRight    = RectCorner(rawValue: 1 << 1)
    static let bottomLeft  = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let all: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tl = corners.contains(.topLeft)     ? radius : 0
        let tr = corners.contains(.topRight)    ? radius : 0
        let bl = corners.contains(.bottomLeft)  ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + tr),
                                       control: CGPoint(x: rect.maxX, y: rect.minY)) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addQuadCurve(to: CGPoint(x: rect.maxX - br, y: rect.maxY),
                                       control: CGPoint(x: rect.maxX, y: rect.maxY)) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bl),
                                       control: CGPoint(x: rect.minX, y: rect.maxY)) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addQuadCurve(to: CGPoint(x: rect.minX + tl, y: rect.minY),
                                       control: CGPoint(x: rect.minX, y: rect.minY)) }
        path.closeSubpath()
        return path
    }
}
