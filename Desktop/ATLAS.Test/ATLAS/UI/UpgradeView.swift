import SwiftUI
import AppKit

struct UpgradeView: View {
    let feature: String
    var onDismiss: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared
    @ObservedObject private var auth = AuthManager.shared

    private var isStandard: Bool { !auth.isPro && auth.session != nil }

    var body: some View {
        VStack(spacing: 0) {

            // Header
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#111113"), Color(hex: "#0A0A0B")],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 10) {
                    AtlasStarView(size: 40, isAnimating: true)
                    Text(isStandard ? "Upgrade to Pro" : "Choose Your Plan")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "#FFFFFF"))
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#F0A030"))
                        Text("\(feature) is a Pro feature")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#F0A030"))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color(hex: "#F0A030").opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(hex: "#F0A030").opacity(0.3), lineWidth: 0.75))
                }
                .padding(.vertical, 24)
            }

            Divider().background(Color(hex: "#222226"))

            // Plan cards
            HStack(alignment: .top, spacing: 12) {
                planCard(
                    name: "Standard",
                    color: Color(hex: "#7090B8"),
                    features: [
                        ("checkmark", "Single file installation"),
                        ("checkmark", "TITAN CORE™ intelligence"),
                        ("checkmark", "ATLAS Library (last 5 records)"),
                        ("checkmark", "Notifications"),
                        ("checkmark", "3 installs/day · 10/month"),
                        ("checkmark", "Storage Manager"),
                        ("xmark", "Bulk installation"),
                        ("xmark", "Uninstall & Rollback"),
                    ],
                    ctaLabel: isStandard ? "Your Current Plan" : "Subscribe — Standard",
                    url: "https://www.interlinked.digital/atlas/plans",
                    recommended: false,
                    isCurrent: isStandard
                )

                planCard(
                    name: "Pro",
                    color: Color(hex: "#3ECFB2"),
                    features: [
                        ("checkmark", "Everything in Standard"),
                        ("checkmark", "Bulk installation"),
                        ("checkmark", "Uninstall & Rollback"),
                        ("checkmark", "Restore"),
                        ("checkmark", "Storage Manager"),
                        ("checkmark", "25 installs/month · no daily cap"),
                        ("checkmark", "Up to 3 devices"),
                    ],
                    ctaLabel: isStandard ? "Upgrade to Pro →" : "Subscribe — Pro",
                    url: "https://www.interlinked.digital/atlas/plans",
                    recommended: true,
                    isCurrent: false
                )
            }
            .padding(16)
            .background(Color(hex: "#0A0A0B"))

            Divider().background(Color(hex: "#222226"))

            // Dismiss
            Button { onDismiss() } label: {
                Text("Maybe Later")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A8A96"))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color(hex: "#0A0A0B"))
        }
        .frame(width: 480)
        .background(Color(hex: "#0A0A0B"))
        .cornerRadius(14)
        .preferredColorScheme(appearance.override)
    }

    // MARK: - Plan card

    @ViewBuilder
    private func planCard(
        name: String,
        color: Color,
        features: [(String, String)],
        ctaLabel: String,
        url: String,
        recommended: Bool,
        isCurrent: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // Card header
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name.uppercased())
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.2)
                        .foregroundColor(color)
                    Spacer()
                    if isCurrent {
                        Text("CURRENT PLAN")
                            .font(.system(size: 7, weight: .black))
                            .tracking(0.8)
                            .foregroundColor(Color(hex: "#7090B8"))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: "#7090B8").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color(hex: "#7090B8").opacity(0.3), lineWidth: 0.75))
                    } else if recommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 7, weight: .black))
                            .tracking(0.8)
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: "#3ECFB2").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color(hex: "#3ECFB2").opacity(0.3), lineWidth: 0.75))
                    }
                }
            }
            .padding(12)
            .background(color.opacity(0.07))

            Divider().background(Color(hex: "#222226"))

            // Features
            VStack(alignment: .leading, spacing: 7) {
                ForEach(features, id: \.1) { icon, label in
                    let included = icon == "checkmark"
                    HStack(spacing: 7) {
                        Image(systemName: included ? "checkmark" : "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(included ? color : Color(hex: "#44444E"))
                            .frame(width: 12)
                        Text(label)
                            .font(.system(size: 11))
                            .foregroundColor(included ? Color(hex: "#CCCCCC") : Color(hex: "#44444E"))
                    }
                }
            }
            .padding(12)

            Spacer(minLength: 0)

            // CTA button
            Button {
                guard !isCurrent else { return }
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } label: {
                Text(ctaLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(
                        isCurrent ? Color(hex: "#696E7C") :
                        recommended ? Color(hex: "#0A0A0B") : color
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        isCurrent
                            ? LinearGradient(colors: [Color(hex: "#1E1E22"), Color(hex: "#1E1E22")],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
                            : recommended
                                ? LinearGradient(colors: [color, color.opacity(0.8)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [color.opacity(0.12), color.opacity(0.12)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .cornerRadius(8)
                    .overlay(
                        isCurrent
                            ? RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "#2E2E34"), lineWidth: 1)
                            : recommended ? nil
                                : RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)
            .padding([.horizontal, .bottom], 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color(hex: "#111113"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(recommended ? color.opacity(0.3) : Color(hex: "#222226"), lineWidth: 0.75)
        )
    }
}

// Corner radius helper (reused from AuthView)
private extension View {
    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
