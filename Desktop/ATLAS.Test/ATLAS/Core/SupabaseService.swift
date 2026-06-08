import Foundation
import IOKit

// MARK: - Models

struct ATLASSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: String
    let email: String

    var isExpired: Bool { Date() >= expiresAt }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case userID = "user_id"
        case email
    }
}

struct ATLASProfile: Codable {
    let id: String
    let email: String
    let plan: String                // "standard" or "pro"
    let subscriptionStatus: String

    var isPro: Bool { plan == "pro" }

    enum CodingKeys: String, CodingKey {
        case id, email, plan
        case subscriptionStatus = "subscription_status"
    }
}

struct ATLASDevice: Codable, Identifiable {
    let id: String
    let deviceName: String
    let hardwareUUID: String
    let lastSeen: String

    enum CodingKeys: String, CodingKey {
        case id
        case deviceName  = "device_name"
        case hardwareUUID = "hardware_uuid"
        case lastSeen    = "last_seen"
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case invalidURL
    case noData
    case httpError(Int, String)
    case decodingError(String)
    case notAuthenticated
    case deviceLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid server URL."
        case .noData:               return "No data received from server."
        case .httpError(let c, let m): return "Server error \(c): \(m)"
        case .decodingError(let m): return "Could not parse response: \(m)"
        case .notAuthenticated:     return "You are not signed in."
        case .deviceLimitReached:   return "Pro plan allows up to 3 devices. Remove a device in Account settings first."
        }
    }
}

// MARK: - Supabase REST client

