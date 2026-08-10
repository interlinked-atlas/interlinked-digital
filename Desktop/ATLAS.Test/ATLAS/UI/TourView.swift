import SwiftUI

// MARK: - Tour data

struct TourStep {
    let icon:     String
    let title:    String
    let body:     String
    let anchorID: String
}

let tourSteps: [TourStep] = [
    TourStep(icon: "arrow.down.to.line.circle.fill", title: "Drop Zone",
             body: "Drag any installer here — DMG, ZIP, PKG, RAR, VST3, or AAX. ATLAS reads the file and figures out exactly what's inside before touching your system.",
             anchorID: "dropZone"),
    TourStep(icon: "doc.text.magnifyingglass", title: "Scan Result",
             body: "After scanning, ATLAS shows a full breakdown — what's inside, compatibility warnings, existing install detection, and a confidence score. Nothing installs until you say so.",
             anchorID: "scanResult"),
    TourStep(icon: "arrow.down.circle.fill", title: "Install Button",
             body: "One tap installs everything. ATLAS handles admin permissions, quarantine removal, correct plugin paths, and Rosetta 2 compatibility automatically.",
             anchorID: "installButton"),
    TourStep(icon: "checkmark.shield.fill", title: "TITAN CORE™",
             body: "After every install, TITAN CORE™ verifies the result — checks files landed in the right place, strips security flags, and confirms nothing is in demo or trial mode.",
             anchorID: "titanCore"),
    TourStep(icon: "books.vertical.fill", title: "ATLAS Library",
             body: "Every install is saved in ATLAS Library. Search your installs, manage plugin formats, and Pro users can uninstall or roll back any install with one tap.",
             anchorID: "history"),
    TourStep(icon: "gearshape.fill", title: "Settings",
             body: "Manage your account, devices, password, storage, and plan here. You can replay Tour ATLAS anytime from the Settings screen.",
             anchorID: "settings"),
    TourStep(icon: "rectangle.compress.vertical", title: "Widget Mode",
             body: "Tap the widget button in the bottom bar to shrink ATLAS into a compact overlay that floats above your desktop. It shows live install progress and lets you expand back with one tap.",
             anchorID: "widget"),
]

// MARK: - Arrow direction

private enum ArrowSide { case top, bottom, left, right, none }

// MARK: - TourView

struct TourView: View {
    @Binding var isShowing: Bool
    var frames: [String: CGRect]
    var containerSize: CGSize

    @AppStorage("atlas.tourDismissed") private var tourDismissed = false
    @State private var step = 0
    @State private var dontShowAgain = false
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 12

    private let cardW: CGFloat = 298
    private let arrowLen: CGFloat = 10
    private let gap: CGFloat = 14
    private let margin: CGFloat = 10

    private var current: TourStep { tourSteps[step] }
    private var isLast:  Bool { step == tourSteps.count - 1 }
    private var isFirst: Bool { step == 0 }

    // Returns (card top-left origin, which side the arrow is on, arrow position along that edge)
    private func layout() -> (CGPoint, ArrowSide, CGFloat) {
        guard let rect = frames[current.anchorID], containerSize.width > 0 else {
            return (CGPoint(x: (containerSize.width - cardW) / 2,
                            y: (containerSize.height - 260) / 2), .none, cardW / 2)
        }
        let cw = containerSize.width
        let ch = containerSize.height

        let spaceRight = cw - rect.maxX
        let spaceLeft  = rect.minX
        let spaceBelow = ch - rect.maxY
        let spaceAbove = rect.minY

        // Right
        if spaceRight >= cardW + gap + margin {
            let x = rect.maxX + gap
            let y = (rect.midY - 130).clamped(margin, ch - 260 - margin)
            let arrowY = (rect.midY - y).clamped(20, 220)
            return (CGPoint(x: x, y: y), .left, arrowY)
        }
        // Left
        if spaceLeft >= cardW + gap + margin {
            let x = rect.minX - gap - cardW
            let y = (rect.midY - 130).clamped(margin, ch - 260 - margin)
            let arrowY = (rect.midY - y).clamped(20, 220)
            return (CGPoint(x: x, y: y), .right, arrowY)
        }
        // Below
        if spaceBelow >= 200 + gap + margin {
            let x = (rect.midX - cardW / 2).clamped(margin, cw - cardW - margin)
            let y = rect.maxY + gap
            let arrowX = (rect.midX - x).clamped(20, cardW - 20)
            return (CGPoint(x: x, y: y), .top, arrowX)
        }
        // Above
        let x = (rect.midX - cardW / 2).clamped(margin, cw - cardW - margin)
        let y = max(margin, rect.minY - gap - 260)
        let arrowX = (rect.midX - x).clamped(20, cardW - 20)
        return (CGPoint(x: x, y: y), .bottom, arrowX)
    }

