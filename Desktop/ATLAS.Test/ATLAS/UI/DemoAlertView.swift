import SwiftUI

// MARK: - Model

struct DemoAlert: Identifiable {
    let id = UUID()
    let productName: String
    let hits: [DemoHit]
}

// MARK: - View

struct DemoAlertView: View {
    let alert: DemoAlert
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ───────────────────────────────────────────────────────
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "#F0A030").opacity(0.12))
                        .frame(width: 64, height: 64)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "#F0A030"))
                }

                VStack(spacing: 6) {
                    Text("DEMO MODE DETECTED")
                        .font(.system(size: 10, weight: .bold)).tracking(2.5)
                        .foregroundColor(Color(hex: "#F0A030"))

                    Text(alert.productName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(hex: "#F0F2FF"))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text("ATLAS installed this product, but detected signs that it may be running in demo or trial mode. The license may not have applied correctly.")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#9EA6B4"))
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 28)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)

            // ── Signals found ────────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SIGNALS FOUND")
                        .font(.system(size: 9, weight: .bold)).tracking(2)
                        .foregroundColor(Color(hex: "#353860"))
                        .padding(.bottom, 2)

                    ForEach(Array(alert.hits.prefix(6).enumerated()), id: \.offset) { _, hit in
                        HStack(alignment: .top, spacing: 10) {
                            Text(hit.source)
                                .font(.system(size: 9, weight: .bold)).tracking(1)
                                .foregroundColor(Color(hex: "#F0A030").opacity(0.8))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color(hex: "#F0A030").opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(minWidth: 50)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\"\(hit.keyword)\"")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F0F2FF"))
                                Text(hit.context)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "#696E7C"))
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .background(Color(hex: "#0D1020"))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#F0A030").opacity(0.15), lineWidth: 0.75))
                    }

                    if alert.hits.count > 6 {
                        Text("+ \(alert.hits.count - 6) more signal(s) — see install log for details")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#696E7C"))
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: 220)

            Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)

            // ── What to do ───────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT THIS MEANS")
                    .font(.system(size: 9, weight: .bold)).tracking(2)
                    .foregroundColor(Color(hex: "#353860"))

                VStack(alignment: .leading, spacing: 5) {
                    tipRow(icon: "doc.badge.arrow.up", text: "The software was installed but may need a license file manually placed")
                    tipRow(icon: "arrow.clockwise", text: "Try reinstalling — drop the same package again and ATLAS will re-run")
                    tipRow(icon: "questionmark.circle", text: "Use the Support button in ATLAS Library to get help from the ATLAS team")
                }
            }
            .padding(20)

            Rectangle().fill(Color(hex: "#1E2132")).frame(height: 1)

            // ── Buttons ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#9EA6B4"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#141A30"))
                        .cornerRadius(9)
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(Color(hex: "#2E3350"), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onDismiss) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Back to ATLAS")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#08090E"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(hex: "#F0A030"))
                    .cornerRadius(9)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 420)
        .background(Color(hex: "#0A0D1C"))
        .cornerRadius(16)
    }

    @ViewBuilder
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#696E7C"))
                .frame(width: 14)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#696E7C"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
