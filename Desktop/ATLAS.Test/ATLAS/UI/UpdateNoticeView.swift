import SwiftUI

extension Notification.Name {
    /// Posted by the ✧ menu-bar "Check for Updates" action. ContentView listens
    /// for this to show UpdateNoticeView — the only integration point between
    /// the AppKit status item and this SwiftUI popup.
    static let atlasShowUpdateNotice = Notification.Name("atlasShowUpdateNotice")
}

// Simple informational popup shown from ✧ → "Check for Updates" for ATLAS v1.
// No network activity, no update feed, no Sparkle — purely informational.
// Visual treatment reuses the established ATLAS Liquid Chrome Glass modal
// system (Core/ATLASGlass.swift) — the same chrome-glass card language as
// UpgradeView's modal — plus the on-glass text tokens and the ATLAS ✧ chrome
// mark itself, so this reads as a native ATLAS surface rather than a generic
// SwiftUI alert. No functional change from the prior version.
struct UpdateNoticeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // ── Header (close button, top-right) — chrome-consistent, matching
            // the icon/border treatment used throughout the glass system.
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.chromeRimGradient)
                        .frame(width: 24, height: 24)
                        .background(Color.atlasPanelBG)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.chromeRimGradient.opacity(0.5), lineWidth: 0.75))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, ATLASSpacing.lg)
            .padding(.trailing, ATLASSpacing.lg)

            // ── Content ──────────────────────────────────────────────────────
            VStack(spacing: ATLASSpacing.md) {
                Image(nsImage: ATLASMenuBarIcon.image(pointSize: 40))
                    .renderingMode(.template)
                    .foregroundStyle(Color.chromeRimGradient)
                    .frame(width: 56, height: 56)

                Text("ATLAS updates will be released on InterLinked's website when v2 is announced.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.atlasOnGlassPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, ATLASSpacing.lg)
            }
            .padding(.top, ATLASSpacing.xs)
            .padding(.bottom, ATLASSpacing.xxl)
        }
        .frame(width: 360)
        .atlasGlass(.surface, cornerRadius: ATLASRadius.xl, modalStrength: 0.15)
    }
}
