import Foundation

// MARK: - Models

private let macOnlyExtensions:  Set<String> = ["dmg", "pkg", "app", "mpkg", "command", "kext", "component"]
private let winOnlyExtensions:  Set<String> = ["exe", "msi", "bat", "cmd", "ps1"]

func detectFilePlatform(_ fileName: String) -> String {
    let ext = (fileName as NSString).pathExtension.lowercased()
    if macOnlyExtensions.contains(ext) { return "mac" }
    if winOnlyExtensions.contains(ext)  { return "windows" }
    return "cross-platform"
}

struct SharedFile: Identifiable, Codable {
    let id:               String
    let file_name:        String
    let file_size:        Int64
    let storage_path:     String
    let uploaded_at:      String
    let expires_at:       String
    let platform:         String?
    let target_device_id: String?
    let arch:             String?   // "Universal", "Apple Silicon", "Intel", nil

    var osIncompatible: Bool {
        let p = platform ?? detectFilePlatform(file_name)
        return p == "windows"
    }
    var archIncompatible: Bool {
        guard let a = arch else { return false }
        // Apple Silicon-only file on an Intel Mac
        if a == "Apple Silicon" && !RosettaEngine.isAppleSilicon { return true }
        return false
    }
    var osWarning: String? {
        if osIncompatible { return "⚠ \"\(file_name)\" is a Windows installer and cannot run on macOS." }
        if archIncompatible { return "⚠ Apple Silicon only — this Mac cannot run this installer." }
        return nil
    }
    var archWarning: String? {
        guard let a = arch, !osIncompatible else { return nil }
        if a == "Apple Silicon" && !RosettaEngine.isAppleSilicon {
            return "Apple Silicon only"
        }
        if a == "Intel" && RosettaEngine.isAppleSilicon {
            return "Intel (Rosetta required)"
        }
        return nil
    }
    var platformBadge: String? {
        switch platform ?? detectFilePlatform(file_name) {
        case "windows": return "Windows only"
        default:        return nil
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

    @Published var sharedFiles:      [SharedFile] = []
    @Published var isUploading       = false
    @Published var uploadProgress:   Double = 0
    @Published var isLoading         = false
    @Published var isDownloading     = false
    @Published var downloadProgress: Double = 0
    @Published var error:            String? = nil

    // Device picker state
    @Published var showDevicePicker  = false
    @Published var pendingUploadURL: URL? = nil
    var pendingArch: String? = nil

    private let apiBase   = "https://www.interlinked.digital/api/atlas/fileshare"
    private let maxBytes: Int64 = 50 * 1024 * 1024 // 50 MB — matches Supabase free tier limit
    private var knownFileIDs: Set<String> = []

    // MARK: - Trigger device picker (called from Share button)

    func initiateShare(url: URL, arch: String? = nil) {
        guard Features.isPro else { error = "File Sharing is a Pro feature."; return }
        pendingUploadURL = url
        pendingArch = arch
        showDevicePicker = true
    }

    // MARK: - Upload (called after device is selected)

    func upload(url: URL, targetDevice: ATLASDevice?, arch: String? = nil) async -> Bool {
        guard Features.isPro else { return false }
        error = nil

        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size  = (attrs?[.size] as? Int64) ?? 0
        if size > maxBytes {
            let mb = Double(size) / 1_048_576
            error = String(format: "File too large (%.1f MB). FileShare currently supports files up to 50 MB.", mb)
            return false
        }

        guard let token = await AuthManager.shared.currentToken() else {
            error = "Not authenticated"; return false
        }

        isUploading = true; uploadProgress = 0
        defer { isUploading = false }

        guard let uploadInfo = await getUploadURL(token: token, fileName: url.lastPathComponent, fileSize: size) else {
            return false
        }

        guard await uploadToSignedURL(uploadInfo.uploadURL, fileURL: url) else { return false }

        let platform = detectFilePlatform(url.lastPathComponent)
        guard await confirmUpload(
            token: token,
            fileName: url.lastPathComponent,
            fileSize: size,
            storagePath: uploadInfo.storagePath,
            platform: platform,
            targetDeviceID: targetDevice?.hardwareUUID,
            arch: arch
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

        guard let apiURL = URL(string: "\(apiBase)/download-url?file_id=\(file.id)") else { return nil }
        var req = URLRequest(url: apiURL)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONDecoder().decode([String: String].self, from: data),
              let urlString = json["download_url"],
              let downloadURL = URL(string: urlString) else {
            error = "Could not get download URL"; return nil
        }

        let destURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLAS-Shared")
            .appendingPathComponent(file.file_name)

        try? FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destURL)

        let delegate = DownloadDelegate { [weak self] progress in
            Task { @MainActor in self?.downloadProgress = progress }
        }
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        do {
            let (tmpURL, _) = try await session.download(for: URLRequest(url: downloadURL))
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

        let deviceID = atlasHardwareUUID()
        guard let url = URL(string: "\(apiBase)/list?device_id=\(deviceID)") else { return }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return }

        struct ListResponse: Codable { let files: [SharedFile] }
        if let resp = try? JSONDecoder().decode(ListResponse.self, from: data) {
            // Notify for files that just arrived (skip on first load when knownFileIDs is empty)
            if !knownFileIDs.isEmpty {
                for file in resp.files where !knownFileIDs.contains(file.id) {
                    let size = file.displaySize
                    ATLASNotification.send(
                        title: "📦 New File Shared",
                        body: "\(file.file_name) (\(size)) is ready to install."
                    )
                }
            }
            knownFileIDs = Set(resp.files.map(\.id))
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
        struct Body: Encodable { let file_name: String; let file_size: Int64 }
        req.httpBody = try? JSONEncoder().encode(Body(file_name: fileName, file_size: fileSize))

        guard let (data, resp) = try? await URLSession.shared.data(for: req) else {
            error = "Upload request failed"; return nil
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 413 {
            error = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "File too large"
            return nil
        }
        if status >= 400 {
            error = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Upload request failed (HTTP \(status))"
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
        // Do NOT set Content-Length or x-upsert — Supabase signed upload URLs handle auth
        // via the token in the URL; extra headers cause 400.

        // Use uploadTask (not async upload) so the session delegate fires for progress.
        let handler = UploadHandler { [weak self] progress in
            Task { @MainActor in self?.uploadProgress = progress }
        }
        let session = URLSession(configuration: .default, delegate: handler, delegateQueue: nil)

        return await withCheckedContinuation { cont in
            handler.onComplete = { [weak self] statusCode, body in
                if statusCode >= 400 {
                    let msg = body.isEmpty ? "HTTP \(statusCode)" : body
                    Task { @MainActor in self?.error = "Upload failed: \(msg)" }
                    cont.resume(returning: false)
                } else {
                    cont.resume(returning: true)
                }
            }
            handler.onError = { [weak self] err in
                Task { @MainActor in self?.error = "Upload failed: \(err)" }
                cont.resume(returning: false)
            }
            let task = session.uploadTask(with: req, fromFile: fileURL)
            task.resume()
        }
    }

    private func confirmUpload(token: String, fileName: String, fileSize: Int64,
                               storagePath: String, platform: String,
                               targetDeviceID: String?, arch: String?) async -> Bool {
        guard let url = URL(string: "\(apiBase)/confirm") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        struct Body: Encodable {
            let file_name: String; let file_size: Int64
            let storage_path: String; let platform: String
            let target_device_id: String?; let arch: String?
        }
        req.httpBody = try? JSONEncoder().encode(Body(
            file_name: fileName, file_size: fileSize,
            storage_path: storagePath, platform: platform,
            target_device_id: targetDeviceID, arch: arch
        ))
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }
}

// MARK: - Upload handler (progress + completion via uploadTask)

private final class UploadHandler: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let onProgress: (Double) -> Void
    var onComplete: ((Int, String) -> Void)?
    var onError:    ((String) -> Void)?
    private var responseData = Data()
    private var statusCode   = 0

    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64, totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { onError?(error.localizedDescription); return }
        let body = String(data: responseData, encoding: .utf8) ?? ""
        onComplete?(statusCode, body)
    }
}

// MARK: - Download delegate (progress for downloads)

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let onProgress: (Double) -> Void
    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