actor SupabaseService {
    static let shared = SupabaseService()
    private init() {}

    private var base: String { SupabaseConfig.projectURL }
    private var anon: String { SupabaseConfig.anonKey }

    // MARK: - Auth

    func signUp(email: String, password: String) async throws -> ATLASSession {
        let body: [String: String] = ["email": email, "password": password]
        let data = try await post(path: "/auth/v1/signup", body: body, token: nil)
        return try parseSession(data)
    }

    func signIn(email: String, password: String) async throws -> ATLASSession {
        let body: [String: String] = ["email": email, "password": password]
        let data = try await post(path: "/auth/v1/token?grant_type=password",
                                  body: body, token: nil)
        return try parseSession(data)
    }

    func refreshSession(_ refreshToken: String) async throws -> ATLASSession {
        let body: [String: String] = ["refresh_token": refreshToken]
        let data = try await post(path: "/auth/v1/token?grant_type=refresh_token",
                                  body: body, token: nil)
        return try parseSession(data)
    }

    func signOut(accessToken: String) async throws {
        _ = try await post(path: "/auth/v1/logout", body: [:] as [String: String],
                           token: accessToken)
    }

    func resetPassword(email: String) async throws {
        let body: [String: String] = ["email": email]
        _ = try await post(path: "/auth/v1/recover", body: body, token: nil)
    }

    func cancelSubscription(accessToken: String) async throws {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/cancel") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                   ?? "Cancellation failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
    }

    // MARK: - Profile

    func getProfile(accessToken: String, userID: String) async throws -> ATLASProfile {
        let path = "/rest/v1/profiles?id=eq.\(userID)&select=id,email,plan,subscription_status"
        let data = try await get(path: path, token: accessToken)
        let profiles = try decode([ATLASProfile].self, from: data)
        guard let profile = profiles.first else {
            throw SupabaseError.decodingError("Profile not found")
        }
        return profile
    }

    // MARK: - Devices

    func getDevices(accessToken: String, userID: String) async throws -> [ATLASDevice] {
        let path = "/rest/v1/devices?user_id=eq.\(userID)&select=id,device_name,hardware_uuid,last_seen&order=created_at.asc"
        let data = try await get(path: path, token: accessToken)
        return try decode([ATLASDevice].self, from: data)
    }

    func registerDevice(accessToken: String, userID: String,
                        name: String, hardwareUUID: String,
                        isPro: Bool) async throws {
        // Enforce 3-device limit for Pro, 1 for Standard
        let existing = try await getDevices(accessToken: accessToken, userID: userID)
        let limit = isPro ? 3 : 1
        let alreadyRegistered = existing.contains { $0.hardwareUUID == hardwareUUID }

        if !alreadyRegistered && existing.count >= limit {
            throw SupabaseError.deviceLimitReached
        }

        // Upsert — updates last_seen if device already exists
        let body: [String: String] = [
            "user_id": userID,
            "device_name": name,
            "hardware_uuid": hardwareUUID,
            "last_seen": ISO8601DateFormatter().string(from: Date())
        ]
        _ = try await post(path: "/rest/v1/devices?on_conflict=user_id,hardware_uuid",
                           body: body, token: accessToken,
                           extraHeaders: ["Prefer": "resolution=merge-duplicates"])
    }

    func removeDevice(accessToken: String, deviceID: String) async throws {
        _ = try await delete(path: "/rest/v1/devices?id=eq.\(deviceID)",
                             token: accessToken)
    }

    func removeCurrentDevice(accessToken: String, userID: String, hardwareUUID: String) async throws {
        _ = try await delete(
            path: "/rest/v1/devices?user_id=eq.\(userID)&hardware_uuid=eq.\(hardwareUUID)",
            token: accessToken)
    }

    // MARK: - New device notification

    func notifyNewDevice(accessToken: String, deviceName: String, hardwareUUID: String) async throws {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/notify-device") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "device_name": deviceName,
            "hardware_uuid": hardwareUUID
        ])
        let (_, _) = try await URLSession.shared.data(for: req)
    }

    // MARK: - Privacy Consent

    func givePrivacyConsent(accessToken: String) async throws {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/consent") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                   ?? "Consent update failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
    }

    // MARK: - Offline token (Phase 2)

    func uploadLog(
        accessToken: String,
        logType: String,
        appName: String,
        filename: String,
        content: String,
        deviceName: String,
        hardwareUUID: String
    ) async throws {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/logs") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "log_type": logType,
            "app_name": appName,
            "filename": filename,
            "content": content,
            "device_name": deviceName,
            "hardware_uuid": hardwareUUID
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                   ?? "Log upload failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
    }

    func fetchOfflineToken(accessToken: String, hardwareUUID: String) async throws -> String {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/token") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["hardware_uuid": hardwareUUID])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
                   ?? "Token fetch failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        guard let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String
        else { throw SupabaseError.decodingError("Missing token in response") }
        return token
    }

    // MARK: - HTTP helpers

    private func get(path: String, token: String?) async throws -> Data {
        guard let url = URL(string: base + path) else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        addHeaders(&req, token: token)
        return try await perform(req)
    }

    private func post(path: String, body: Encodable, token: String?,
                      extraHeaders: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: base + path) else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = try JSONEncoder().encode(body)
        addHeaders(&req, token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        return try await perform(req)
    }

    private func delete(path: String, token: String?) async throws -> Data {
        guard let url = URL(string: base + path) else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        addHeaders(&req, token: token)
        return try await perform(req)
    }

    private func addHeaders(_ req: inout URLRequest, token: String?) {
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String
                   ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String
                   ?? String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SupabaseError.decodingError(error.localizedDescription)
        }
    }

    private func parseSession(_ data: Data) throws -> ATLASSession {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SupabaseError.decodingError("Bad auth response") }

        guard let access    = json["access_token"]  as? String,
              let refresh   = json["refresh_token"] as? String,
              let expiresIn = json["expires_in"]    as? TimeInterval,
              let user      = json["user"]          as? [String: Any],
              let uid       = user["id"]            as? String,
              let email     = user["email"]         as? String
        else { throw SupabaseError.decodingError("Missing auth fields") }

        return ATLASSession(
            accessToken:  access,
            refreshToken: refresh,
            expiresAt:    Date().addingTimeInterval(expiresIn - 60),
            userID:       uid,
            email:        email
        )
    }
}

// MARK: - Hardware UUID

func atlasHardwareUUID() -> String {
    let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                             IOServiceMatching("IOPlatformExpertDevice"))
    defer { IOObjectRelease(service) }
    guard service != 0 else { return UUID().uuidString }
    let uuid = IORegistryEntryCreateCFProperty(
        service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0
    )?.takeRetainedValue() as? String
    return uuid ?? UUID().uuidString
}
