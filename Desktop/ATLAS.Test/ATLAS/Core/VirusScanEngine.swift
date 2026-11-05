import Foundation
import CryptoKit

// MARK: - Models

enum VirusVerdict: String, Codable {
    case clean, pua, suspicious, malicious, unknown, unscanned
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
    var isClear:    Bool { verdict == .clean || verdict == .unknown || verdict == .unscanned }

    // Local check only — never claims a clean bill of health the way a
    // multi-engine cloud scan would. "unscanned" means "not found in our
    // local known-malware list," not "verified safe."
    var summaryLine: String {
        switch verdict {
        case .clean, .unknown, .unscanned:
            return "Not found in ATLAS's local known-malware list"
        case .pua:
            return "Filename pattern matches common crack/keygen tools"
        case .suspicious:
            return "Flagged by ATLAS's local check"
        case .malicious:
            return "Matches a known malware signature"
        }
    }

    var color: String {
        switch verdict {
        case .clean, .unknown, .unscanned: return "green"
        case .pua:                         return "yellow"
        case .suspicious:                  return "orange"
        case .malicious:                   return "red"
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

    // Filename patterns commonly seen on crack/keygen/patcher tools —
    // flagged as PUA (potentially unwanted), never hard-blocked on name alone.
    private let puaNamePatterns = ["keygen", "crack", "patch", "patched", "loader", "activator"]

    private lazy var knownMalwareHashes: Set<String> = {
        guard let url = Bundle.module.url(forResource: "KnownMalwareHashes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(HashList.self, from: data)
        else { return [] }
        return Set(decoded.hashes.keys.map { $0.lowercased() })
    }()

    // Fully local — no network call, no auth, no backend dependency. Checks
    // the file's SHA-256 against a bundled known-malware list and its
    // filename against common crack/keygen patterns. This is a basic check,
    // not a substitute for real antivirus software (see VirusScanView's
    // disclaimer).
    func scan(url: URL) async -> VirusScanResult? {
        isScanning  = true
        scanResult  = nil
        lastResult  = nil
        error       = nil

        defer { isScanning = false }

        guard let hash = sha256(url: url) else {
            error = "Could not read file for scanning"
            return nil
        }

        let verdict: VirusVerdict
        if knownMalwareHashes.contains(hash.lowercased()) {
            verdict = .malicious
        } else if puaNamePatterns.contains(where: { url.lastPathComponent.lowercased().contains($0) }) {
            verdict = .pua
        } else {
            verdict = .unscanned
        }

        let result = VirusScanResult(
            verdict:    verdict,
            malicious:  verdict == .malicious ? 1 : 0,
            suspicious: 0,
            total:      0,
            engines:    [],
            hash:       hash
        )
        lastResult = result
        scanResult = result.verdict
        return result
    }

    private struct HashList: Codable {
        let hashes: [String: String]
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
}
