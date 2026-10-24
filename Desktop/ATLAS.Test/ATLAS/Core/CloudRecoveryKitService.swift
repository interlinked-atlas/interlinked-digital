import Foundation
import CryptoKit
import Security

// MARK: - CloudKitMeta

struct CloudKitMeta: Equatable {
    let id: UUID
    let generatedAt: Date
    let recordCount: Int
    let archivedCount: Int
    let deviceName: String?
    let atlasVersion: String
    let atlaskitSize: Int?
    let txtSize: Int?
}

// MARK: - CloudRecoveryKitService

// All cloud Recovery Kit operations: key management, upload, download, list, delete.
// Upload receives the ACTUAL kit.atlaskit and kit.txt bytes already generated locally.
// Never regenerates a new AtlasKit from HistoryStore — preserves the exact exported artifact.

actor CloudRecoveryKitService {
    static let shared = CloudRecoveryKitService()
    private init() {}

    private let base       = "https://www.interlinked.digital/api/atlas/recovery-kit"
    private let kcService  = "com.atlas.ATLAS"
    // Legacy identifier (pre-account-scoping) — a single Keychain item shared by
    // whichever ATLAS account happened to sign in first on this Mac. Kept ONLY
    // for one-time, one-directional migration below; never written to again.
    private let legacyDEKAccount = "atlas-recovery-kit-dek"

    // Per-account identifier — confirmed necessary: fetchOrLoadDEK() previously
    // looked up legacyDEKAccount with no user-identity check at all, so signing
    // out of account A and into account B on the same Mac (signOut() never
    // cleared this item) would hand B's upload/download calls A's cached DEK
    // without error. Scoping the Keychain account string by user_id closes
    // that: a per-account query can only ever return that same account's key.
    private func dekAccount(for userID: String) -> String {
        "atlas-recovery-kit-dek-\(userID)"
    }

    // MARK: - DEK Keychain helpers

    private func loadDEK(account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          kcService,
            kSecAttrAccount as String:          account,
            kSecReturnData as String:           true,
            kSecMatchLimit as String:           kSecMatchLimitOne,
            kSecUseAuthenticationUI as String:  kSecUseAuthenticationUISkip
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveDEK(_ dek: String, account: String) {
        let data = Data(dek.utf8)
        let del: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: kcService,
                                   kSecAttrAccount as String: account]
        SecItemDelete(del as CFDictionary)
        var add: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    kcService,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        var access: SecAccess?
        SecAccessCreate("ATLAS Cloud Recovery Key" as CFString, nil, &access)
        if let access { add[kSecAttrAccess as String] = access }
        SecItemAdd(add as CFDictionary, nil)
    }

    private func deleteDEK(account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: kcService,
                                 kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    // Clears only the calling (now signing-out) account's own cached DEK.
    // Called from AuthManager.signOut(). Never touches another account's entry
    // — each account's Keychain item is independently addressed by userID.
    func clearDEK(userID: String) {
        deleteDEK(account: dekAccount(for: userID))
    }

    private func fetchOrLoadDEK(token: String, userID: String) async throws -> String {
        let account = dekAccount(for: userID)
        if let cached = loadDEK(account: account) { return cached }

        // One-time, one-directional migration for existing installs: before this
        // fix, every account on this Mac shared the single legacy item. If it's
        // still there, the common case (one account ever used on this Mac) means
        // it genuinely belongs to this user — adopt it under the new per-account
        // key so this and future lookups are correctly scoped, and remove the
        // legacy item so a second account can never again inherit it from here.
        // This never silently regenerates or replaces a key the server already
        // has a different value for — apiDEK()/the server remain untouched by
        // this branch, and existing cloud kits stay decryptable because the same
        // key bytes are preserved, only their local Keychain location changes.
        if let legacy = loadDEK(account: legacyDEKAccount) {
            saveDEK(legacy, account: account)
            deleteDEK(account: legacyDEKAccount)
            return legacy
        }

        let dek = try await apiDEK(token: token)
        saveDEK(dek, account: account)
        return dek
    }

    // POST /api/atlas/recovery-kit/key → { key: base64 }
    private func apiDEK(token: String) async throws -> String {
        guard let url = URL(string: "\(base)/key") else { throw CloudKitError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String else {
            throw CloudKitError.badResponse("Missing key in response")
        }
        return key
    }

    // MARK: - List

    // Returns all active cloud Recovery Kits for this user, newest first.
    func list(token: String) async throws -> [CloudKitMeta] {
        guard let url = URL(string: "\(base)/list") else { throw CloudKitError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data: data)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kits = json["kits"] as? [[String: Any]] else { return [] }
        return kits.compactMap { parseMeta($0) }
    }

    // MARK: - Upload

    // Uploads the ACTUAL kit.atlaskit and kit.txt bytes that were generated locally.
    // Encrypts each file independently with the user's DEK (separate nonces).
    // Creates a new kit record — does not modify or replace existing cloud kits.
    func upload(
        kitAtlaskitData: Data,
        kitTxtData: Data,
        generatedAt: Date,
        atlasVersion: String,
        kitVersion: Int,
        recordCount: Int,
        archivedCount: Int,
        token: String,
        userID: String
    ) async throws -> CloudKitMeta {
        let dek    = try await fetchOrLoadDEK(token: token, userID: userID)
        let symKey = try RecoveryKitCrypto.symmetricKey(from: dek)

        // Encrypt each file independently — separate random nonces
        let encryptedAtlaskit = try RecoveryKitCrypto.encrypt(data: kitAtlaskitData, key: symKey)
        let encryptedTxt      = try RecoveryKitCrypto.encrypt(data: kitTxtData,      key: symKey)

        // Request upload URLs + server-generated kit_id
        guard let uploadUrlEndpoint = URL(string: "\(base)/upload-url") else { throw CloudKitError.invalidURL }
        var urlReq = URLRequest(url: uploadUrlEndpoint)
        urlReq.httpMethod = "POST"
        urlReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        urlReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "generated_at":   df.string(from: generatedAt),
            "atlaskit_size":  encryptedAtlaskit.count,
            "txt_size":       encryptedTxt.count,
            "atlas_version":  atlasVersion,
            "kit_version":    kitVersion,
            "record_count":   recordCount,
            "archived_count": archivedCount,
            "device_name":    deviceFriendlyName() as Any,
            "hardware_uuid":  atlasHardwareUUID() as Any,
        ])
        let (urlData, urlResp) = try await URLSession.shared.data(for: urlReq)
        try checkHTTP(urlResp, data: urlData)

        guard let urlJson         = try? JSONSerialization.jsonObject(with: urlData) as? [String: Any],
              let kitIdStr        = urlJson["kit_id"]            as? String,
              let kitId           = UUID(uuidString: kitIdStr),
              let atlaskitUpload  = urlJson["atlaskit_upload_url"] as? String,
              let atlaskitUpURL   = URL(string: atlaskitUpload),
              let atlaskitPath    = urlJson["atlaskit_path"]     as? String,
              let txtUpload       = urlJson["txt_upload_url"]    as? String,
              let txtUpURL        = URL(string: txtUpload),
              let txtPath         = urlJson["txt_path"]          as? String
        else { throw CloudKitError.badResponse("Missing upload URL fields") }

        // PUT encrypted atlaskit
        var putAtlaskit = URLRequest(url: atlaskitUpURL)
        putAtlaskit.httpMethod = "PUT"
        putAtlaskit.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        putAtlaskit.httpBody = encryptedAtlaskit
        let (_, putAResp) = try await URLSession.shared.data(for: putAtlaskit)
        if let http = putAResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CloudKitError.server("atlaskit upload failed (HTTP \(http.statusCode))")
        }

        // PUT encrypted txt
        var putTxt = URLRequest(url: txtUpURL)
        putTxt.httpMethod = "PUT"
        putTxt.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        putTxt.httpBody = encryptedTxt
        let (_, putTResp) = try await URLSession.shared.data(for: putTxt)
        if let http = putTResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CloudKitError.server("txt upload failed (HTTP \(http.statusCode))")
        }

        // Confirm — INSERT new row
        guard let confirmURL = URL(string: "\(base)/confirm") else { throw CloudKitError.invalidURL }
        var cReq = URLRequest(url: confirmURL)
        cReq.httpMethod = "POST"
        cReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        cReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        cReq.httpBody = try JSONSerialization.data(withJSONObject: [
            "kit_id":         kitIdStr,
            "atlaskit_path":  atlaskitPath,
            "txt_path":       txtPath,
            "generated_at":   df.string(from: generatedAt),
            "atlas_version":  atlasVersion,
            "kit_version":    kitVersion,
            "record_count":   recordCount,
            "archived_count": archivedCount,
            "atlaskit_size":  encryptedAtlaskit.count,
            "txt_size":       encryptedTxt.count,
            "device_name":    deviceFriendlyName() as Any,
            "hardware_uuid":  atlasHardwareUUID() as Any,
        ])
        let (cData, cResp) = try await URLSession.shared.data(for: cReq)
        try checkHTTP(cResp, data: cData)

        return CloudKitMeta(
            id:            kitId,
            generatedAt:   generatedAt,
            recordCount:   recordCount,
            archivedCount: archivedCount,
            deviceName:    deviceFriendlyName(),
            atlasVersion:  atlasVersion,
            atlaskitSize:  encryptedAtlaskit.count,
            txtSize:       encryptedTxt.count
        )
    }

    // MARK: - Download (for Mac app — downloads encrypted blob, decrypts locally)

    // Downloads and decrypts a specific kit by ID.
    // Returns the plaintext kit.atlaskit bytes ready for existing AtlasKit decode + hash verify flow.
    func download(kitId: UUID, token: String, userID: String) async throws -> Data {
        guard let url = URL(string: "\(base)/download-url?kit_id=\(kitId.uuidString)") else {
            throw CloudKitError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (urlData, urlResp) = try await URLSession.shared.data(for: req)
        try checkHTTP(urlResp, data: urlData)
        guard let urlJson  = try? JSONSerialization.jsonObject(with: urlData) as? [String: Any],
              let dlStr    = urlJson["atlaskit_download_url"] as? String,
              let dlURL    = URL(string: dlStr)
        else { throw CloudKitError.badResponse("Missing atlaskit_download_url") }

        let (encData, dlResp) = try await URLSession.shared.data(from: dlURL)
        if let http = dlResp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw CloudKitError.server("Download failed (HTTP \(http.statusCode))")
        }

        let dek    = try await fetchOrLoadDEK(token: token, userID: userID)
        let symKey = try RecoveryKitCrypto.symmetricKey(from: dek)
        return try RecoveryKitCrypto.decrypt(envelopeData: encData, key: symKey)
    }

    // MARK: - Delete

    func deleteKit(kitId: UUID, token: String) async throws {
        guard let url = URL(string: "\(base)/delete") else { throw CloudKitError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["kit_id": kitId.uuidString])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkHTTP(resp, data: data)
    }

    // MARK: - Helpers

    private func checkHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                   ?? "Server error \(http.statusCode)"
            throw CloudKitError.server(msg)
        }
    }

    private func parseMeta(_ kit: [String: Any]) -> CloudKitMeta? {
        guard let idStr = kit["id"] as? String, let id = UUID(uuidString: idStr) else { return nil }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let generatedAt = (kit["generated_at"] as? String).flatMap {
            isoFrac.date(from: $0) ?? iso.date(from: $0)
        } ?? Date()
        return CloudKitMeta(
            id:            id,
            generatedAt:   generatedAt,
            recordCount:   kit["record_count"]   as? Int    ?? 0,
            archivedCount: kit["archived_count"] as? Int    ?? 0,
            deviceName:    kit["device_name"]    as? String,
            atlasVersion:  kit["atlas_version"]  as? String ?? "",
            atlaskitSize:  kit["atlaskit_size"]  as? Int,
            txtSize:       kit["txt_size"]       as? Int
        )
    }
}

// MARK: - Errors

enum CloudKitError: Error, LocalizedError {
    case invalidURL
    case server(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Invalid server URL."
        case .server(let m):      return m
        case .badResponse(let m): return m
        }
    }
}
