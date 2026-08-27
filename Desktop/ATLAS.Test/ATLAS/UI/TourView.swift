import SwiftUI

// MARK: - Tour data

struct TourStep {
    let icon:     String
    let title:    String
    let body:     String
    let anchorID: String
}

private func makeTourSteps() -> [TourStep] { [
    TourStep(icon: "arrow.down.to.line.circle.fill",        title: L(.tourStep0Title), body: L(.tourStep0Body), anchorID: "dropZone"),
    TourStep(icon: "books.vertical.fill",                   title: L(.tourStep1Title), body: L(.tourStep1Body), anchorID: "history"),
    TourStep(icon: "square.stack.3d.down.right.fill",       title: L(.tourStep2Title), body: L(.tourStep2Body), anchorID: "installedProducts"),
    TourStep(icon: "arrow.uturn.backward.circle.fill",      title: L(.tourStep3Title), body: L(.tourStep3Body), anchorID: "installedProducts"),
    TourStep(icon: "sparkles",                              title: L(.tourStep4Title), body: L(.tourStep4Body), anchorID: "cleanerRow"),
    TourStep(icon: "lifepreserver",                         title: L(.tourStep5Title), body: L(.tourStep5Body), anchorID: "recoveryKitSection"),
    TourStep(icon: "gearshape.fill",                        title: L(.tourStep6Title), body: L(.tourStep6Body), anchorID: "settings"),
    TourStep(icon: "arrow.down.to.line.circle.fill",        title: L(.tourStep7Title), body: L(.tourStep7Body), anchorID: "dropZone"),
] }

// MARK: - Card height preference (used for dynamic layout)

private struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Arrow direction

private enum ArrowSide { case top, bottom, left, right, none }

// MARK: - TourView

struct TourView: View {
    @Binding var isShowing: Bool
    var frames: [String: CGRect]
    var containerSize: CGSize
    var onLibraryOpen: (() -> Void)? = nil
    var onTourEnd:     (() -> Void)? = nil

    @ObservedObject private var langMgr = LanguageManager.shared
    @AppStorage("atlas.tourDismissed") private var tourDismissed = false
    @State private var step = 0
    @State private var dontShowAgain = false
    @State private var cardOpacity: Double = 0
    @State private var cardOffset: CGFloat = 12
    @State private var cardHeight: CGFloat = 300

    private let cardW: CGFloat = 298
    private let arrowLen: CGFloat = 10
    private let gap: CGFloat = 14
    private let margin: CGFloat = 10

    private var tourSteps: [TourStep] { makeTourSteps() }
    private var current: TourStep { tourSteps[step] }
    private var isLast:  Bool { step == tourSteps.count - 1 }
    private var isFirst: Bool { step == 0 }

    // Returns (card top-left origin, which side the arrow is on, arrow position along that edge)
    // Uses measured cardHeight so the card never clips regardless of content length.
    private func layout() -> (CGPoint, ArrowSide, CGFloat) {
        let ch_card = cardHeight   // real measured height (or conservative default on first frame)
        let halfH   = ch_card / 2

        guard let rect = frames[current.anchorID], containerSize.width > 0 else {
            return (CGPoint(x: (containerSize.width - cardW) / 2,
                            y: (containerSize.height - ch_card) / 2), .none, cardW / 2)
        }
        let cw = containerSize.width
        let ch = containerSize.height

        let spaceRight = cw - rect.maxX
        let spaceLeft  = rect.minX
        let spaceBelow = ch - rect.maxY
        let spaceAbove = rect.minY

        // Right — prefer if there's room for the full card width + gap
        if spaceRight >= cardW + gap + margin {
            let x = rect.maxX + gap
            let y = (rect.midY - halfH).clamped(margin, ch - ch_card - margin)
            let arrowY = (rect.midY - y).clamped(20, ch_card - 20)
            return (CGPoint(x: x, y: y), .left, arrowY)
        }
        // Left
        if spaceLeft >= cardW + gap + margin {
            let x = rect.minX - gap - cardW
            let y = (rect.midY - halfH).clamped(margin, ch - ch_card - margin)
            let arrowY = (rect.midY - y).clamped(20, ch_card - 20)
            return (CGPoint(x: x, y: y), .right, arrowY)
        }
        // Below — only if the full card fits below the anchor
        if spaceBelow >= ch_card + gap + margin {
            let x = (rect.midX - cardW / 2).clamped(margin, cw - cardW - margin)
            let y = rect.maxY + gap
            let arrowX = (rect.midX - x).clamped(20, cardW - 20)
            return (CGPoint(x: x, y: y), .top, arrowX)
        }
        // Above — clamp so card never goes below window bottom
        let x = (rect.midX - cardW / 2).clamped(margin, cw - cardW - margin)
        let y = (rect.minY - gap - ch_card).clamped(margin, ch - ch_card - margin)
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
                .background(GeometryReader { geo in
                    Color.clear.preference(key: CardHeightKey.self, value: geo.size.height)
                })
                .offset(x: origin.x, y: origin.y)
                .opacity(cardOpacity)
                .offset(y: cardOffset)
                .animation(.spring(response: 0.38, dampingFraction: 0.78), value: step)
        }
        .onPreferenceChange(CardHeightKey.self) { h in
            if abs(h - cardHeight) > 1 { cardHeight = h }
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
                    Text(L(.tourAtlasTitle))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    Text("· \(String(format: L(.tourStepOfFmt), step + 1, tourSteps.count))")
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
                        Text(L(.tourDontShowAgain))
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
                                Text(L(.tourBack)).font(.system(size: 11, weight: .medium))
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
                            Text(isLast ? L(.done) : L(.tourNext)).font(.system(size: 11, weight: .semibold))
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
        let next = max(0, min(tourSteps.count - 1, step + dir))
        // Stepping forward from step 1 → step 2 opens the Library panel first
        if dir > 0 && step == 1 && next == 2 {
            onLibraryOpen?()
            withAnimation(.easeOut(duration: 0.15)) { cardOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { step = next }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { cardOpacity = 1 }
            }
            return
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { step = next }
    }

    private func close() {
        if dontShowAgain { tourDismissed = true }
        withAnimation(.easeOut(duration: 0.18)) { cardOpacity = 0; cardOffset = 8 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isShowing = false
            onTourEnd?()
        }
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
