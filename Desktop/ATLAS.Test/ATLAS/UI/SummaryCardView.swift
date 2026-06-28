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

    @State private var detailsExpanded   = false
    @State private var installerTrashed  = false
    @State private var trashHovered      = false

    private var installedNames: [String] {
        var names = Set<String>()
        let meaningful = ["app", "vst3", "vst", "component", "aaxplugin", "pkg", "framework"]
        for file in record.installedFiles {
            let url = URL(fileURLWithPath: file.destinationPath)
            if meaningful.contains(url.pathExtension.lowercased()) {
                names.insert(url.lastPathComponent)
            }
        }
        if names.isEmpty { names.insert(record.fileName) }
        return Array(names).sorted()
    }

    private var headlineText: String {
        guard record.status == .success else { return "Installation failed" }
        let names = installedNames
        if names.count == 1 { return "\(names[0]) installed" }
        return "\(names[0]) + \(names.count - 1) more installed"
    }

    private var detailsSummary: String {
        var parts: [String] = []
        let n = installedNames.count
        if n > 0 { parts.append("\(n) item\(n == 1 ? "" : "s")") }
        if !record.pkgReceiptIDs.isEmpty {
            let r = record.pkgReceiptIDs.count
            parts.append("\(r) receipt\(r == 1 ? "" : "s") tracked")
        } else if !record.installedFiles.isEmpty {
            let f = record.installedFiles.count
            parts.append("\(f) file\(f == 1 ? "" : "s") tracked")
        }
        return parts.joined(separator: " · ")
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

            // ── Failure reason (always visible on failure) ─────────────
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

            // ── Collapsible details (success only) ────────────────────
            if record.status == .success {
                Button {
                    withAnimation(.atlasSpring) { detailsExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Rectangle().fill(Color.atlasSeparator).frame(height: 1)
                        HStack(spacing: 5) {
                            Text(detailsSummary)
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
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(installedNames, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: iconFor(name))
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#3ECFB2"))
                                    .frame(width: 16)
                                Text(name)
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.atlasLabel)
                            }
                        }

                        if !record.pkgReceiptIDs.isEmpty {
                            let r = record.pkgReceiptIDs.count
                            Text("\(r) package receipt\(r == 1 ? "" : "s") tracked for uninstall")
                                .font(.system(size: 10))
                                .foregroundColor(Color.atlasSubtitle)
                        } else if !record.installedFiles.isEmpty {
                            let f = record.installedFiles.count
                            Text("\(f) file\(f == 1 ? "" : "s") tracked for uninstall")
                                .font(.system(size: 10))
                                .foregroundColor(Color.atlasSubtitle)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
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
                            Text("Installer moved to Trash")
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
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 11))
                                Text("Move Installer to Trash")
                                    .font(.system(size: 12, weight: .semibold))
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
                            Image(systemName: "house.fill")
                                .font(.system(size: 11))
                            Text("Back to Home")
                                .font(.system(size: 12, weight: .semibold))
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

    private func iconFor(_ name: String) -> String {
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        switch ext {
        case "app":        return "app.badge.fill"
        case "vst3":       return "puzzlepiece.fill"
        case "vst":        return "puzzlepiece"
        case "component":  return "puzzlepiece"
        case "aaxplugin":  return "puzzlepiece.fill"
        case "pkg":        return "shippingbox.fill"
        default:           return "doc.fill"
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

    @State private var detailsExpanded = false

    private var succeeded: Bool { failedFiles.isEmpty }

    private var cleanedNames: [String] {
        var names = Set<String>()
        let meaningful = ["app", "vst3", "vst", "component", "aaxplugin", "pkg", "framework"]
        for path in removedFiles {
            let url = URL(fileURLWithPath: path)
            if meaningful.contains(url.pathExtension.lowercased()) {
                names.insert(url.lastPathComponent)
            }
        }
        if names.isEmpty && !removedFiles.isEmpty { names.insert(appName) }
        return Array(names).sorted()
    }

    private var headlineText: String {
        if cleanedNames.count == 1 {
            return "\(cleanedNames[0]) removed\(succeeded ? "" : " (partial)")"
        }
        return succeeded ? "\(appName) uninstalled" : "\(appName) partially uninstalled"
    }

    private var detailsSummary: String {
        var parts = ["\(removedFiles.count) file\(removedFiles.count == 1 ? "" : "s") removed"]
        if !failedFiles.isEmpty { parts.append("\(failedFiles.count) failed") }
        return parts.joined(separator: " · ")
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
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Color.atlasSeparator)

            // ── Collapsible details ───────────────────────────────────
            Button {
                withAnimation(.atlasSpring) { detailsExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Rectangle().fill(Color.atlasSeparator).frame(height: 1)
                    HStack(spacing: 5) {
                        Text(detailsSummary)
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
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(cleanedNames, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#E05555"))
                                .frame(width: 16)
                            Text(name)
                                .font(.system(size: 12))
                                .foregroundColor(Color.atlasLabel)
                                .strikethrough(true, color: Color.atlasSubtitle)
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                        Text("Files moved to Trash — empty Trash in Finder to free space.")
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Action buttons ────────────────────────────────────────
            Divider().background(Color.atlasSeparator)

            VStack(spacing: 8) {
                if let onRecover {
                    Button(action: onRecover) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 11))
                            Text("Recover")
                                .font(.system(size: 12, weight: .semibold))
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
                            Image(systemName: "house.fill")
                                .font(.system(size: 11))
                            Text("Back to Home")
                                .font(.system(size: 12, weight: .semibold))
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
