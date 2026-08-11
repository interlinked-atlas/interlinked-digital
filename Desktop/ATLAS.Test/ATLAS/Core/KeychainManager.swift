import Foundation
import Security

// Stores and retrieves the user's sudo password from macOS Keychain.
// We use kSecClassGenericPassword which is the standard way to store
// credentials in Keychain — it is encrypted at rest and tied to this app.

struct KeychainManager {

    private static let service = "com.atlas.ATLAS"
    private static let account = "sudo-password"

    // One-time migration: delete old Keychain items that have a restrictive ACL
    // so they get recreated with the open-access policy on next save.
    // Runs only once per install via a UserDefaults flag.
    static func migrateAccessControlIfNeeded() {
        let key = "atlas.keychain.aclMigrated.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        // Delete all items — they will be re-created with open access on next write
        for acct in [account, sessionAccount, offlineTokenAccount, lastVerifiedAccount, cachedProfileAccount] {
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: acct]
            SecItemDelete(q as CFDictionary)
        }
        // Clear caches so they get re-read from Keychain after re-auth
        _cachedPassword    = nil
        _cachedSession     = nil
        _cachedOfflineToken = nil
        _cachedLastVerified = nil
        _cachedProfile     = nil
    }

    // In-memory cache — read from Keychain once per app session.
    // Every call to loadPassword() hits the Security framework which can
    // trigger a macOS "allow this app to access Keychain" prompt each time
    // if the app is ad-hoc signed. Caching avoids repeated prompts.
    private static var _cachedPassword: String? = nil

    // Creates a Keychain access object that allows all applications silently —
    // avoids the "authenticity cannot be verified" prompt on unsigned/ad-hoc builds.
    private static func openAccess(label: String) -> SecAccess? {
        var access: SecAccess?
        SecAccessCreate(label as CFString, nil, &access)
        return access
    }

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

        var addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if let access = openAccess(label: "ATLAS Password") {
            addQuery[kSecAttrAccess as String] = access
        }

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
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          account,
            kSecReturnData as String:           true,
            kSecMatchLimit as String:           kSecMatchLimitOne,
            kSecUseAuthenticationUI as String:  kSecUseAuthenticationUISkip
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

    private static let sessionAccount   = "atlas-session"
    private static var _cachedSession:  ATLASSession? = nil

    static func saveSession(_ session: ATLASSession) {
        _cachedSession = session
        guard let data = try? JSONEncoder().encode(session) else { return }
        let del: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: sessionAccount]
        SecItemDelete(del as CFDictionary)
        var add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: sessionAccount,
                                   kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if let access = openAccess(label: "ATLAS Session") { add[kSecAttrAccess as String] = access }
        SecItemAdd(add as CFDictionary, nil)
    }

    // Replaces the Keychain ACL for the session item with a fresh open-access object.
    // Stale ACL entries (e.g. from "Always Allow" clicks on a previous build binary)
    // contain broken app references that cause macOS to show a repeated authenticity
    // warning prompt. SecItemUpdate with a new SecAccess replaces the ACL in-place
    // without touching kSecValueData — the session token is preserved.
    private static func repairKeychainACLIfNeeded() {
        var access: SecAccess?
        guard SecAccessCreate("ATLAS Session" as CFString, nil, &access) == errSecSuccess,
              let access else { return }
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sessionAccount
        ]
        let update: [String: Any] = [kSecAttrAccess as String: access]
        SecItemUpdate(query as CFDictionary, update as CFDictionary)
    }

    static func loadSession() -> ATLASSession? {
        if let cached = _cachedSession { return cached }
        repairKeychainACLIfNeeded()
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: sessionAccount,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne,
                                 kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip]
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        let session = try? JSONDecoder().decode(ATLASSession.self, from: data)
        _cachedSession = session
        return session
    }

    static func clearSession() {
        _cachedSession = nil
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: sessionAccount]
        SecItemDelete(q as CFDictionary)
    }

    // MARK: - Offline token / profile cache

    private static let offlineTokenAccount   = "atlas-offline-token"
    private static let lastVerifiedAccount   = "atlas-last-verified"
    private static let cachedProfileAccount  = "atlas-cached-profile"

    private static var _cachedOfflineToken:  String? = nil
    private static var _cachedLastVerified:  Date?   = nil
    private static var _cachedProfile:       ATLASProfile? = nil

    static func saveOfflineToken(_ token: String) {
        _cachedOfflineToken = token
        keychainSet(account: offlineTokenAccount, data: Data(token.utf8))
    }

    static func loadOfflineToken() -> String? {
        if let cached = _cachedOfflineToken { return cached }
        guard let d = keychainGet(account: offlineTokenAccount) else { return nil }
        let token = String(data: d, encoding: .utf8)
        _cachedOfflineToken = token
        return token
    }

    static func clearOfflineToken() {
        _cachedOfflineToken = nil
        keychainDelete(account: offlineTokenAccount)
    }

    static func saveLastVerified(_ date: Date) {
        _cachedLastVerified = date
        var t = date.timeIntervalSince1970
        keychainSet(account: lastVerifiedAccount, data: Data(bytes: &t, count: MemoryLayout<Double>.size))
    }

    static func loadLastVerified() -> Date? {
        if let cached = _cachedLastVerified { return cached }
        guard let d = keychainGet(account: lastVerifiedAccount),
              d.count == MemoryLayout<Double>.size else { return nil }
        let t = d.withUnsafeBytes { $0.load(as: Double.self) }
        let date = Date(timeIntervalSince1970: t)
        _cachedLastVerified = date
        return date
    }

    static func saveProfile(_ profile: ATLASProfile) {
        _cachedProfile = profile
        guard let data = try? JSONEncoder().encode(profile) else { return }
        keychainSet(account: cachedProfileAccount, data: data)
    }

    static func loadProfile() -> ATLASProfile? {
        if let cached = _cachedProfile { return cached }
        guard let d = keychainGet(account: cachedProfileAccount) else { return nil }
        let profile = try? JSONDecoder().decode(ATLASProfile.self, from: d)
        _cachedProfile = profile
        return profile
    }

    static func clearOfflineData() {
        _cachedOfflineToken = nil
        _cachedLastVerified = nil
        _cachedProfile      = nil
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
        var add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account,
                                   kSecValueData as String: data,
                                   kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if let access = openAccess(label: "ATLAS") { add[kSecAttrAccess as String] = access }
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func keychainGet(account: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                 kSecAttrService as String: service,
                                 kSecAttrAccount as String: account,
                                 kSecReturnData as String: true,
                                 kSecMatchLimit as String: kSecMatchLimitOne,
                                 kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip]
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
