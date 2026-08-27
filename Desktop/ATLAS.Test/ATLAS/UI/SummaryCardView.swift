import SwiftUI
import AppKit

// MARK: - Shared failure reason formatter

func friendlyReason(_ raw: String) -> String {
    let lower = raw.lowercased()

    func extractVersion() -> String? {
        let patterns = [#"(\d{1,2}\.\d+(?:\.\d+)?)"#, #"(?:osx?|macos)\s*(\d{1,2})"#]
        for pat in patterns {
            if let r = raw.range(of: pat, options: .regularExpression) {
                let match = String(raw[r])
                let num = match.trimmingCharacters(in: .letters).trimmingCharacters(in: .whitespaces)
                if !num.isEmpty { return num }
                if let numRange = match.range(of: #"\d[\d.]+"#, options: .regularExpression) {
                    return String(match[numRange])
                }
            }
        }
        return nil
    }

    let osVersionTriggers = [
        "requires macos", "requires os x", "requires osx",
        "minimum os", "lsminimumsystemversion", "macos version",
        "os version", "not all requirements", "requirements were not met",
        "requires at least", "operating system is too old",
        "operating system must be at least", "refused to install",
        "incompatible with this version", "not compatible with your version",
        "system version", "supported system", "os must be"
    ]
    if osVersionTriggers.contains(where: { lower.contains($0) }) {
        if let ver = extractVersion() {
            return "Installation cannot proceed — this product requires at least macOS \(ver)."
        }
        return "Installation cannot proceed — your macOS version does not meet the minimum requirement. Check the software's system requirements."
    }

    if lower.contains("disk space") || lower.contains("not enough space") ||
       lower.contains("no space left") || lower.contains("insufficient space") {
        return "Installation failed — not enough disk space. Free up storage and try again."
    }

    if lower.contains("permission denied") || lower.contains("not authorized") ||
       lower.contains("authorization") || lower.contains("not permitted") {
        return "Installation failed — ATLAS was denied access. Go to System Settings › Privacy & Security and make sure ATLAS has Full Disk Access."
    }

    if lower.contains("could not mount") || lower.contains("failed to mount") ||
       lower.contains("hdiutil") {
        return "Installation failed — the disk image could not be opened. The file may be damaged or incomplete."
    }

    if lower.contains("architecture") || lower.contains("rosetta") ||
       lower.contains("not supported on this processor") {
        return "Installation failed — this software is not compatible with your Mac's processor. Check if an Apple Silicon version is available."
    }

    if lower.contains("notariz") || lower.contains("codesign") ||
       lower.contains("gatekeeper") || lower.contains("not signed") ||
       lower.contains("unsigned") {
        return "Installation failed — macOS blocked the software. Open System Settings › Privacy & Security and click 'Allow' next to the blocked item."
    }

    if lower.contains("resource busy") || lower.contains("in use") ||
       lower.contains("already running") {
        return "Installation failed — the app is currently open. Quit it and try again."
    }

    if lower.contains("cancel") { return "Installation was cancelled." }

    if lower.contains("pkg installation failed") ||
       (lower.contains("installer") && (lower.contains("failed") || lower.contains("error"))) {
        let lines = raw.components(separatedBy: "\n")
        let useful = lines.first(where: {
            let l = $0.lowercased()
            return l.contains("error") || l.contains("fail") || l.contains("require")
        }) ?? lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        if let line = useful {
            let clean = line.replacingOccurrences(of: "installer: ", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.count > 5 {
                let truncated = clean.count > 180 ? String(clean.prefix(177)) + "…" : clean
                return "Installation failed — \(truncated)"
            }
        }
        return "Installation failed — the package installer returned an error. Check the log for details."
    }

    var clean = raw
        .replacingOccurrences(of: "Error Domain=", with: "")
        .replacingOccurrences(of: "NSLocalizedDescription=", with: "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if clean.count > 200 { clean = String(clean.prefix(197)) + "…" }
    return clean
}

// MARK: - Install summary card

struct InstallSummaryCard: View {
    let record: InstallRecord
    var installerURL: URL? = nil
    var onDone: (() -> Void)? = nil

    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var detailsExpanded  = false  // collapsed by default — user expands when needed
    @State private var installerTrashed = false
    @State private var trashHovered     = false

    // Groups installed files by type for display. Filters out noise (.DS_Store etc).
    private struct FileGroup: Identifiable {
        let id = UUID()
        let label: String
        let icon: String
        let color: String
        let files: [InstallRecord.InstalledFile]
    }

    private var fileGroups: [FileGroup] {
        let meaningful: [String: (label: String, icon: String, color: String)] = [
            "app":       ("Application",  "app.badge.fill",        "#3ECFB2"),
            "vst3":      ("VST3 Plugin",  "puzzlepiece.fill",      "#A78BFA"),
            "vst":       ("VST Plugin",   "puzzlepiece",           "#A78BFA"),
            "component": ("AU Plugin",    "puzzlepiece.extension.fill", "#60A5FA"),
            "aaxplugin": ("AAX Plugin",   "puzzlepiece.fill",      "#F472B6"),
            "framework": ("Framework",    "shippingbox.fill",      "#94A3B8"),
            "pkg":       ("Package",      "shippingbox.fill",      "#94A3B8"),
        ]
        var buckets: [String: [InstallRecord.InstalledFile]] = [:]
        for f in record.installedFiles {
            let ext = URL(fileURLWithPath: f.destinationPath).pathExtension.lowercased()
            if meaningful[ext] != nil { buckets[ext, default: []].append(f) }
        }
        // Add runtime-created paths (Library dirs created at runtime, not in PKG receipt)
        var runtimeFiles: [InstallRecord.InstalledFile] = []
        for path in record.runtimeCreatedPaths ?? [] {
            runtimeFiles.append(.init(sourceName: URL(fileURLWithPath: path).lastPathComponent,
                                      destinationPath: path))
        }

        var groups: [FileGroup] = []
        let order = ["app","vst3","vst","component","aaxplugin","framework","pkg"]
        for ext in order {
            if let files = buckets[ext], !files.isEmpty, let meta = meaningful[ext] {
                groups.append(FileGroup(label: meta.label, icon: meta.icon, color: meta.color, files: files))
            }
        }
        if !runtimeFiles.isEmpty {
            groups.append(FileGroup(label: "Support Files", icon: "folder.fill", color: "#94A3B8", files: runtimeFiles))
        }
        return groups
    }

    private var headlineText: String {
        guard record.status == .success else { return "Installation failed" }
        // Pick the most prominent installed name for the headline
        let apps = record.installedFiles.filter {
            ["app","vst3","vst","component","aaxplugin"].contains(
                URL(fileURLWithPath: $0.destinationPath).pathExtension.lowercased())
        }
        if let first = apps.first {
            let name = URL(fileURLWithPath: first.destinationPath).lastPathComponent
            return apps.count == 1 ? "\(name) installed" : "\(name) + \(apps.count - 1) more installed"
        }
        return "\(record.fileName) installed"
    }

    // MARK: - Instruction-aware checklist

    /// Always-visible summary of what ATLAS completed and what the user still needs to do.
    @ViewBuilder
    private var installationChecklist: some View {
        let docInfo    = record.installerDocInfo
        let userSteps  = docInfo?.steps ?? []
        let keys       = docInfo?.licenseKeys ?? []
        let urls       = docInfo?.activationURLs ?? []
        let hasReceipts = !record.pkgReceiptIDs.isEmpty
        let hasFiles    = !record.installedFiles.isEmpty || totalItems > 0
        let hasUserAction = !userSteps.isEmpty || !keys.isEmpty || !urls.isEmpty

        // Only show the checklist if there's at least one item to display
        if hasReceipts || hasFiles || hasUserAction
            || record.titanVerified == true || record.verificationWarning != nil {

            VStack(alignment: .leading, spacing: 6) {

                // ATLAS-completed steps
                if hasFiles || hasReceipts {
                    ChecklistRow(
                        icon: "checkmark.circle.fill",
                        color: Color(hex: "#2ECC8A"),
                        label: hasFiles
                            ? "\(totalItems) item\(totalItems == 1 ? "" : "s") installed"
                            : "\(record.pkgReceiptIDs.count) package\(record.pkgReceiptIDs.count == 1 ? "" : "s") installed"
                    )
                }

                // Verification
                if record.titanVerified == true {
                    ChecklistRow(
                        icon: "checkmark.shield.fill",
                        color: Color(hex: "#2ECC8A"),
                        label: "Verification passed"
                    )
                } else if let warning = record.verificationWarning {
                    ChecklistRow(
                        icon: "exclamationmark.shield.fill",
                        color: Color(hex: "#F0A030"),
                        label: warning.count > 80
                            ? String(warning.prefix(77)) + "…"
                            : warning
                    )
                }

                // User-action steps from installer docs
                if !userSteps.isEmpty || !keys.isEmpty || !urls.isEmpty {
                    Divider()
                        .background(Color.atlasSeparator)
                        .padding(.vertical, 2)

                    Text(L(.userActionRequired))
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#F0A030").opacity(0.8))
                        .tracking(0.7)

                    ForEach(Array(userSteps.prefix(4).enumerated()), id: \.offset) { _, step in
                        ChecklistRow(
                            icon: "person.fill",
                            color: Color(hex: "#F0A030"),
                            label: step
                        )
                    }

                    if !keys.isEmpty {
                        ChecklistRow(
                            icon: "key.fill",
                            color: Color(hex: "#F0A030"),
                            label: "Enter activation code in the plugin or its manager"
                        )
                    }

                    if !urls.isEmpty {
                        ForEach(urls.prefix(2), id: \.self) { url in
                            ChecklistRow(
                                icon: "arrow.up.right.square",
                                color: Color(hex: "#5B8DEF"),
                                label: url
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    private var totalItems: Int {
        fileGroups.reduce(0) { $0 + $1.files.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Headline ──────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: record.status == .success
                      ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(record.status == .success
                        ? Color(hex: "#2ECC8A") : Color(hex: "#E05555"))
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                    Text(record.shortDate + " · " + record.shortTime)
                        .font(.system(size: 10))
                        .foregroundColor(Color.atlasSubtitle)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Color.atlasSeparator)

            // ── Installation checklist (success only) ─────────────────
            if record.status == .success {
                installationChecklist
            }

            // ── Failure reason ─────────────────────────────────────────
            if record.status == .failure, let reason = record.failureReason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(hex: "#E05555"))
                        .font(.system(size: 11))
                        .padding(.top, 1)
                    Text(friendlyReason(reason))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#E05555").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(hex: "#E05555").opacity(0.25), lineWidth: 0.75))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            // ── Installed files breakdown (success only) ───────────────
            if record.status == .success {
                Button {
                    withAnimation(.atlasSpring) { detailsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.atlasSeparator).frame(height: 1)
                        HStack(spacing: 5) {
                            Text("\(totalItems) item\(totalItems == 1 ? "" : "s") installed")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.atlasTertiary)
                            Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color.atlasTertiary)
                        }
                        .fixedSize()
                        Rectangle().fill(Color.atlasSeparator).frame(height: 1)
                    }
                    .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)

                if detailsExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        if fileGroups.isEmpty {
                            // PKG-only install — no tracked files, show receipt count
                            HStack(spacing: 8) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#94A3B8"))
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(record.fileName)
                                        .font(.system(size: 12))
                                        .foregroundColor(Color.atlasLabel)
                                    if !record.pkgReceiptIDs.isEmpty {
                                        Text("\(record.pkgReceiptIDs.count) package receipt\(record.pkgReceiptIDs.count == 1 ? "" : "s") tracked")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color.atlasSubtitle)
                                    }
                                }
                            }
                        } else {
                            ForEach(fileGroups) { group in
                                VStack(alignment: .leading, spacing: 4) {
                                    // Group label
                                    Text(group.label.uppercased())
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(Color.atlasTertiary)
                                        .padding(.bottom, 1)

                                    ForEach(group.files, id: \.destinationPath) { file in
                                        InstalledFileRow(file: file, icon: group.icon, color: group.color)
                                    }
                                }
                            }
                        }

                        if !record.pkgReceiptIDs.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.badge.checkmark")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.atlasSubtitle)
                                Text("\(record.pkgReceiptIDs.count) package receipt\(record.pkgReceiptIDs.count == 1 ? "" : "s") tracked for uninstall")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.atlasSubtitle)
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // ── Action buttons ────────────────────────────────────────
            Divider().background(Color.atlasSeparator)
            VStack(spacing: 8) {
                if Features.trashInstaller, record.status == .success, let url = installerURL {
                    if installerTrashed {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color.atlasSubtitle)
                            Text(L(.installerMovedToTrash))
                                .font(.system(size: 12))
                                .foregroundColor(Color.atlasSubtitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    } else {
                        Button {
                            NSWorkspace.shared.recycle([url]) { _, _ in
                                DispatchQueue.main.async { installerTrashed = true }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash.fill").font(.system(size: 11))
                                Text(L(.moveInstallerToTrash)).font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(trashHovered ? Color(hex: "#E05555") : Color(hex: "#E05555").opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color(hex: "#E05555").opacity(trashHovered ? 0.15 : 0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(hex: "#E05555").opacity(trashHovered ? 0.4 : 0.2), lineWidth: 0.75))
                            .animation(.atlasHoverIn, value: trashHovered)
                        }
                        .buttonStyle(.plain)
                        .onHover { trashHovered = $0 }
                        .help("Move \(url.lastPathComponent) to Trash")
                    }
                }
                if let onDone {
                    Button(action: onDone) {
                        HStack(spacing: 6) {
                            Image(systemName: "house.fill").font(.system(size: 11))
                            Text(L(.backToHome)).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#08090E"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .background(Color.atlasPanelBG)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(record.status == .success
                ? Color(hex: "#2ECC8A").opacity(0.2)
                : Color(hex: "#E05555").opacity(0.2),
                lineWidth: 0.75))
    }
}

// MARK: - Single installed file row (name + path + reveal button)

private struct InstalledFileRow: View {
    let file: InstallRecord.InstalledFile
    let icon: String
    let color: String
    @State private var hovered = false

    private var fileName: String { URL(fileURLWithPath: file.destinationPath).lastPathComponent }
    private var dirPath: String  { URL(fileURLWithPath: file.destinationPath).deletingLastPathComponent().path }
    private var fileExists: Bool { FileManager.default.fileExists(atPath: file.destinationPath) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: color))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.atlasLabel)
                    .lineLimit(1)
                Text(dirPath)
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if hovered && fileExists {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: file.destinationPath)])
                } label: {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                .transition(.opacity)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hovered ? Color.atlasSeparator.opacity(0.5) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onHover { hovered = $0 }
        .animation(.atlasHoverIn, value: hovered)
    }
}

// MARK: - Checklist row

private struct ChecklistRow: View {
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 14, alignment: .center)
                .padding(.top, 1)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color.atlasLabel)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Uninstall summary card

