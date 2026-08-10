import SwiftUI

// MARK: - Device Picker Sheet

struct DevicePickerView: View {
    @ObservedObject private var engine = FileShareEngine.shared
    @ObservedObject private var auth   = AuthManager.shared
    let fileURL: URL
    let arch: String?
    let onDone: () -> Void

    @State private var selectedDevice: ATLASDevice? = nil
    @State private var isSending = false

    private var otherDevices: [ATLASDevice] {
        let myUUID = atlasHardwareUUID()
        return auth.devices.filter { $0.hardwareUUID != myUUID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share to Device")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#525260"))
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onDone) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#525260"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.06))

            if otherDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "#525260"))
                    Text("No other devices found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#525260"))
                    Text("Sign into ATLAS with this account on another Mac to see it here.")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#44444E"))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                VStack(spacing: 6) {
                    ForEach(otherDevices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: selectedDevice?.id == device.id,
                            onTap: { selectedDevice = device }
                        )
                    }
                }
                .padding(12)
            }

            if let err = engine.error {
                Divider().background(Color.white.opacity(0.06))
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#EF5B5B"))
                    Text(err).font(.system(size: 11)).foregroundColor(Color(hex: "#EF5B5B")).lineLimit(2)
                    Spacer()
                    Button("✕") { engine.error = nil }.buttonStyle(.plain)
                        .foregroundColor(Color(hex: "#525260")).font(.system(size: 11))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }

            if !otherDevices.isEmpty {
                Divider().background(Color.white.opacity(0.06))

                // Upload progress bar (shown while sending)
                if isSending {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "icloud.and.arrow.up")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                            Text("Sending to \(selectedDevice?.deviceName ?? "device")…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(Int(engine.uploadProgress * 100))%")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .frame(width: 36, alignment: .trailing)
                        }
                        ProgressView(value: engine.uploadProgress)
                            .progressViewStyle(.linear)
                            .tint(Color(hex: "#3ECFB2"))
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                } else {
                    HStack(spacing: 10) {
                        Button(action: onDone) {
                            Text("Cancel")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: "#525260"))
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(Color.white.opacity(0.04))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: sendFile) {
                            Text("Send")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#0A0A0C"))
                                .padding(.horizontal, 20).padding(.vertical, 8)
                                .background(selectedDevice != nil ? Color(hex: "#3ECFB2") : Color(hex: "#3ECFB2").opacity(0.35))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedDevice == nil)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
        }
        .background(Color(hex: "#0E0E10"))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .frame(width: 320)
        .task { await auth.fetchDevices() }
    }

    private func sendFile() {
        guard let device = selectedDevice else { return }
        isSending = true
        Task {
            let ok = await engine.upload(url: fileURL, targetDevice: device, arch: arch)
            isSending = false
            if ok { onDone() }
        }
    }
}

// MARK: - Device Row

private struct DeviceRow: View {
    let device:     ATLASDevice
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? Color(hex: "#3ECFB2") : Color(hex: "#525260"))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.deviceName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                    Text("Last seen \(String(device.lastSeen.prefix(10)))")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#525260"))
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(isSelected ? Color(hex: "#3ECFB2").opacity(0.07) : Color.white.opacity(0.02))
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? Color(hex: "#3ECFB2").opacity(0.25) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FileShare List View

struct FileShareView: View {
    @ObservedObject private var engine = FileShareEngine.shared
    let onInstall: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shared Files")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("Available on all your devices · expires after 7 days")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#525260"))
                }
                Spacer()
                Button(action: { Task { await engine.loadFiles() } }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#525260"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color.white.opacity(0.06))

            if engine.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading…").font(.system(size: 12)).foregroundColor(Color(hex: "#525260"))
                }
                .padding(20)
            } else if engine.sharedFiles.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 22))
                        .foregroundColor(Color(hex: "#525260"))
                    Text("No shared files")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#525260"))
                    Text("Share an installer after scanning to access it on other devices")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#44444E"))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(engine.sharedFiles) { file in
                            FileShareRow(file: file, onInstall: {
                                Task {
                                    if let url = await engine.downloadAndInstall(file: file) {
                                        onInstall(url)
                                    }
                                }
                            }, onDelete: {
                                Task { await engine.deleteFile(file) }
                            })
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 260)
            }

            // Download progress
            if engine.isDownloading {
                VStack(spacing: 6) {
                    Divider().background(Color.white.opacity(0.06))
                    HStack(spacing: 10) {
                        ProgressView(value: engine.downloadProgress)
                            .progressViewStyle(.linear)
                            .tint(Color(hex: "#3ECFB2"))
                        Text("\(Int(engine.downloadProgress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .frame(width: 32)
                    }
                    .padding(.horizontal, 16)
                    Text("Downloading…")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#525260"))
                }
                .padding(.bottom, 10)
            }

            // Error
            if let err = engine.error {
                Divider().background(Color.white.opacity(0.06))
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#EF5B5B"))
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#EF5B5B"))
                        .lineLimit(2)
                    Spacer()
                    Button("✕") { engine.error = nil }
                        .buttonStyle(.plain)
                        .foregroundColor(Color(hex: "#525260"))
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color(hex: "#0E0E10"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
        .task { await engine.loadFiles() }
    }
}

// MARK: - Row

struct FileShareRow: View {
    let file:      SharedFile
    let onInstall: () -> Void
    let onDelete:  () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: "#3ECFB2"))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(file.file_name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor((file.osIncompatible || file.archIncompatible) ? Color(hex: "#888890") : .white)
                        .lineLimit(1)
                    if let badge = file.platformBadge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#EF5B5B"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#EF5B5B").opacity(0.12))
                            .cornerRadius(4)
                    }
                    if let archW = file.archWarning {
                        Text(archW)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0A030"))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#F0A030").opacity(0.12))
                            .cornerRadius(4)
                    }
                }
                if let warning = file.osWarning {
                    Text(warning)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#EF5B5B"))
                        .lineLimit(2)
                } else {
                    Text("\(file.displaySize) · expires \(file.expiryDate)")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#525260"))
                }
            }

            Spacer()

            if file.osIncompatible || file.archIncompatible {
                Text(file.osIncompatible ? "Incompatible" : "Won't Run")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#EF5B5B").opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: "#EF5B5B").opacity(0.08))
                    .cornerRadius(7)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: "#EF5B5B").opacity(0.18), lineWidth: 1))
            } else {
                Button(action: onInstall) {
                    Text("Install")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "#3ECFB2").opacity(0.10))
                        .cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: "#3ECFB2").opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#525260"))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.02))
        .cornerRadius(9)
    }

    private var iconName: String {
        let ext = file.file_name.split(separator: ".").last?.lowercased() ?? ""
        switch ext {
        case "exe", "msi": return "app.badge"
        case "zip", "rar", "7z": return "archivebox"
        case "pkg", "dmg": return "shippingbox"
        default: return "doc"
        }
    }
}

// MARK: - Upload progress overlay (shown during upload)

struct FileShareUploadOverlay: View {
    @ObservedObject private var engine = FileShareEngine.shared

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                Text("Sharing to your devices…")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            ProgressView(value: engine.uploadProgress)
                .progressViewStyle(.linear)
                .tint(Color(hex: "#3ECFB2"))
            Text("\(Int(engine.uploadProgress * 100))%")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#525260"))
        }
        .padding(16)
        .background(Color(hex: "#111113"))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "#3ECFB2").opacity(0.2), lineWidth: 1))
        .padding(.horizontal, 20)
    }
}
