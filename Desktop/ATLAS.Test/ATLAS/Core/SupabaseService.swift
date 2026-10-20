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
    let plan: String                // "atlas" (or legacy "standard"/"pro")
    let subscriptionStatus: String
    let billingAnchorDay: Int?      // day of month billing renews (1-31)
    let billingInterval: String?    // "monthly" or "annual"

    // P0-1: profiles.plan is NEVER an entitlement signal — it is display
    // metadata only. The sole entitlement authority is a server-verified
    // subscriptions.status == 'active' check (see AuthManager.entitlementActive,
    // populated via GET /api/atlas/entitlement). This property is deliberately
    // no longer derived from `plan` and always returns false so nothing can
    // silently fall back to the old, incorrect plan-string check.
    @available(*, deprecated, message: "Use AuthManager.shared.isSubscribed (server-verified), not this. Never derive entitlement from plan.")
    var isSubscribed: Bool { false }
    @available(*, deprecated, message: "Use AuthManager.shared.isSubscribed (server-verified), not this.")
    var isPro: Bool { false }

    enum CodingKeys: String, CodingKey {
        case id, email, plan
        case subscriptionStatus = "subscription_status"
        case billingAnchorDay   = "billing_anchor_day"
        case billingInterval    = "billing_interval"
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
    case emailNotConfirmed
    case notEntitled
    case serverUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid server URL."
        case .noData:               return "No data received from server."
        case .httpError(let c, let m): return "Server error \(c): \(m)"
        case .decodingError(let m): return "Could not parse response: \(m)"
        case .notAuthenticated:     return "You are not signed in."
        case .deviceLimitReached:   return "ATLAS allows up to 3 devices. Remove a device in Account settings first."
        case .emailNotConfirmed:    return "Please confirm your email before signing in. Check your inbox for a confirmation link."
        case .notEntitled:          return "This account does not have an active ATLAS subscription."
        case .serverUnavailable:    return "Couldn't verify with the server. Please try again."
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
        do {
            let data = try await post(path: "/auth/v1/token?grant_type=password",
                                      body: body, token: nil)
            return try parseSession(data)
        } catch SupabaseError.httpError(_, let msg)
                where msg.lowercased().contains("email not confirmed") ||
                      msg.lowercased().contains("email_not_confirmed") {
            throw SupabaseError.emailNotConfirmed
        }
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

    func updatePassword(accessToken: String, newPassword: String) async throws {
        let body: [String: String] = ["password": newPassword]
        _ = try await patch(path: "/auth/v1/user", body: body, token: accessToken)
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
        let path = "/rest/v1/profiles?id=eq.\(userID)&select=id,email,plan,subscription_status,billing_anchor_day,billing_interval"
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

    // P0-4: device registration is now atomic and server-authoritative via
    // POST /api/atlas/devices/register (backed by the register_device RPC).
    // The Swift client no longer counts devices or inserts rows itself —
    // that direct-REST path is closed (the devices table's client INSERT RLS
    // policy was removed). userID is not sent in the request body; the
    // server derives identity from the verified accessToken.
    func registerDevice(accessToken: String, userID: String,
                        name: String, hardwareUUID: String,
                        isSubscribed: Bool) async throws {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/devices/register") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "hardware_uuid": hardwareUUID,
            "device_name": name,
        ])
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.serverUnavailable }

        if http.statusCode == 200 { return }

        let reason = json["reason"] as? String
        switch reason {
        case "device_limit":   throw SupabaseError.deviceLimitReached
        case "not_entitled":   throw SupabaseError.notEntitled
        case "server_error":   throw SupabaseError.serverUnavailable
        default:
            throw SupabaseError.httpError(http.statusCode, reason ?? "Device registration failed")
        }
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

    // MARK: - Entitlement (P0-2)
    // Sole server-authoritative check for "does this account have an active
    // ATLAS subscription." Never inferred from profiles.plan locally.

    enum EntitlementResult {
        case active
        case notEntitled(reason: String?)
        case serverError
    }

    func fetchEntitlement(accessToken: String) async throws -> EntitlementResult {
        guard let url = URL(string: "https://www.interlinked.digital/api/atlas/entitlement") else {
            throw SupabaseError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { return .serverError }
        guard (200...299).contains(http.statusCode) else { return .serverError }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .serverError
        }
        if (json["valid"] as? Bool) == true {
            return .active
        }
        return .notEntitled(reason: json["reason"] as? String)
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

    private func patch(path: String, body: Encodable, token: String?) async throws -> Data {
        guard let url = URL(string: base + path) else { throw SupabaseError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.httpBody = try JSONEncoder().encode(body)
        addHeaders(&req, token: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
