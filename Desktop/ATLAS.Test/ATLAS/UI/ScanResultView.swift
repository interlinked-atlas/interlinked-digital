import SwiftUI

struct ScanResultView: View {
    let result: ScanResult
    let onInstall: () -> Void
    let onCancel: () -> Void
    var onShare: (() -> Void)? = nil

    @State private var detailsExpanded = false

    private var hasSecondaryDetails: Bool {
        !result.warnings.isEmpty ||
        result.isQuarantined ||
        result.existingInstall != nil ||
        !result.contentsFound.isEmpty
    }

    private var spaceCritical: Bool {
        result.diskSpaceWarning?.hasPrefix("Not enough") == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Identity row ──────────────────────────────────────────────
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(result.fileURL.lastPathComponent)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(typeLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }
                Spacer()
                categoryBadge
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider().background(Color.atlasSeparator)

            // ── Recommendation ────────────────────────────────────────────
            Text(result.recommendation)
                .font(.system(size: 12))
                .foregroundColor(Color.atlasSubtitle)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, result.diskSpaceWarning != nil ? 8 : 12)

            // ── Critical disk-space warning (always visible) ──────────────
            if let warn = result.diskSpaceWarning {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 12))
                        .foregroundColor(spaceCritical
                            ? Color(hex: "#E05555") : Color(hex: "#F0A030"))
                    Text(warn)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(spaceCritical
                            ? Color(hex: "#E05555") : Color(hex: "#F0A030"))
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((spaceCritical
                    ? Color(hex: "#E05555") : Color(hex: "#F0A030")).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder((spaceCritical
                        ? Color(hex: "#E05555") : Color(hex: "#F0A030")).opacity(0.25),
                        lineWidth: 0.75))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            // ── Collapsible details ───────────────────────────────────────
            if hasSecondaryDetails {
                Button {
                    withAnimation(.atlasSpring) {
                        detailsExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.atlasSeparator)
                            .frame(height: 1)
                        HStack(spacing: 5) {
                            Text(detailsSummaryLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Color.atlasTertiary)
                            Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(Color.atlasTertiary)
                        }
                        .fixedSize()
                        Rectangle()
                            .fill(Color.atlasSeparator)
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                if detailsExpanded {
                    VStack(alignment: .leading, spacing: 10) {

                        if let existing = result.existingInstall {
                            existingInstallRow(existing)
                        }

                        if result.isQuarantined {
                            noticeRow(
                                icon: "lock.shield",
                                color: Color(hex: "#3ECFB2"),
                                text: "Quarantine flag detected — ATLAS will clear it automatically before installing."
                            )
                        }

                        if !result.warnings.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(result.warnings, id: \.self) { w in
                                    noticeRow(
                                        icon: "exclamationmark.triangle.fill",
                                        color: Color(hex: "#F0A030"),
                                        text: w
                                    )
                                }
                            }
                        }

                        if !result.contentsFound.isEmpty {
                            contentsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            // ── Action buttons ────────────────────────────────────────────
            Divider()
                .background(Color.atlasSeparator)
                .padding(.top, hasSecondaryDetails ? 10 : 0)

            HStack(spacing: 10) {
                Button("Cancel") { onCancel() }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.atlasDeepBG)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75))
                    .buttonStyle(.plain)

                if let onShare {
                    Button(action: onShare) {
                        HStack(spacing: 5) {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 10))
                            Text("Share")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Color(hex: "#3ECFB2").opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color(hex: "#3ECFB2").opacity(0.25), lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if result.canInstall {
                    Button {
                        if !spaceCritical { onInstall() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: spaceCritical
                                  ? "externaldrive.badge.exclamationmark"
                                  : "arrow.down.circle.fill")
                                .font(.system(size: 11))
                            Text(spaceCritical ? "Insufficient Space" : "Install")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(spaceCritical
                            ? Color(hex: "#E05555") : Color(hex: "#08090E"))
                        .padding(.horizontal, 18).padding(.vertical, 8)
                        .background(spaceCritical
                            ? Color(hex: "#E05555").opacity(0.15)
                            : Color(hex: "#3ECFB2"))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(spaceCritical
                                    ? Color(hex: "#E05555").opacity(0.4)
                                    : Color.clear, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .disabled(spaceCritical)
                } else {
                    Text("Cannot install automatically")
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .background(Color.atlasPanelBG)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75))
    }

    // MARK: - Sub-views

    private var categoryBadge: some View {
        let cat = result.category
        return HStack(spacing: 4) {
            Image(systemName: cat.icon)
                .font(.system(size: 9, weight: .semibold))
            Text(cat.rawValue)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(cat.color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(cat.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(cat.color.opacity(0.3), lineWidth: 0.75))
    }

    private func noticeRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(color.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(color.opacity(0.2), lineWidth: 0.75))
    }

    private func existingInstallRow(_ existing: ExistingInstall) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(Color(hex: "#F0A030"))
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Already installed")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F0A030"))
                    if let ver = existing.version {
                        Text("v\(ver)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(hex: "#F0A030").opacity(0.85))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: "#F0A030").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(existing.path)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#C8A060"))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("Will reinstall")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#F0A030").opacity(0.6))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#F0A030").opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color(hex: "#F0A030").opacity(0.25), lineWidth: 0.75))
    }

    // MARK: - Contents section

    @State private var showAllContents = false
    private let contentsCap = 5

    private var contentsSection: some View {
        let total   = result.contentsFound.count
        let visible = showAllContents
            ? result.contentsFound
            : Array(result.contentsFound.prefix(contentsCap))

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Contents found")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.atlasSubtitle)
                Spacer()
                Text("\(total) item\(total == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasTertiary)
            }
            .padding(.bottom, 2)

            ForEach(visible) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.type.icon)
                        .foregroundColor(iconColor(item.type))
                        .font(.system(size: 12))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.system(size: 12))
                            .foregroundColor(Color.atlasLabel)
                            .lineLimit(1)
                        Text(item.type.label)
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }

                    Spacer()

                    if let arch = item.arch {
                        Text(arch)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(archColor(arch))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(archColor(arch).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if let minOS = item.minOSVersion {
                        let compat = isOSCompatible(minOS)
                        Text("macOS \(minOS)+")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(compat
                                ? Color.atlasSubtitle : Color(hex: "#E05555"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(compat
                                ? Color.atlasElevated : Color(hex: "#E05555").opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if !item.size.isEmpty {
                        Text(item.size)
                            .font(.system(size: 10))
                            .foregroundColor(Color.atlasSubtitle)
                    }
                }
                .padding(.vertical, 5)

                if item.id != visible.last?.id {
                    Rectangle()
                        .fill(Color.atlasSeparator)
                        .frame(height: 1)
                }
            }

            if total > contentsCap {
                Rectangle().fill(Color.atlasSeparator).frame(height: 1)

                Button {
                    withAnimation(.atlasSnap) {
                        showAllContents.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showAllContents ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(showAllContents
                             ? "Show less"
                             : "Show all \(total) items")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "#3ECFB2"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.atlasDeepBG)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75))
    }

    // MARK: - Details summary label

    private var detailsSummaryLabel: String {
        var parts: [String] = []
        if !result.contentsFound.isEmpty {
            let n = result.contentsFound.count
            parts.append("\(n) item\(n == 1 ? "" : "s") inside")
        }
        if result.existingInstall != nil { parts.append("already installed") }
        if result.isQuarantined          { parts.append("quarantined") }
        if !result.warnings.isEmpty {
            let n = result.warnings.count
            parts.append("\(n) warning\(n == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func archColor(_ arch: String) -> Color {
        switch arch {
        case "Universal":     return Color(hex: "#3ECFB2")
        case "Apple Silicon": return Color(hex: "#3B82F6")
        default:              return Color(hex: "#F0A030")
        }
    }

    private func iconColor(_ type: FoundItemType) -> Color {
        switch type {
        case .app:                          return Color(hex: "#3B82F6")
        case .pkg:                          return Color(hex: "#F0A030")
        case .component, .vst3, .vst, .aax: return Color(hex: "#7C3AED")
        case .script:                       return Color(hex: "#E05555")
        default:                            return Color.atlasSubtitle
        }
    }

    private func isOSCompatible(_ minOS: String) -> Bool {
        let current = ProcessInfo.processInfo.operatingSystemVersion
        let parts = minOS.split(separator: ".").compactMap { Int($0) }
        guard let major = parts.first else { return true }
        let minor = parts.count > 1 ? parts[1] : 0
        return current.majorVersion > major ||
            (current.majorVersion == major && current.minorVersion >= minor)
    }

    private var typeLabel: String {
        switch result.installerType {
        case .dmg:                  return "Disk Image"
        case .iso:                  return "ISO Disc Image"
        case .zip:                  return "ZIP Archive"
        case .app:                  return "Application Bundle"
        case .pkg:                  return "Package Installer"
        case .component:            return "Audio Unit"
        case .vst3:                 return "VST3 Plugin"
        case .vst:                  return "VST Plugin"
        case .aax:                  return "AAX Plugin"
        case .kontaktLibrary:       return "Kontakt Library"
        case .exe:                  return "Windows EXE (Wine)"
        case .unsupported(let e):   return "Unsupported (.\(e))"
        }
    }
}
