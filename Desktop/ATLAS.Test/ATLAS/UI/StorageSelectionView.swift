import SwiftUI
import AppKit

struct StorageSelectionView: View {
    let installerName: String
    let estimatedBytes: Int64
    let onSelect: (StorageVolume, URL) -> Void
    let onCancel: () -> Void

    @State private var volumes: [StorageVolume] = []
    @State private var selected: StorageVolume? = nil
    @State private var customURL: URL? = nil
    @State private var customName: String? = nil
    @State private var validation: StorageValidation? = nil
    @State private var continueHovered = false
    @State private var cancelHovered   = false

    private var effectiveDestination: URL? {
        customURL ?? selected?.url
    }

    private var effectiveName: String? {
        customName ?? selected?.displayName
    }

    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "#0E1326").opacity(0.97), location: 0),
                    .init(color: Color(hex: "#090C1B").opacity(0.99), location: 1),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "externaldrive.connected.to.line.below.fill")
                            .font(.system(size: 22))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Choose Installation Storage")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(hex: "#F0F2FF"))
                            Text("Select where ATLAS should install \(installerName)")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#696E7C"))
                        }
                        Spacer()
                        // TITAN CORE™ badge
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: "#3ECFB2"))
                                .frame(width: 5, height: 5)
                            Text("TITAN CORE™")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1)
                                .foregroundColor(Color(hex: "#3ECFB2"))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color(hex: "#3ECFB2").opacity(0.08))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: "#3ECFB2").opacity(0.2), lineWidth: 1))
                    }

                    // Install size info
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#F0A030"))
                        Text("Large installation detected — estimated size: \(StorageVolume.format(estimatedBytes))")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#F0A030"))
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(hex: "#F0A030").opacity(0.07))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(hex: "#F0A030").opacity(0.2), lineWidth: 1))
                }
                .padding(20)

                Divider().background(Color(hex: "#1E2132"))

                // Volume list
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(volumes) { vol in
                            volumeRow(vol)
                        }

                        // Custom folder option
                        customFolderRow
                    }
                    .padding(16)
                }

                Divider().background(Color(hex: "#1E2132"))

                // Selected path display
                if let dest = effectiveDestination {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .font(.system(size: 11))
                        Text(dest.path)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#696E7C"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Validation warning
                if let val = validation, !val.isValid || !val.message.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: val.isValid ? "exclamationmark.triangle" : "xmark.circle.fill")
                            .foregroundColor(val.isValid ? Color(hex: "#F0A030") : Color(hex: "#E05555"))
                            .font(.system(size: 11))
                        Text(val.message)
                            .font(.system(size: 11))
                            .foregroundColor(val.isValid ? Color(hex: "#F0A030") : Color(hex: "#E05555"))
                    }
                    .padding(.horizontal, 20).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Bottom buttons
                HStack(spacing: 10) {
                    Button("Cancel") { onCancel() }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(cancelHovered ? Color(hex: "#F0F2FF") : Color(hex: "#696E7C"))
                        .padding(.horizontal, 20).padding(.vertical, 9)
                        .background(cancelHovered ? Color(hex: "#141A30") : Color(hex: "#08091A"))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#1E2132"), lineWidth: 1))
                        .buttonStyle(.plain)
                        .scaleEffect(cancelHovered ? 1.02 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: cancelHovered)
                        .onHover { cancelHovered = $0 }

                    Spacer()

                    let canContinue = effectiveDestination != nil && (validation?.isValid ?? true)
                    Button {
                        guard canContinue,
                              let vol = selected ?? volumes.first,
                              let dest = effectiveDestination else { return }
                        let finalVol = customURL != nil
                            ? StorageVolume(
                                name: customName ?? dest.lastPathComponent,
                                url: dest, isInternal: false, isExternal: true, isBoot: false,
                                availableBytes: vol.availableBytes, totalBytes: vol.totalBytes)
                            : vol
                        onSelect(finalVol, dest)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Install Here")
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(canContinue ? Color(hex: "#08090E") : Color(hex: "#696E7C"))
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(canContinue ? Color(hex: "#3ECFB2") : Color(hex: "#141A30"))
                        .cornerRadius(9)
                        .overlay(RoundedRectangle(cornerRadius: 9)
                            .stroke(canContinue ? Color.clear : Color(hex: "#2E3350"), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                    .scaleEffect(canContinue && continueHovered ? 1.02 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.75), value: continueHovered)
                    .onHover { continueHovered = $0 }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 500, idealWidth: 520, minHeight: 460)
        .onAppear {
            volumes = StorageManager.shared.availableVolumes()
            // Pre-select the boot volume (internal)
            selected = volumes.first(where: { $0.isBoot }) ?? volumes.first
            validateSelected()
        }
    }

    // MARK: - Volume row

    @ViewBuilder
    private func volumeRow(_ vol: StorageVolume) -> some View {
        let isSelected = selected?.id == vol.id && customURL == nil
        Button {
            selected  = vol
            customURL = nil
            customName = nil
            validateSelected()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: vol.icon)
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color(hex: "#3ECFB2") : Color(hex: "#696E7C"))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(vol.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0F2FF"))
                        if vol.isExternal {
                            Text("EXTERNAL")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color(hex: "#3ECFB2").opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("\(vol.availableFormatted) available")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#696E7C"))
                        Text("·")
                            .foregroundColor(Color(hex: "#3D4470"))
                        Text(vol.url.path)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#3D4470"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Capacity bar
                VStack(alignment: .trailing, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: "#141A30"))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(vol.usedPercent > 0.85
                                      ? Color(hex: "#E05555")
                                      : Color(hex: "#3ECFB2"))
                                .frame(width: geo.size.width * vol.usedPercent)
                        }
                    }
                    .frame(width: 60, height: 4)

                    Text("\(vol.totalFormatted) total")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#3D4470"))
                }
            }
            .padding(12)
            .background(isSelected
                        ? Color(hex: "#3ECFB2").opacity(0.06)
                        : Color(hex: "#0A0D1C"))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected
                        ? Color(hex: "#3ECFB2").opacity(0.4)
                        : Color(hex: "#1E2132"), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom folder row

    @ViewBuilder
    private var customFolderRow: some View {
        let isSelected = customURL != nil
        Button {
            let panel = NSOpenPanel()
            panel.title          = "Choose Installation Folder"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Choose"
            if panel.runModal() == .OK, let url = panel.url {
                customURL  = url
                customName = url.lastPathComponent
                selected   = nil
                validateCustom(url: url)
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color(hex: "#3ECFB2") : Color(hex: "#696E7C"))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text(customName ?? "Choose Custom Folder…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? Color(hex: "#F0F2FF") : Color(hex: "#696E7C"))
                    if let url = customURL {
                        Text(url.path)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#3D4470"))
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Browse to any folder on any connected volume")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#3D4470"))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#3D4470"))
            }
            .padding(12)
            .background(isSelected ? Color(hex: "#3ECFB2").opacity(0.06) : Color(hex: "#0A0D1C"))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(hex: "#3ECFB2").opacity(0.4) : Color(hex: "#1E2132"),
                        lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Validation

    private func validateSelected() {
        guard let vol = selected else { validation = nil; return }
        validation = StorageManager.shared.validate(vol, neededBytes: estimatedBytes)
    }

    private func validateCustom(url: URL) {
        let attrs = (try? FileManager.default.attributesOfFileSystem(forPath: url.path))
        let free  = (attrs?[.systemFreeSize] as? Int64) ?? 0
        let total = (attrs?[.systemSize] as? Int64) ?? 0
        let vol   = StorageVolume(name: url.lastPathComponent, url: url,
                                  isInternal: false, isExternal: true, isBoot: false,
                                  availableBytes: free, totalBytes: total)
        validation = StorageManager.shared.validate(vol, neededBytes: estimatedBytes)
    }
}
