import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - AppKit drop target (bypasses NSItemProvider — reliable on all architectures)

private final class DropTargetNSView: NSView {
    var onHover: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    private static let dragTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("com.apple.disk-image"),
        NSPasteboard.PasteboardType("public.item"),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Self.dragTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onHover?(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onHover?(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onHover?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop?(urls.map { $0.standardizedFileURL })
        return true
    }

    override var acceptsFirstResponder: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct DropTargetView: NSViewRepresentable {
    var onHover: (Bool) -> Void
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropTargetNSView {
        let v = DropTargetNSView()
        v.onHover = onHover
        v.onDrop  = onDrop
        return v
    }
    func updateNSView(_ nsView: DropTargetNSView, context: Context) {
        nsView.onHover = onHover
        nsView.onDrop  = onDrop
    }
}

// MARK: - SwiftUI wrapper

struct DropZoneView: View {
    @Binding var isTargeted: Bool
    var isQueuing: Bool = false   // true when an install is already running
    let onFileDrop: ([URL]) -> Void
    let onUnsupported: (String) -> Void

    @State private var buttonHovered = false
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var langMgr = LanguageManager.shared

    var body: some View {
        ZStack {
            // Surface — Liquid Chrome Glass: translucent base + directional wash + chrome edge,
            // brightening on drag-over. Replaces the prior flat-gradient/teal-tint surface.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    isTargeted
                        ? AnyShapeStyle(Color.atlasChromeUndertone.opacity(0.06))
                        : AnyShapeStyle(Color.clear)
                )
                .atlasGlass(.surface, cornerRadius: 16)

            // Border — polished-chrome perimeter, always clearly visible (not just on
            // drag-over). Solid, not dashed — a dashed line reads as a placeholder
            // convention, not machined metal trim. Drag-over brightens/thickens it.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    Color.chromeRimGradient.opacity(isTargeted ? 1.0 : 0.85),
                    lineWidth: isTargeted ? 3 : 2.25
                )

            // Inner rim — a second, inset chrome stroke so the pane reads as
            // physically constructed (outer trim + inner reveal), not a single outline.
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.chromeRimGradient.opacity(isTargeted ? 0.55 : 0.30), lineWidth: 0.75)
                .padding(3)

            // Content
            VStack(spacing: 18) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            isTargeted
                                ? Color.atlasChromeUndertone.opacity(0.14)
                                : Color(hex: scheme == .dark ? "#0F1228" : "#E8EAFF").opacity(0.8)
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: isTargeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 26, weight: isTargeted ? .medium : .light))
                        .foregroundStyle(Color.chromeRimGradient)
                        .opacity(isTargeted ? 1.0 : 0.85)
                        .scaleEffect(isTargeted ? 1.08 : 1.0)
                }
                .atlasChromeGlow(active: isTargeted)
                .shadow(
                    color: isTargeted ? Color.atlasChromeUndertone.opacity(0.25) : .clear,
                    radius: 12, y: 2
                )

                // Label
                VStack(spacing: 6) {
                    Text(isTargeted
                         ? (isQueuing ? "Release to add to queue" : L(.releaseToAdd))
                         : (isQueuing ? "Drop to add to queue" : L(.dropFilesHere)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.atlasOnGlassPrimary)

                    Text(isQueuing
                         ? "Added items will install automatically when the current install finishes"
                         : ".dmg  ·  .iso  ·  .zip  ·  .pkg  ·  .app  ·  plugins  ·  folders")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.atlasOnGlassSecondary)
                        .multilineTextAlignment(.center)
                }

                // Button
                Button(isQueuing ? "Choose file to queue" : L(.chooseFile)) { openFilePicker() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(buttonHovered ? Color.atlasChromeBase : Color.atlasSubtitle)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        buttonHovered
                            ? Color.atlasChromeUndertone.opacity(0.08)
                            : Color.atlasPanelBG
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                buttonHovered
                                    ? AnyShapeStyle(Color.chromeEdgeGradient.opacity(0.6))
                                    : AnyShapeStyle(Color.atlasBorder),
                                lineWidth: 0.75
                            )
                    )
                    .buttonStyle(.plain)
                    .scaleEffect(buttonHovered ? 1.02 : 1.0)
                    .animation(.atlasSnap, value: buttonHovered)
                    .onHover { buttonHovered = $0 }
            }

            // AppKit drag overlay
            DropTargetView(
                onHover: { hovering in withAnimation(.atlasSnap) { isTargeted = hovering } },
                onDrop: { urls in handleDrop(urls: urls) }
            )
        }
        .scaleEffect(isTargeted ? 1.006 : 1.0)
        .animation(.atlasSnap, value: isTargeted)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .shadow(
            color: isTargeted
                ? Color.atlasChromeUndertone.opacity(0.08)
                : (scheme == .dark ? .black.opacity(0.20) : .black.opacity(0.06)),
            radius: isTargeted ? 16 : 10,
            y: 2
        )
    }

    // MARK: - Drop handling (unchanged)

    private func handleDrop(urls: [URL]) {
        var resolved: [URL] = []
        for url in urls {
            if InstallerClassifier.isAtlasItself(url) {
                onFileDrop([url])
                return
            }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let dirExt = url.pathExtension.lowercased()
                if ["app", "component", "vst3", "vst", "aaxplugin"].contains(dirExt) {
                    resolved.append(url)
                } else if InstallerClassifier.findNcintFile(in: url) != nil {
                    resolved.append(url)
                } else {
                    resolved.append(contentsOf: collectFromFolder(url: url))
                }
            } else {
                let ext = url.pathExtension.lowercased()
                let supported = ["dmg", "iso", "zip", "app", "pkg",
                                 "mpkg", "component", "vst", "vst3", "aaxplugin"]
                if supported.contains(ext) || ext.isEmpty {
                    resolved.append(url)
                } else {
                    onUnsupported(ext)
                }
            }
        }
        if !resolved.isEmpty { onFileDrop(resolved) }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Select installer files or a folder"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = []
        panel.showsHiddenFiles = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }

        var resolved: [URL] = []
        for url in panel.urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let dirExt = url.pathExtension.lowercased()
                if ["app", "component", "vst3", "vst", "aaxplugin"].contains(dirExt) {
                    resolved.append(url)
                } else if InstallerClassifier.findNcintFile(in: url) != nil {
                    resolved.append(url)
                } else {
                    resolved.append(contentsOf: collectFromFolder(url: url))
                }
            } else {
                let ext = url.pathExtension.lowercased()
                let supported = ["dmg", "iso", "zip", "app", "pkg",
                                 "mpkg", "component", "vst", "vst3", "aaxplugin"]
                if supported.contains(ext) || ext.isEmpty {
                    resolved.append(url)
                } else {
                    onUnsupported(ext)
                }
            }
        }
        if !resolved.isEmpty { onFileDrop(resolved) }
    }

    private func collectFromFolder(url: URL) -> [URL] {
        // Plugin bundle extensions — treated as terminal installable units.
        let pluginExts    = Set(["component", "vst", "vst3", "aaxplugin"])
        // Installer/archive extensions — surfaced individually.
        let installerExts = Set(["dmg", "iso", "zip", "pkg", "mpkg", "app"])
        let fm = FileManager.default

        var pluginURLs:    [URL] = []
        var installerURLs: [URL] = []

        // Recursive walk — does NOT follow symlinks (FileManager.enumerator default).
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let item as URL in enumerator {
            let name = item.lastPathComponent
            guard !name.hasPrefix("._"), !name.hasPrefix(".") else { continue }
            let ext = item.pathExtension.lowercased()

            if pluginExts.contains(ext) {
                // Recognize plugin bundle as a terminal installable unit; do not crawl inside.
                pluginURLs.append(item)
                enumerator.skipDescendants()
            } else if installerExts.contains(ext) {
                // Installer or app — surface individually; skip bundle/archive contents.
                installerURLs.append(item)
                enumerator.skipDescendants()
            }
            // Instruction files, artwork, unrelated files: ignored at collection stage.
            // They are preserved when the folder itself is passed as a unit (plugin-only path).
        }

        // Mixed payload: both installer files and plugin bundles present — surface both.
        if !installerURLs.isEmpty {
            return installerURLs + pluginURLs
        }

        // Plugin-only payload (may include instructions/documentation/unrelated files):
        // pass the folder URL as a single unit so the full ATLAS scan path — including
        // instruction parsing via findAndParseInstructions — can process it correctly.
        if !pluginURLs.isEmpty {
            return [url]
        }

        // Nothing ATLAS recognizes inside this folder.
        return []
    }
}