struct UninstallSummaryCard: View {
    let removedFiles: [String]
    let failedFiles: [String]
    let appName: String
    var onDone: (() -> Void)? = nil
    var onRecover: (() -> Void)? = nil

    @ObservedObject private var langMgr = LanguageManager.shared
    @State private var detailsExpanded  = false  // collapsed by default
    @State private var failuresExpanded = false

    private var succeeded: Bool { failedFiles.isEmpty }

    // Separate meaningful plugin/app files from generic support paths for display
    private var primaryFiles: [String] {
        let exts = ["app","vst3","vst","component","aaxplugin","framework","pkg"]
        return removedFiles.filter { exts.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
    }
    private var supportFiles: [String] {
        let exts = Set(["app","vst3","vst","component","aaxplugin","framework","pkg"])
        return removedFiles.filter { !exts.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
    }

    private var headlineText: String {
        let primaries = primaryFiles
        if primaries.count == 1 {
            return "\(URL(fileURLWithPath: primaries[0]).lastPathComponent) removed\(succeeded ? "" : " (partial)")"
        }
        if !primaries.isEmpty {
            return "\(URL(fileURLWithPath: primaries[0]).lastPathComponent) + \(primaries.count - 1) more removed"
        }
        return succeeded ? "\(appName) uninstalled" : "\(appName) partially uninstalled"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Headline ──────────────────────────────────────────────────
            HStack(spacing: 10) {
                Image(systemName: succeeded ? "trash.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(succeeded ? Color(hex: "#2ECC8A") : Color(hex: "#F0A030"))
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                    if !succeeded {
                        Text("\(failedFiles.count) item\(failedFiles.count == 1 ? "" : "s") could not be removed")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#F0A030"))
                    } else {
                        Text("\(removedFiles.count) file\(removedFiles.count == 1 ? "" : "s") moved to Trash")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Color.atlasSeparator)

            // ── File list ─────────────────────────────────────────────
            Button {
                withAnimation(.atlasSpring) { detailsExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Rectangle().fill(Color.atlasSeparator).frame(height: 1)
                    HStack(spacing: 5) {
                        Text("\(removedFiles.count) item\(removedFiles.count == 1 ? "" : "s") removed")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color.atlasTertiary)
                        Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Color.atlasTertiary)
                    }
                    .fixedSize()
                    Rectangle().fill(Color.atlasSeparator).frame(height: 1)
                }
                .padding(.horizontal, 14)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 6)

            if detailsExpanded {
                VStack(alignment: .leading, spacing: 10) {

                    // Primary files (apps, plugins)
                    if !primaryFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(.removed))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.atlasTertiary)
                                .padding(.bottom, 1)
                            ForEach(primaryFiles, id: \.self) { path in
                                RemovedFileRow(path: path)
                            }
                        }
                    }

                    // Support/Library files
                    if !supportFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(.supportFiles))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.atlasTertiary)
                                .padding(.bottom, 1)
                            ForEach(supportFiles, id: \.self) { path in
                                RemovedFileRow(path: path)
                            }
                        }
                    }

                    // Failed files
                    if !failedFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L(.couldNotRemove))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "#F0A030"))
                                .padding(.bottom, 1)
                            ForEach(failedFiles, id: \.self) { path in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "#F0A030"))
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(URL(fileURLWithPath: path).lastPathComponent)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Color(hex: "#F0A030"))
                                        Text(URL(fileURLWithPath: path).deletingLastPathComponent().path)
                                            .font(.system(size: 10))
                                            .foregroundColor(Color.atlasSubtitle)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                        Text(L(.filesMovedToTrash))
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Action buttons ────────────────────────────────────────
            Divider().background(Color.atlasSeparator)
            VStack(spacing: 8) {
                if let onRecover {
                    Button(action: onRecover) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 11))
                            Text(L(.recover)).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(hex: "#3ECFB2").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(hex: "#3ECFB2").opacity(0.3), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                }
                if let onDone {
                    Button(action: onDone) {
                        HStack(spacing: 6) {
                            Image(systemName: "house.fill").font(.system(size: 11))
                            Text(L(.backToHome)).font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#08090E"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .background(Color.atlasPanelBG)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder((succeeded ? Color(hex: "#2ECC8A") : Color(hex: "#F0A030")).opacity(0.2),
                lineWidth: 0.75))
    }
}

// MARK: - Single removed file row (path + Trash indicator)

private struct RemovedFileRow: View {
    let path: String
    @State private var hovered = false

    private var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
    private var dirPath:  String { URL(fileURLWithPath: path).deletingLastPathComponent().path }

    private func iconFor(_ path: String) -> String {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "app":       return "app.badge.fill"
        case "vst3":      return "puzzlepiece.fill"
        case "vst":       return "puzzlepiece"
        case "component": return "puzzlepiece.extension.fill"
        case "aaxplugin": return "puzzlepiece.fill"
        case "framework": return "shippingbox.fill"
        default:          return "folder.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconFor(path))
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#E05555").opacity(0.7))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(fileName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.atlasLabel)
                    .strikethrough(true, color: Color.atlasSubtitle.opacity(0.6))
                    .lineLimit(1)
                Text(dirPath)
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Image(systemName: "trash.fill")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#E05555").opacity(hovered ? 0.9 : 0.4))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(hovered ? Color.atlasSeparator.opacity(0.4) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onHover { hovered = $0 }
        .animation(.atlasHoverIn, value: hovered)
    }
}
