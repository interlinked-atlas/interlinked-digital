import Foundation
import CryptoKit

// MARK: - Models

enum VirusVerdict: String, Codable {
    case clean, pua, suspicious, malicious, unknown
}

struct VirusScanResult {
    let verdict:    VirusVerdict
    let malicious:  Int
    let suspicious: Int
    let total:      Int
    let engines:    [FlaggingEngine]
    let hash:       String

    struct FlaggingEngine: Codable {
        let name:     String
        let result:   String
        let category: String
        let isPua:    Bool
    }

    var isBlocking: Bool { verdict == .malicious }
    var isWarning:  Bool { verdict == .suspicious || verdict == .pua }
    var isClear:    Bool { verdict == .clean || verdict == .unknown }

    var summaryLine: String {
        switch verdict {
        case .clean:      return "No threats detected (\(total) engines)"
        case .unknown:    return "File not in VirusTotal database"
        case .pua:        return "\(malicious) engine\(malicious == 1 ? "" : "s") flagged crack/keygen tools"
        case .suspicious: return "\(malicious + suspicious) engine\(malicious + suspicious == 1 ? "" : "s") flagged this file"
        case .malicious:  return "\(malicious) engine\(malicious == 1 ? "" : "s") detected malware"
        }
    }

    var color: String {
        switch verdict {
        case .clean, .unknown: return "green"
        case .pua:             return "yellow"
        case .suspicious:      return "orange"
        case .malicious:       return "red"
        }
    }
}

// MARK: - Engine

@MainActor
final class VirusScanEngine: ObservableObject {
    static let shared = VirusScanEngine()

    @Published var isScanning   = false
    @Published var scanResult:  VirusVerdict? = nil
    @Published var lastResult:  VirusScanResult? = nil
    @Published var error:       String? = nil

    private let apiBase = "https://www.interlinked.digital/api/atlas"

    func scan(url: URL) async -> VirusScanResult? {
        guard Features.isPro else { return nil }

        isScanning  = true
        scanResult  = nil
        lastResult  = nil
        error       = nil

        defer { isScanning = false }

        // 1. Compute SHA-256
        guard let hash = sha256(url: url) else {
            error = "Could not read file for scanning"
            return nil
        }

        // 2. Call API
        guard let token = await AuthManager.shared.currentToken() else {
            error = "Not authenticated"
            return nil
        }

        guard let apiURL = URL(string: "\(apiBase)/virusscan") else { return nil }
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["hash": hash])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 403 {
                // Shouldn't happen (gated by Features.isPro) but handle gracefully
                return nil
            }

            let json = try JSONDecoder().decode(ScanResponse.self, from: data)
            let result = VirusScanResult(
                verdict:    json.verdict,
                malicious:  json.malicious,
                suspicious: json.suspicious,
                total:      json.total,
                engines:    json.engines,
                hash:       hash
            )
            lastResult = result
            scanResult = result.verdict
            return result
        } catch {
            self.error = "Scan failed: \(error.localizedDescription)"
            return nil
        }
    }

    func deleteFile(url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

    private func sha256(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024 // 1 MB chunks

        while true {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Codable helpers

    private struct ScanResponse: Codable {
        let verdict:    VirusVerdict
        let malicious:  Int
        let suspicious: Int
        let total:      Int
        let engines:    [VirusScanResult.FlaggingEngine]
    }
}
