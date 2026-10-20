import SwiftUI

struct CombinedAgreementView: View {
    let onAccept: () -> Void

    static let tosKey     = "ATLAS.tosAccepted"
    static let privacyKey = "ATLAS.privacyConsentGiven"

    @State private var tosChecked      = false
    @State private var privacyChecked  = false
    @State private var tosExpanded     = false
    @State private var privacyExpanded = false
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 20
    @State private var continueHovered = false
    @State private var exitHovered     = false

    var canContinue: Bool { tosChecked && privacyChecked }

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
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Header: logo + ATLAS text ──────────────────────────
                    VStack(spacing: 8) {
                        // Oversized frame prevents glow rings from being clipped
                        ZStack {
                            AtlasStarView(size: 72, isAnimating: true)
                        }
                        .frame(width: 220, height: 180)

                        AtlasTitleText(size: 36, tracking: 12)
                            .padding(.top, -8)

                        Text("by InterLinked®")
                            .font(.atlasFont(size: 11, weight: .light))
                            .tracking(3)
                            .foregroundColor(Color(hex: "#696E7C"))
                            .padding(.top, 2)
                    }
                    .opacity(cardOpacity)
                    .padding(.top, 8)

                    Spacer().frame(height: 24)

                    // ── Agreement card ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 0) {

                        // Row 1 — Terms of Service
                        AgreementRow(
                            checked: $tosChecked,
                            expanded: $tosExpanded,
                            label: "Terms of Service",
                            fullText: TermsOfServiceContent.fullText
                        )

                        Rectangle()
                            .fill(Color(hex: "#1E2132"))
                            .frame(height: 1)

                        // Row 2 — Privacy Agreement
                        AgreementRow(
                            checked: $privacyChecked,
                            expanded: $privacyExpanded,
                            label: "Privacy Agreement",
                            fullText: PrivacyPolicyContent.fullText
                        )

                        Rectangle()
                            .fill(Color(hex: "#1E2132"))
                            .frame(height: 1)

                        // Buttons
                        HStack(spacing: 10) {
                            // Exit
                            Button("Exit") { NSApplication.shared.terminate(nil) }
                                .font(.atlasFont(size: 12, weight: .medium))
                                .foregroundColor(exitHovered ? Color(hex: "#F0F2FF") : Color(hex: "#696E7C"))
                                .padding(.horizontal, 20).padding(.vertical, 9)
                                .background(exitHovered ? Color(hex: "#141A30") : Color(hex: "#08091A"))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                                .buttonStyle(.plain)
                                .scaleEffect(exitHovered ? 1.02 : 1.0)
                                .animation(.spring(response: 0.2, dampingFraction: 0.8), value: exitHovered)
                                .onHover { exitHovered = $0 }

                            Spacer()

                            // Continue
                            Button {
                                guard canContinue else { return }
                                UserDefaults.standard.set(true, forKey: Self.tosKey)
                                UserDefaults.standard.set(true, forKey: Self.privacyKey)
                                onAccept()
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Continue")
                                        .font(.atlasFont(size: 13, weight: .semibold))
                                    Image(systemName: "arrow.right")
                                        .font(.atlasFont(size: 11, weight: .semibold))
                                }
                                .foregroundColor(canContinue ? Color(hex: "#08090E") : Color(hex: "#696E7C"))
                                .padding(.horizontal, 22).padding(.vertical, 10)
                                .background(
                                    canContinue
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
                                    .stroke(canContinue ? Color.clear : Color(hex: "#2E3350"), lineWidth: 1))
                                .shadow(color: canContinue
                                        ? Color(hex: "#3ECFB2").opacity(continueHovered ? 0.45 : 0.2)
                                        : Color.clear,
                                        radius: continueHovered ? 10 : 5, y: 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canContinue)
                            .scaleEffect(canContinue && continueHovered ? 1.03 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: continueHovered)
                            .animation(.easeInOut(duration: 0.2), value: canContinue)
                            .onHover { continueHovered = $0 }
                        }
                        .padding(24)
                    }
                    .background(Color(hex: "#0A0D1C"))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.5), radius: 32, y: 12)
                    .opacity(cardOpacity)
                    .offset(y: cardOffset)
                    .padding(.horizontal, 32)

                    Spacer().frame(height: 40)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 560)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.76).delay(0.1)) {
                cardOpacity = 1
                cardOffset  = 0
            }
        }
    }
}

// MARK: - Agreement row (checkbox + expandable full text)

private struct AgreementRow: View {
    @Binding var checked: Bool
    @Binding var expanded: Bool
    let label: String
    let fullText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Checkbox + label row
            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(checked
                              ? Color(hex: "#3ECFB2").opacity(0.15)
                              : Color(hex: "#08091A"))
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(checked
                                ? Color(hex: "#3ECFB2")
                                : Color(hex: "#2E3350"), lineWidth: 1.5)
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.atlasFont(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                    }
                }
                .frame(width: 20, height: 20)
                .animation(.easeInOut(duration: 0.15), value: checked)
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { checked.toggle() }
                }

                // Label text (underlined, tap to expand)
                HStack(spacing: 0) {
                    Text("I agree to the ")
                        .font(.atlasFont(size: 12))
                        .foregroundColor(Color(hex: "#9EA6B4"))
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            expanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.atlasFont(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .underline()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.atlasFont(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.15)) { checked.toggle() }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            // Expandable full text
            if expanded {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(fullText)
                        .font(.atlasFont(size: 11))
                        .foregroundColor(Color(hex: "#8890B0"))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                }
                .frame(maxHeight: 220)
                .background(Color(hex: "#07080F"))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
