import SwiftUI
import AppKit

struct SubscriptionRequiredView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var checking = false
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 20

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

            VStack(spacing: 0) {
                Spacer()

                // Logo
                VStack(spacing: 10) {
                    ZStack { AtlasStarView(size: 64, isAnimating: true) }
                        .frame(width: 180, height: 160)
                    AtlasTitleText(size: 32, tracking: 10)
                    Text("by InterLinked®")
                        .font(.system(size: 11, weight: .light))
                        .tracking(3)
                        .foregroundColor(Color(hex: "#696E7C"))
                }
                .opacity(cardOpacity)

                Spacer().frame(height: 28)

                // Card
                VStack(alignment: .leading, spacing: 20) {
                    // Back button row
                    HStack {
                        Button {
                            auth.signOut()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(L(.backToSignIn))
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(Color(hex: "#696E7C"))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }

                    // Icon + heading
                    HStack(spacing: 10) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 13))
                            .foregroundColor(Color(hex: statusColor))
                        Text(headingText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0F2FF"))
                    }

                    Text(bodyText)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8890B0"))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    // Plan card (brief) — only show for new/cancelled users
                    if auth.profile?.subscriptionStatus != "payment_failed" {
                        HStack(spacing: 10) {
                            planPill(name: "ATLAS", price: "$30/mo · $300/yr", color: "#3ECFB2")
                        }
                    }

                    Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)

                    // Buttons
                    VStack(spacing: 10) {
                        // Subscribe button
                        Button {
                            let url = auth.profile?.subscriptionStatus == "payment_failed"
                                ? "https://www.interlinked.digital/atlas/account"
                                : "https://www.interlinked.digital/atlas"
                            NSWorkspace.shared.open(URL(string: url)!)
                        } label: {
                            HStack(spacing: 6) {
                                Text(subscribeButtonLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "#08090E"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(hex: "#3ECFB2"))
                            .cornerRadius(9)
                        }
                        .buttonStyle(.plain)

                        // Already subscribed — refresh
                        Button {
                            checking = true
                            Task {
                                await auth.refreshProfile()
                                await MainActor.run { checking = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                if checking {
                                    ProgressView().scaleEffect(0.65).frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                Text(checking ? L(.checkingEllipsis) : L(.iveSubscribed))
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(Color(hex: "#696E7C"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color(hex: "#0A0D1C"))
                            .cornerRadius(9)
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(checking)

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

                Spacer()
            }
        }
        .frame(minWidth: 560, minHeight: 580)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.76).delay(0.1)) {
                cardOpacity = 1; cardOffset = 0
            }
        }
    }

    private var statusIcon: String {
        switch auth.profile?.subscriptionStatus {
        case "cancelled":     return "arrow.counterclockwise.circle.fill"
        case "payment_failed": return "exclamationmark.circle.fill"
        default:              return "lock.fill"
        }
    }
    private var statusColor: String {
        switch auth.profile?.subscriptionStatus {
        case "cancelled":     return "#F0A030"
        case "payment_failed": return "#E05555"
        default:              return "#E05555"
        }
    }
    private var headingText: String {
        switch auth.profile?.subscriptionStatus {
        case "cancelled":     return L(.reJoinAtlas)
        case "payment_failed": return L(.paymentFailed)
        default:              return L(.subscriptionRequired)
        }
    }
    private var bodyText: String {
        switch auth.profile?.subscriptionStatus {
        case "cancelled":
            return L(.subBodyReJoin)
        case "payment_failed":
            return L(.subBodyPayment)
        default:
            return L(.subBodyNew)
        }
    }
    private var subscribeButtonLabel: String {
        switch auth.profile?.subscriptionStatus {
        case "cancelled":     return L(.reJoinAtlas)
        case "payment_failed": return L(.updateBilling)
        default:              return L(.subscribeNow)
        }
    }

    private func planPill(name: String, price: String, color: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: color))
            Text(price)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#696E7C"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: color).opacity(0.06))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(hex: color).opacity(0.25), lineWidth: 1))
    }
}
