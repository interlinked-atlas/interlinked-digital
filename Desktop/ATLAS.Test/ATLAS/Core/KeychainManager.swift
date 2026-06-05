import Foundation
import Security

// Stores and retrieves the user's sudo password from macOS Keychain.
// We use kSecClassGenericPassword which is the standard way to store
// credentials in Keychain — it is encrypted at rest and tied to this app.

struct KeychainManager {

    private static let service = "com.atlas.ATLAS"
    private static let account = "sudo-password"

    // In-memory cache — read from Keychain once per app session.
    // Every call to loadPassword() hits the Security framework which can
    // trigger a macOS "allow this app to access Keychain" prompt each time
    // if the app is ad-hoc signed. Caching avoids repeated prompts.
    private static var _cachedPassword: String? = nil

    // Save password to Keychain and update the in-memory cache.
    static func savePassword(_ password: String) -> Bool {
        let data = password.data(using: .utf8)!

        // Delete any existing entry from either keychain before adding
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecSuccess {
            _cachedPassword = password
            return true
        }
        return false
    }

    // Returns the cached password — only reads Keychain on the first call per session.
    // Caching prevents repeated macOS "allow Keychain access" prompts on ad-hoc builds.
    static func loadPassword() -> String? {
        if let cached = _cachedPassword { return cached }

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        _cachedPassword = password
        return password
    }

    // Check if password is stored.
    static func hasPassword() -> Bool {
        return loadPassword() != nil
    }

    // Remove password from Keychain and clear the in-memory cache.
    static func clearPassword() {
        _cachedPassword = nil
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Session (Supabase auth token storage)

    private static let sessionAccount = "atlas-session"

    static func saveSession(_ session: ATLASSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let del: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: sessionAccount]
        SecItemDelete(del as CFDictionary)
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: sessionAccount,
                                   kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadSession() -> ATLASSession? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: sessionAccount,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ATLASSession.self, from: data)
    }

    static func clearSession() {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: sessionAccount]
        SecItemDelete(q as CFDictionary)
    }

    // MARK: - Offline token (Phase 2)

    private static let offlineTokenAccount   = "atlas-offline-token"
    private static let lastVerifiedAccount   = "atlas-last-verified"
    private static let cachedProfileAccount  = "atlas-cached-profile"

    static func saveOfflineToken(_ token: String) {
        keychainSet(account: offlineTokenAccount, data: Data(token.utf8))
    }

    static func loadOfflineToken() -> String? {
        guard let d = keychainGet(account: offlineTokenAccount) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func clearOfflineToken() { keychainDelete(account: offlineTokenAccount) }

    static func saveLastVerified(_ date: Date) {
        var t = date.timeIntervalSince1970
        keychainSet(account: lastVerifiedAccount, data: Data(bytes: &t, count: MemoryLayout<Double>.size))
    }

    static func loadLastVerified() -> Date? {
        guard let d = keychainGet(account: lastVerifiedAccount),
              d.count == MemoryLayout<Double>.size else { return nil }
        let t = d.withUnsafeBytes { $0.load(as: Double.self) }
        return Date(timeIntervalSince1970: t)
    }

    static func saveProfile(_ profile: ATLASProfile) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        keychainSet(account: cachedProfileAccount, data: data)
    }

    static func loadProfile() -> ATLASProfile? {
        guard let d = keychainGet(account: cachedProfileAccount) else { return nil }
        return try? JSONDecoder().decode(ATLASProfile.self, from: d)
    }

    static func clearOfflineData() {
        keychainDelete(account: offlineTokenAccount)
        keychainDelete(account: lastVerifiedAccount)
        keychainDelete(account: cachedProfileAccount)
    }

    // MARK: - Private helpers

    private static func keychainSet(account: String, data: Data) {
        let del: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(del as CFDictionary)
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account,
                                   kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainGet(account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: account,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func keychainDelete(account: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }
}
