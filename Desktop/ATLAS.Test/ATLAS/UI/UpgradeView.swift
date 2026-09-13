import SwiftUI
import AppKit

struct UpgradeView: View {
    let feature: String
    var onDismiss: () -> Void
    @ObservedObject private var appearance = AppearanceManager.shared

    private let teal  = Color(hex: "#3ECFB2")
    private let bg    = Color(hex: "#0A0A0B")
    private let card  = Color(hex: "#111113")
    private let sep   = Color(hex: "#222226")

    private let featureList: [(String, String)] = [
        ("checkmark.circle.fill", "Up to 3 devices"),
        ("checkmark.circle.fill", "25 installs / month"),
        ("checkmark.circle.fill", "Bulk queue installation"),
        ("checkmark.circle.fill", "TITAN CORE™ & Smart Storage"),
        ("checkmark.circle.fill", "Uninstall, Rollback & Recovery"),
        ("checkmark.circle.fill", "Virus Scanner & ATLAS CLEANER™"),
        ("checkmark.circle.fill", "Full install history"),
    ]

    var body: some View {
        VStack(spacing: 0) {

            // Header
            ZStack {
                LinearGradient(
                    colors: [Color(hex: "#111113"), bg],
                    startPoint: .top, endPoint: .bottom
                )
                VStack(spacing: 10) {
                    AtlasStarView(size: 40, isAnimating: true)
                    Text("Subscribe to ATLAS")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    if !feature.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10))
                                .foregroundColor(teal)
                            Text("\(feature) requires an ATLAS subscription")
                                .font(.system(size: 11))
                                .foregroundColor(teal)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(teal.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(teal.opacity(0.3), lineWidth: 0.75))
                    }
                }
                .padding(.vertical, 24)
            }

            Divider().background(sep)

            // Plan card
            VStack(alignment: .leading, spacing: 0) {

                // Card header
                HStack {
                    Text("ATLAS")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.2)
                        .foregroundColor(teal)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$30 / month")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Text("or $300 / year  (save $60)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#8890B0"))
                    }
                }
                .padding(14)
                .background(teal.opacity(0.07))

                Divider().background(sep)

                // Features
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(featureList, id: \.1) { icon, label in
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(teal)
                            Text(label)
                                .font(.system(size: 12))
                                .foregroundColor(Color(hex: "#CCCCCC"))
                        }
                    }
                }
                .padding(14)

                Divider().background(sep)

                // CTAs
                VStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "https://www.interlinked.digital/atlas/checkout?plan=atlas")!)
                        onDismiss()
                    } label: {
                        Text("Subscribe Monthly — $30/mo")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#08090E"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(teal)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "https://www.interlinked.digital/atlas/checkout?plan=atlas-annual")!)
                        onDismiss()
                    } label: {
                        Text("Subscribe Annually — $300/yr  (save $60)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(teal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(teal.opacity(0.12))
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(teal.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }
            .background(card)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(teal.opacity(0.3), lineWidth: 0.75))
            .padding(16)

            Divider().background(sep)

            Button { onDismiss() } label: {
                Text("Maybe Later")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#8A8A96"))
            }
            .buttonStyle(.plain)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(bg)
        }
        .frame(width: 360)
        .background(bg)
        .cornerRadius(14)
        .preferredColorScheme(appearance.override)
    }
}

private extension View {
    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