    var body: some View {
        let (origin, arrowSide, arrowOffset) = layout()
        let anchorRect = frames[current.anchorID]

        ZStack(alignment: .topLeading) {
            // Backdrop
            Color.black.opacity(0.50)
                .ignoresSafeArea()

            // Spotlight ring
            if let rect = anchorRect {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(hex: "#3ECFB2").opacity(0.9), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: "#3ECFB2").opacity(0.05))
                    )
                    .frame(width: rect.width + 12, height: rect.height + 12)
                    .position(x: rect.midX, y: rect.midY)
                    .shadow(color: Color(hex: "#3ECFB2").opacity(0.55), radius: 14)
                    .animation(.spring(response: 0.38, dampingFraction: 0.75), value: step)
            }

            // Card + arrow
            cardView(arrowSide: arrowSide, arrowOffset: arrowOffset)
                .frame(width: cardW)
                .offset(x: origin.x, y: origin.y)
                .opacity(cardOpacity)
                .offset(y: cardOffset)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: step)
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                cardOpacity = 1; cardOffset = 0
            }
        }
    }

    @ViewBuilder
    private func cardView(arrowSide: ArrowSide, arrowOffset: CGFloat) -> some View {
        VStack(spacing: 0) {
            // Top arrow
            if arrowSide == .top {
                arrowTriangle(pointing: .top)
                    .frame(width: arrowLen * 2, height: arrowLen)
                    .padding(.leading, arrowOffset - arrowLen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 0) {
                // Header
                HStack(spacing: 4) {
                    Text("Tour ATLAS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    Text("· \(step + 1) of \(tourSteps.count)")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#696E7C"))
                    Spacer()
                    Button { close() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#696E7C"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 15)
                .padding(.top, 13)
                .padding(.bottom, 9)

                Divider().background(Color(hex: "#1E2132"))

                // Body
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 9) {
                        Image(systemName: current.icon)
                            .font(.system(size: 17))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .frame(width: 30, height: 30)
                            .background(Color(hex: "#3ECFB2").opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        Text(current.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(hex: "#F0F2FF"))
                    }
                    Text(current.body)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8890B0"))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 5) {
                        ForEach(0..<tourSteps.count, id: \.self) { i in
                            Circle()
                                .fill(i == step ? Color(hex: "#3ECFB2") : Color(hex: "#3ECFB2").opacity(0.25))
                                .frame(width: i == step ? 6 : 4, height: i == step ? 6 : 4)
                                .animation(.spring(response: 0.3), value: step)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)

                // Don't show again
                if isFirst {
                    Divider().background(Color(hex: "#1E2132"))
                    HStack(spacing: 7) {
                        Image(systemName: dontShowAgain ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundColor(dontShowAgain ? Color(hex: "#3ECFB2") : Color(hex: "#696E7C"))
                        Text("Don't show this again")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#696E7C"))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { dontShowAgain.toggle() }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                }

                Divider().background(Color(hex: "#1E2132"))

                // Nav buttons
                HStack(spacing: 8) {
                    if !isFirst {
                        Button { navigate(-1) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                                Text("Back").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Color(hex: "#696E7C"))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Color(hex: "#0A0D1C"))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color(hex: "#1E2132"), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        if isLast { if dontShowAgain { tourDismissed = true }; close() } else { navigate(1) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isLast ? "Done" : "Next").font(.system(size: 11, weight: .semibold))
                            if !isLast { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)) }
                        }
                        .foregroundColor(Color(hex: "#08090E"))
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
            }
            .background(Color(hex: "#0A0D1C"))
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color(hex: "#3ECFB2").opacity(0.35), Color(hex: "#7090B8").opacity(0.15)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 28, y: 10)
            // Left/right arrows as overlays on the card box
            .overlay(alignment: .topLeading) {
                if arrowSide == .left {
                    arrowTriangle(pointing: .left)
                        .frame(width: arrowLen, height: arrowLen * 2)
                        .offset(x: -arrowLen + 1, y: arrowOffset - arrowLen)
                }
            }
            .overlay(alignment: .topLeading) {
                if arrowSide == .right {
                    arrowTriangle(pointing: .right)
                        .frame(width: arrowLen, height: arrowLen * 2)
                        .offset(x: cardW - 1, y: arrowOffset - arrowLen)
                }
            }

            // Bottom arrow
            if arrowSide == .bottom {
                arrowTriangle(pointing: .bottom)
                    .frame(width: arrowLen * 2, height: arrowLen)
                    .padding(.leading, arrowOffset - arrowLen)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func navigate(_ dir: Int) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
            step = max(0, min(tourSteps.count - 1, step + dir))
        }
    }

    private func close() {
        if dontShowAgain { tourDismissed = true }
        withAnimation(.easeOut(duration: 0.18)) { cardOpacity = 0; cardOffset = 8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isShowing = false }
    }

    @ViewBuilder
    private func arrowTriangle(pointing direction: ArrowSide) -> some View {
        ArrowShape(direction: direction).fill(Color(hex: "#0A0D1C"))
    }
}

// MARK: - Arrow shape

private struct ArrowShape: Shape {
    let direction: ArrowSide
    func path(in rect: CGRect) -> Path {
        Path { p in
            switch direction {
            case .top:
                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .bottom:
                p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            case .left:
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            case .right:
                p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            case .none:
                break
            }
            p.closeSubpath()
        }
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}
