import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - RecoverySlotRow

struct RecoverySlotRow: View {
    let slot: RecoverySlot
    var onSetInstaller: (URL) -> Void
    var onInstall: () -> Void
    var onSkip: () -> Void
    var onRetry: () -> Void

    @ObservedObject private var monthlyLimit = MonthlyLimitManager.shared
    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Product header
            HStack(spacing: 8) {
                statusDot
                VStack(alignment: .leading, spacing: 1) {
                    Text(slot.record.fileName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(originalDateLabel)
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.55))
                        if !pluginFormats.isEmpty {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.3))
                            Text(pluginFormats.joined(separator: " • "))
                                .font(.system(size: 10))
                                .foregroundColor(Color.atlasSubtitle.opacity(0.55))
                        }
                    }
                }
                Spacer()
                stateLabel
            }

            // Installer input + action
            HStack(spacing: 8) {
                installerInputArea
                    .frame(maxWidth: .infinity)
                actionButton
            }

            // Progress bar (only when installing)
            if slot.state.isInstalling {
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: slot.progress)
                        .progressViewStyle(.linear)
                        .tint(Color(hex: "#3ECFB2"))
                        .frame(height: 3)
                    if !slot.progressStep.isEmpty {
                        Text(slot.progressStep)
                            .font(.system(size: 9))
                            .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Status dot

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
    }

    private var statusColor: Color {
        switch slot.state {
        case .waitingForInstaller:    return Color.atlasSubtitle.opacity(0.25)
        case .ready:                  return Color(hex: "#3ECFB2")
        case .unsupportedFormat:      return Color(hex: "#F0A030")
        case .installing:             return Color(hex: "#7090B8")
        case .success:                return Color(hex: "#3ECFB2")
        case .failure:                return Color(hex: "#E05555")
        case .skipped:                return Color.atlasSubtitle.opacity(0.3)
        case .limitReached:           return Color(hex: "#F0A030")
        }
    }

    // MARK: - State label

    @ViewBuilder
    private var stateLabel: some View {
        switch slot.state {
        case .waitingForInstaller:
            Text(L(.queueStatusWaiting))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
        case .ready:
            Text(L(.filterReady))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color(hex: "#3ECFB2"))
        case .unsupportedFormat(let ext):
            Text("Unsupported .\(ext)")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(hex: "#F0A030"))
        case .installing:
            Text(L(.queueStatusInstalling))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(hex: "#7090B8"))
        case .success:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text(L(.queueStatusInstalled))
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(Color(hex: "#3ECFB2"))
        case .failure:
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 9))
                Text(L(.titanStepFailed))
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(Color(hex: "#E05555"))
        case .skipped:
            Text(L(.titanStepSkipped))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color.atlasSubtitle.opacity(0.4))
        case .limitReached:
            Text(L(.stateLimitReached))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Color(hex: "#F0A030"))
        }
    }

    // MARK: - Installer input area

    @ViewBuilder
    private var installerInputArea: some View {
        let isInteractive = !slot.state.isInstalling && !(slot.state == .success)

        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    isDropTargeted
                        ? Color(hex: "#3ECFB2")
                        : (slot.installerURL != nil
                            ? Color(hex: "#3ECFB2").opacity(0.35)
                            : Color.atlasSubtitle.opacity(0.18)),
                    style: StrokeStyle(lineWidth: 1, dash: slot.installerURL == nil ? [4, 3] : [])
                )
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isDropTargeted
                              ? Color(hex: "#3ECFB2").opacity(0.06)
                              : Color.atlasElevated.opacity(0.4))
                )

            if let url = slot.installerURL {
                HStack(spacing: 6) {
                    Image(systemName: installerIcon)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#3ECFB2").opacity(0.8))
                    Text(url.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let type = slot.classifiedType {
                        Text(type.shortLabel)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Color(hex: "#3ECFB2").opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                }
                .padding(.horizontal, 10)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.35))
                    Text(L(.dropInstallerHere))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.4))
                    Text(L(.orLabel))
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.25))
                    Button(L(.chooseFile)) {
                        pickInstaller()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#3ECFB2").opacity(0.8))
                    .buttonStyle(.plain)
                }
            }

            // AppKit drop overlay (invisible, handles drag-and-drop)
            if isInteractive {
                RecoverySlotDropView(
                    isActive: isInteractive,
                    isTargeted: $isDropTargeted,
                    onDrop: onSetInstaller
                )
            }
        }
        .frame(height: 32)
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        switch slot.state {
        case .waitingForInstaller, .unsupportedFormat:
            // Skip button
            Button("Skip") { onSkip() }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                .buttonStyle(.plain)
                .frame(width: 48)

        case .ready:
            let limitOK = !monthlyLimit.isLocked
            Button(L(.installAction)) { if limitOK { onInstall() } }
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(limitOK ? .white : Color.atlasSubtitle.opacity(0.4))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(limitOK ? Color(hex: "#3ECFB2") : Color.atlasElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .buttonStyle(.plain)
                .disabled(!limitOK)
                .frame(width: 64)

        case .installing:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 64, height: 22)

        case .success:
            EmptyView()

        case .failure:
            HStack(spacing: 4) {
                Button(L(.retry)) { onRetry() }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .buttonStyle(.plain)
                Button("Skip") { onSkip() }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.45))
                    .buttonStyle(.plain)
            }
            .frame(width: 80)

        case .skipped, .limitReached:
            EmptyView()
        }
    }

    // MARK: - Helpers

    private var originalDateLabel: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: slot.record.date)
    }

    private var pluginFormats: [String] {
        let pluginExts = Set(["component", "vst3", "vst", "aaxplugin"])
        let formats = slot.record.installedFiles
            .map { URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased() }
            .filter { pluginExts.contains($0) }
            .map { formatDisplayLabel($0) }
        return Array(Set(formats)).sorted()
    }

    private func formatDisplayLabel(_ ext: String) -> String {
        switch ext {
        case "component": return "AU"
        case "vst3":      return "VST3"
        case "vst":       return "VST"
        case "aaxplugin": return "AAX"
        default:          return ext.uppercased()
        }
    }

    private var installerIcon: String {
        guard let type = slot.classifiedType else { return "doc.fill" }
        switch type {
        case .dmg, .iso:            return "opticaldisc"
        case .zip:                  return "archivebox.fill"
        case .app, .interactiveInstaller: return "app.fill"
        case .pkg:                  return "shippingbox.fill"
        case .component, .vst3, .vst, .aax: return "waveform"
        case .kontaktLibrary:       return "pianokeys.inverse"
        case .exe:                  return "doc.fill"
        case .unsupported:          return "doc.fill"
        }
    }

    private func pickInstaller() {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Installer for \(slot.record.fileName)"
        if panel.runModal() == .OK, let url = panel.url {
            onSetInstaller(url)
        }
    }
}

