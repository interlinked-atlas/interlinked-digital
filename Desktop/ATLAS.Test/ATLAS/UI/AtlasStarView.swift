import SwiftUI
import AppKit

// MARK: - AtlasStarView

struct AtlasStarView: View {
    var size: CGFloat = 80
    var isAnimating: Bool = true

    var body: some View {
        LiquidMetalView(size: size, clipToCircle: true, videoFile: "atlas-visualizer")
    }
}

// MARK: - Installing variant

struct InstallingStarView: View {
    var body: some View {
        LiquidMetalView(size: 200, clipToCircle: false, videoFile: "atlas-visualizer")
            .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
}

// MARK: - ATLAS title text
// Uses NSTextField so glyphs are never clipped by typographic cell bounds.
// Decorative fonts like "SF Intellivised" have serifs/crossbars that extend
// past the advance width — SwiftUI Text clips at those bounds, NSTextField doesn't.

struct AtlasTitleText: View {
    let size: CGFloat
    let tracking: CGFloat

    var body: some View {
        ATLASNSLabel(text: "ATLAS", fontSize: size, kern: tracking)
            .fixedSize()   // shrink-wrap to intrinsic size so parent centers it
    }
}

private struct ATLASNSLabel: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let kern: CGFloat

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.isEditable = false
        field.isSelectable = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.allowsDefaultTighteningForTruncation = false
        field.alignment = .center
        apply(to: field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        apply(to: field)
    }

    private func apply(to field: NSTextField) {
        let font = NSFont(name: "SF Intellivised", size: fontSize)
                ?? NSFont.systemFont(ofSize: fontSize, weight: .thin)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: kern,
        ]
        field.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
        field.sizeToFit()
    }
}
