import AppKit

// ============================================================
// MARK: - ATLAS ✧ Menu-Bar Icon (Candidate A — "Signature Sparkle")
// ============================================================
//
// Renders the approved ATLAS ✧ mark as a template NSImage for the macOS
// status item, replacing the generic system "sparkle" SF Symbol. Drawn
// programmatically (no new bundled asset, no Package.swift resource changes)
// as a four-point sparkle with elongated tips and a sharp concave waist —
// the same geometry approved in the icon-candidate review, based on the
// silhouette of AtlasResources/ATLAS.png and the atlas-visualizer mark.
//
// Template mode (isTemplate = true) is required: macOS applies its own
// adaptive black/white tint per menu-bar appearance, so this renders
// correctly in both Light and Dark automatically, with no color logic here.
//
// Presentation-layer only. No functional/business logic lives here.
enum ATLASMenuBarIcon {

    /// Returns the ✧ mark as a template NSImage sized for the menu bar.
    static func image(pointSize: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: pointSize, height: pointSize))
        img.lockFocus()

        let scale = pointSize / 24.0
        let transform = AffineTransform(scale: scale)

        let path = NSBezierPath()
        let top    = CGPoint(x: 12,   y: 22.8)   // NSImage y-axis is flipped vs SVG; top tip = high y
        let right  = CGPoint(x: 22.8, y: 12)
        let bottom = CGPoint(x: 12,   y: 1.2)
        let left   = CGPoint(x: 1.2,  y: 12)

        path.move(to: top)
        path.curve(to: right,
                   controlPoint1: CGPoint(x: 12.9, y: 13.7),
                   controlPoint2: CGPoint(x: 17.1, y: 12.6))
        path.curve(to: bottom,
                   controlPoint1: CGPoint(x: 17.1, y: 11.4),
                   controlPoint2: CGPoint(x: 12.9, y: 10.2))
        path.curve(to: left,
                   controlPoint1: CGPoint(x: 11.1, y: 10.2),
                   controlPoint2: CGPoint(x: 6.9,  y: 11.4))
        path.curve(to: top,
                   controlPoint1: CGPoint(x: 6.9,  y: 12.6),
                   controlPoint2: CGPoint(x: 11.1, y: 13.7))
        path.close()

        path.transform(using: transform)
        NSColor.black.setFill()
        path.fill()

        img.unlockFocus()
        img.isTemplate = true
        return img
    }
}