// MARK: - InstallerType display label

private extension InstallerType {
    var shortLabel: String {
        switch self {
        case .dmg:                  return "DMG"
        case .iso:                  return "ISO"
        case .zip:                  return "ZIP"
        case .app:                  return "APP"
        case .interactiveInstaller: return "PKG"
        case .pkg:                  return "PKG"
        case .component:            return "AU"
        case .vst3:                 return "VST3"
        case .vst:                  return "VST"
        case .aax:                  return "AAX"
        case .kontaktLibrary:       return "NKI"
        case .exe:                  return "EXE"
        case .unsupported(let ext): return ext.uppercased()
        }
    }
}

// MARK: - RecoverySlotDropView

/// Lightweight NSViewRepresentable drop target for a single recovery slot.
/// Accepts the same file UTTypes as the main ATLAS drop zone.
struct RecoverySlotDropView: NSViewRepresentable {
    var isActive: Bool
    @Binding var isTargeted: Bool
    var onDrop: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }

    func makeNSView(context: Context) -> SlotDropNSView {
        let view = SlotDropNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: SlotDropNSView, context: Context) {
        context.coordinator.owner   = self
        nsView.coordinator          = context.coordinator
        nsView.isAccepting          = isActive
    }

    class Coordinator: NSObject {
        var owner: RecoverySlotDropView
        init(owner: RecoverySlotDropView) { self.owner = owner }
    }
}

class SlotDropNSView: NSView {
    var coordinator: RecoverySlotDropView.Coordinator?
    var isAccepting: Bool = true

    private let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("public.file-url"),
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("com.apple.disk-image"),
        NSPasteboard.PasteboardType("public.item")
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(acceptedTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(acceptedTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isAccepting else { return [] }
        DispatchQueue.main.async { self.coordinator?.owner.isTargeted = true }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        DispatchQueue.main.async { self.coordinator?.owner.isTargeted = false }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        DispatchQueue.main.async { self.coordinator?.owner.isTargeted = false }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard isAccepting else { return false }
        let pb = sender.draggingPasteboard
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
           let url = urls.first {
            DispatchQueue.main.async { self.coordinator?.owner.onDrop(url) }
            return true
        }
        return false
    }
}
