import Foundation

// MARK: - Models

// Mac-only file extensions
private let macOnlyExtensions: Set<String> = ["dmg", "pkg", "app", "mpkg", "command", "kext", "component"]
// Windows-only file extensions
private let winOnlyExtensions: Set<String> = ["exe", "msi", "bat", "cmd", "ps1"]

func detectFilePlatform(_ fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    if macOnlyExtensions.contains(ext) { return "mac" }
    if winOnlyExtensions.contains(ext)  { return "windows" }
    return "cross-platform"
}

struct SharedFile: Identifiable, Codable {
    let id:           String
    let file_name:    String
    let file_size:    Int64
    let storage_path: String
    let uploaded_at:  String
    let expires_at:   String
    let platform:     String?

    /// True if this file almost certainly won't run on macOS
    var osIncompatible: Bool {
        let p = platform ?? detectFilePlatform(file_name)
        return p == "windows"
    }
    /// User-facing warning when incompatible
    var osWarning: String? {
        guard osIncompatible else { return nil }
        return "⚠ \"\(file_name)\" is a Windows installer and cannot run on macOS."
    }
    /// Badge label shown on the file row
    var platformBadge: String? {
        switch platform ?? detectFilePlatform(file_name) {
        case "windows": return "Windows only"
        case "mac":     return nil  // we're on Mac, no badge needed
        case "cross-platform": return nil
        default: return nil
        }
    }

    var displaySize: String {
        let mb = Double(file_size) / 1_048_576
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.1f MB", mb)
    }
    var uploadDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: uploaded_at) else { return uploaded_at }
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .short
        return fmt.string(from: date)
    }
    var expiryDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = iso.date(from: expires_at) else { return expires_at }
        let fmt = DateFormatter(); fmt.dateStyle = .medium; fmt.timeStyle = .none
        return fmt.string(from: date)
    }
}

// MARK: - Engine

@MainActor
final class FileShareEngine: ObservableObject {
    static let shared = FileShareEngine()

    @Published var sharedFiles:     [SharedFile] = []
    @Published var isUploading      = false
    @Published var uploadProgress:  Double = 0
    @Published var isLoading        = false
    @Published var isDownloading    = false
    @Published var downloadProgress: Double = 0
    @Published var error:            String? = nil

    private let apiBase   = "https://www.interlinked.digital/api/atlas/fileshare"
    private let maxBytes: Int64 = 2 * 1024 * 1024 * 1024 // 2 GB

    // MARK: - Upload

    func upload(url: URL) async -> Bool {
        guard Features.isPro else { return false }
        error = nil

        // Size check
        let attrs  = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size   = (attrs?[.size] as? Int64) ?? 0
        if size > maxBytes {
            let gb = Double(size) / 1_073_741_824
            error = String(format: "File is too large to share (%.2f GB). Maximum is 2 GB.", gb)
            return false
        }

        guard let token = await AuthManager.shared.currentToken() else {
            error = "Not authenticated"; return false
        }

        isUploading = true; uploadProgress = 0
        defer { isUploading = false }

        // 1. Get signed upload URL
        guard let uploadInfo = await getUploadURL(token: token, fileName: url.lastPathComponent, fileSize: size) else {
            return false
        }

        // 2. Upload file directly to Supabase Storage
        guard await uploadToSignedURL(uploadInfo.uploadURL, fileURL: url) else { return false }

        // 3. Confirm to our API
        let platform = detectFilePlatform(url.lastPathComponent)
        guard await confirmUpload(
            token: token,
            fileName: url.lastPathComponent,
            fileSize: size,
            storagePath: uploadInfo.storagePath,
            platform: platform
        ) else { return false }

        await loadFiles()
        return true
    }

    // MARK: - Download + Install

    func downloadAndInstall(file: SharedFile) async -> URL? {
        guard Features.isPro else { return nil }
        error = nil

        guard let token = await AuthManager.shared.currentToken() else {
            error = "Not authenticated"; return nil
        }

        isDownloading = true; downloadProgress = 0
        defer { isDownloading = false }

        // Get signed download URL
        guard let apiURL = URL(string: "\(apiBase)/download-url?file_id=\(file.id)") else { return nil }
        var req = URLRequest(url: apiURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONDecoder().decode([String: String].self, from: data),
              let urlString = json["download_url"],
              let downloadURL = URL(string: urlString) else {
            error = "Could not get download URL"; return nil
        }

        // Download to temp directory
        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLAS-Shared")
            .appendingPathComponent(file.file_name)

        try? FileManager.default.createDirectory(
            at: destURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destURL)

        let delegate = ProgressDelegate { [weak self] progress in
            Task { @MainActor in self?.downloadProgress = progress }
        }
        let session  = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let dlReq    = URLRequest(url: downloadURL)

        do {
            let (tmpURL, _) = try await session.download(for: dlReq)
            try FileManager.default.moveItem(at: tmpURL, to: destURL)
            return destURL
        } catch {
            self.error = "Download failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - List

    func loadFiles() async {
        guard Features.isPro else { return }
        guard let token = await AuthManager.shared.currentToken() else { return }

        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(apiBase)/list") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }

        struct ListResponse: Codable { let files: [SharedFile] }
        if let resp = try? JSONDecoder().decode(ListResponse.self, from: data) {
            sharedFiles = resp.files
        }
    }

    // MARK: - Delete

    func deleteFile(_ file: SharedFile) async {
        guard let token = await AuthManager.shared.currentToken() else { return }
        guard let url = URL(string: "\(apiBase)/delete") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(["file_id": file.id])
        _ = try? await URLSession.shared.data(for: req)
        sharedFiles.removeAll { $0.id == file.id }
    }

    // MARK: - Private helpers

    private struct UploadInfo { let uploadURL: String; let storagePath: String }

    private func getUploadURL(token: String, fileName: String, fileSize: Int64) async -> UploadInfo? {
        guard let url = URL(string: "\(apiBase)/upload-url") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct UploadURLBody: Encodable { let file_name: String; let file_size: Int64 }
        req.httpBody = try? JSONEncoder().encode(UploadURLBody(file_name: fileName, file_size: fileSize))

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            error = "Upload request failed"; return nil
        }

        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 413 {
            if let json = try? JSONDecoder().decode([String: String].self, from: data) {
                error = json["error"] ?? "File too large"
            }
            return nil
        }

        struct Resp: Codable { let upload_url: String; let storage_path: String }
        guard let body = try? JSONDecoder().decode(Resp.self, from: data) else {
            error = "Invalid upload response"; return nil
        }
        return UploadInfo(uploadURL: body.upload_url, storagePath: body.storage_path)
    }

    private func uploadToSignedURL(_ signedURL: String, fileURL: URL) async -> Bool {
        guard let url = URL(string: signedURL) else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let delegate = ProgressDelegate { [weak self] progress in
            Task { @MainActor in self?.uploadProgress = progress }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
            let (_, resp) = try await session.upload(for: req, fromFile: fileURL)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status >= 400 { error = "Upload failed (HTTP \(status))"; return false }
            return true
        } catch {
            self.error = "Upload failed: \(error.localizedDescription)"; return false
        }
    }

    private func confirmUpload(token: String, fileName: String, fileSize: Int64, storagePath: String, platform: String) async -> Bool {
        guard let url = URL(string: "\(apiBase)/confirm") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct ConfirmBody: Encodable { let file_name: String; let file_size: Int64; let storage_path: String; let platform: String }
        req.httpBody = try? JSONEncoder().encode(ConfirmBody(file_name: fileName, file_size: fileSize, storage_path: storagePath, platform: platform))
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}

// MARK: - Progress delegate

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
