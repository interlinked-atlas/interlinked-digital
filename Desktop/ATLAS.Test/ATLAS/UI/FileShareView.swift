import SwiftUI

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
                Text(file.file_name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("\(file.displaySize) · expires \(file.expiryDate)")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#525260"))
            }

            Spacer()

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
