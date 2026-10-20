import SwiftUI

struct ZIPPasswordRequest: Identifiable {
    let id = UUID()
    let fileName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
}

struct ZIPPasswordView: View {
    let request: ZIPPasswordRequest
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var password: String = ""
    @State private var showPassword: Bool = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#7090B8").opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(hex: "#7090B8"))
                }

                VStack(spacing: 6) {
                    Text(L(.passwordRequired))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "#7090B8"))
                        .tracking(3)

                    Text(L(.filePasswordProtected))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(hex: "#F0F2F5"))

                    Text(request.fileName)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "#696E7C"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            // ── Password field ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text(L(.archivePassword))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Color(hex: "#353860"))
                    .tracking(2)

                ZStack(alignment: .trailing) {
                    Group {
                        if showPassword {
                            TextField(L(.enterPassword), text: $password)
                                .focused($fieldFocused)
                        } else {
                            SecureField(L(.enterPassword), text: $password)
                                .focused($fieldFocused)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Color(hex: "#F0F2F5"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .padding(.trailing, 36)
                    .background(Color(hex: "#07080F"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                password.isEmpty
                                    ? Color(hex: "#1E2240")
                                    : Color(hex: "#7090B8").opacity(0.5),
                                lineWidth: 1)
                    )
                    .cornerRadius(8)
                    .onSubmit { submitIfValid() }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#353860"))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                }

                Text(L(.rememberPassword))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#353860"))
                    .lineLimit(2)
            }
            .padding(.horizontal, 28)

            // ── Buttons ─────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Button {
                    request.onCancel()
                } label: {
                    Text(L(.cancel))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#696E7C"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Color(hex: "#0C0E1C"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color(hex: "#1E2240"), lineWidth: 1)
                        )
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)

                Button {
                    submitIfValid()
                } label: {
                    Text(L(.unlockAndInstall))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(password.isEmpty ? Color(hex: "#353860") : Color(hex: "#08090E"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(password.isEmpty ? Color(hex: "#16181E") : Color(hex: "#7090B8"))
                        .cornerRadius(9)
                }
                .buttonStyle(.plain)
                .disabled(password.isEmpty)
                .animation(.easeInOut(duration: 0.15), value: password.isEmpty)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 28)
        }
        .frame(width: 400)
        .background(Color(hex: "#0C0E1C"))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(hex: "#1E2240"), lineWidth: 1)
        )
        .onAppear { fieldFocused = true }
    }

    private func submitIfValid() {
        guard !password.isEmpty else { return }
        request.onSubmit(password)
    }
}
