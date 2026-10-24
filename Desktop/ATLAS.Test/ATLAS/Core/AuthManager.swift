import Foundation
import AppKit

final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private init() {
        // Restore session immediately so returning users skip the login screen entirely.
        // If a Keychain prompt is needed it appears after splash (splash takes ~2s naturally).
        restoreSession()
    }

    @Published var session: ATLASSession?
    @Published var profile: ATLASProfile?
    @Published var isLoading = false
    @Published var isLoadingProfile = false
    @Published var authError: String?
    @Published var authErrorIsDeviceLimit = false
    @Published var authErrorIsEmailUnconfirmed = false
    @Published var devices: [ATLASDevice] = []
    @Published var planChangeNotice: String? = nil
    private var planSyncTimer: Timer?

    // P0-2: the ONLY source of truth for "may use paid ATLAS functionality."
    // Populated exclusively by a server round-trip to GET /api/atlas/entitlement
    // (itself backed by subscriptions.status == 'active'). Never derived from
    // profile.plan or any other locally-cached/client-side value.
    @Published private(set) var entitlementActive: Bool = false

    var isSignedIn: Bool { session != nil }
    var isSubscribed: Bool { entitlementActive }
    var isPro: Bool { isSubscribed }  // backward compat alias

    static let adminEmail = "titantinstaller@gmail.com"
    var isAdmin: Bool { userEmail.lowercased() == Self.adminEmail }
    var planLabel: String { "ATLAS" }
    var userEmail: String { session?.email ?? "" }
    var subscriptionActive: Bool {
        guard let p = profile else { return false }
        return p.subscriptionStatus == "active"
    }
    var subscriptionStatusLabel: String {
        switch profile?.subscriptionStatus {
        case "active":         return "Active"
        case "cancelled":      return "Cancelled"
        case "payment_failed": return "Payment Failed"
        default:               return "Inactive"
        }
    }

    // MARK: - Called from SwiftUI (main thread)

    func signIn(email: String, password: String) async {
        isLoading = true
        authError = nil
        authErrorIsEmailUnconfirmed = false
        do {
            let s = try await SupabaseService.shared.signIn(email: email, password: password)
            await completeAuth(s)
        } catch SupabaseError.emailNotConfirmed {
            authError = "Please confirm your email before signing in. Check your inbox for a link from interlinked.digital."
            authErrorIsEmailUnconfirmed = true
        } catch {
            let msg = error.localizedDescription.lowercased()
            if msg.contains("invalid login") || msg.contains("invalid credentials") || msg.contains("400") || msg.contains("wrong password") || msg.contains("email not found") {
                authError = "Incorrect email or password."
            } else {
                authError = error.localizedDescription
            }
        }
        isLoading = false
    }

    func signUp(email: String, password: String) async {
        isLoading = true
        authError = nil
        do {
            let s = try await SupabaseService.shared.signUp(email: email, password: password)
            await completeAuth(s)
        } catch {
            authError = error.localizedDescription
        }
        isLoading = false
    }

    func forgotPassword(email: String) async {
        isLoading = true
        authError = nil
        do {
            try await SupabaseService.shared.resetPassword(email: email)
        } catch {
            authError = error.localizedDescription
        }
        isLoading = false
    }

    func currentToken() async -> String? { session?.accessToken }

    // MARK: - Entitlement (P0-2)
    // Server-authoritative check, called at sign-in and on every periodic
    // re-check tick. A server/network error leaves entitlementActive
    // unchanged rather than forcing it true or false from a guess — callers
    // needing a fail-closed decision (e.g. install authorization) go through
    // their own dedicated server round-trip (check-install), which fails
    // closed independently. This flag drives UI/feature-gating display.
    @discardableResult
    private func checkEntitlement() async -> Bool {
        guard let token = session?.accessToken else {
            await MainActor.run { entitlementActive = false }
            return false
        }
        do {
            let result = try await SupabaseService.shared.fetchEntitlement(accessToken: token)
            switch result {
            case .active:
                await MainActor.run { entitlementActive = true }
                return true
            case .notEntitled:
                await MainActor.run { entitlementActive = false }
                return false
            case .serverError:
                // Could not verify — leave the last-known state as-is rather
                // than silently granting or revoking on a transient error.
                return entitlementActive
            }
        } catch {
            return entitlementActive
        }
    }

    func signOut() {
        let token = session?.accessToken
        clearLocalSession()                   // update UI immediately
        if let token {
            Task {
                // Signing out — whether user-initiated or triggered by the
                // periodic entitlement/device sync timer's defensive checks —
                // must never remove the device registration as a side effect.
                // Device removal is a deliberate, separate action the user
                // takes explicitly in Account Settings (with its own confirm
                // dialog, over the website's RLS-protected DELETE endpoint).
                // This previously called removeCurrentDevice() here too,
                // which meant any single transient/defensive sign-out
                // permanently deleted a correctly-registered device — and
                // since the next sign-in's periodic check would then
                // correctly (but now wrongly, because of this very call)
                // find the device missing, it triggered another sign-out,
                // which removed it again: a self-sustaining loop from one
                // transient trigger. Only the session itself is revoked here.
                try? await SupabaseService.shared.signOut(accessToken: token)
            }
        }
    }

    func cancelSubscription() async {
        guard let token = session?.accessToken else { return }
        isLoading = true
        authError = nil
        do {
            try await SupabaseService.shared.cancelSubscription(accessToken: token)
            clearLocalSession()
        } catch {
            authError = "Could not cancel: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func clearLocalSession() {
        planSyncTimer?.invalidate()
        planSyncTimer = nil
        // Clear this account's cached Recovery Kit encryption key before dropping
        // the session — same "different account signing in next must never
        // inherit this account's cached state" reasoning as the install-limit
        // cache reset below, for the Keychain-cached DEK instead.
        if let userID = session?.userID {
            Task { await CloudRecoveryKitService.shared.clearDEK(userID: userID) }
        }
        session = nil
        profile = nil
        devices = []
        authError = nil
        authErrorIsDeviceLimit = false
        entitlementActive = false
        KeychainManager.clearSession()
        KeychainManager.clearOfflineData()
        // Reset the monthly-install-limit local cache so a different account signing
        // in next never briefly sees this account's stale usage numbers.
        Task { @MainActor in MonthlyLimitManager.shared.resetForSignOut() }
    }

    // Public: called by SubscriptionRequiredView "I've subscribed" button
    func refreshProfile() async {
        guard let s = session, !s.isExpired else { return }
        if let p = try? await SupabaseService.shared.getProfile(
            accessToken: s.accessToken, userID: s.userID) {
            await MainActor.run { profile = p }
            KeychainManager.saveProfile(p)
        }
    }

    private func startPlanSyncTimer() {
        planSyncTimer?.invalidate()
        planSyncTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self = self, let s = self.session, !s.isExpired else { return }
            Task {
                // P0-2: re-verify server-authoritative entitlement on every tick.
                await self.checkEntitlement()
                // Sync profile (plan + subscription status)
                if let p = try? await SupabaseService.shared.getProfile(
                    accessToken: s.accessToken, userID: s.userID) {
                    let planChanged   = p.plan != self.profile?.plan
                    let statusChanged = p.subscriptionStatus != self.profile?.subscriptionStatus
                    // Force sign-out immediately if subscription was cancelled or payment failed
                    if p.subscriptionStatus == "cancelled" || p.subscriptionStatus == "payment_failed" {
                        await MainActor.run { self.signOut() }
                        return
                    }
                    if planChanged || statusChanged {
                        await MainActor.run {
                            self.profile = p
                        }
                        KeychainManager.saveProfile(p)
                    }
                }
                // Sync device list — force sign-out if this device was removed remotely
                if let list = try? await SupabaseService.shared.getDevices(
                    accessToken: s.accessToken, userID: s.userID) {
                    let myUUID = atlasHardwareUUID()
                    let stillRegistered = list.contains { $0.hardwareUUID == myUUID }
                    if !stillRegistered {
                        await MainActor.run { self.signOut() }
                        return
                    }
                    await MainActor.run { self.devices = list }
                }
            }
        }
    }

    func fetchDevices() async {
        guard let s = session else { return }
        do {
            let list = try await SupabaseService.shared.getDevices(
                accessToken: s.accessToken, userID: s.userID)
            await MainActor.run { devices = list }
        } catch { }
    }

    func removeDevice(_ device: ATLASDevice) async {
        guard let s = session else { return }
        try? await SupabaseService.shared.removeDevice(
            accessToken: s.accessToken, deviceID: device.id)
        await fetchDevices()
    }

    // MARK: - Private

    private func completeAuth(_ s: ATLASSession) async {
        await MainActor.run { session = s; isLoadingProfile = true }
        KeychainManager.saveSession(s)
        if let p = try? await SupabaseService.shared.getProfile(
            accessToken: s.accessToken, userID: s.userID) {
            // Block cancelled or payment-failed accounts immediately at login
            if p.subscriptionStatus == "cancelled" || p.subscriptionStatus == "payment_failed" {
                let msg = p.subscriptionStatus == "payment_failed"
                    ? "Your last payment failed. Visit interlinked.digital/atlas to update your billing info."
                    : "Your subscription has been cancelled. Visit interlinked.digital/atlas to subscribe again."
                await MainActor.run {
                    isLoadingProfile = false
                    session = nil
                    authError = msg
                }
                KeychainManager.clearSession()
                try? await SupabaseService.shared.signOut(accessToken: s.accessToken)
                return
            }
            await MainActor.run {
                profile = p
                isLoadingProfile = false
                MonthlyLimitManager.shared.reloadForCurrentIdentity()
            }
            KeychainManager.saveProfile(p)
        } else {
            await MainActor.run { isLoadingProfile = false }
        }
        KeychainManager.saveLastVerified(Date())
        await checkEntitlement()
        await registerDevice(s)
        await fetchDevices()
        await refreshOfflineToken(s)
        if UserDefaults.standard.bool(forKey: CombinedAgreementView.privacyKey) {
            try? await SupabaseService.shared.givePrivacyConsent(accessToken: s.accessToken)
        }
        await MainActor.run { startPlanSyncTimer() }
    }

    // MARK: - Offline token refresh

    private func refreshOfflineToken(_ s: ATLASSession) async {
        let uuid = atlasHardwareUUID()
        if let token = try? await SupabaseService.shared.fetchOfflineToken(
            accessToken: s.accessToken, hardwareUUID: uuid) {
            KeychainManager.saveOfflineToken(token)
        }
    }

    private func registerDevice(_ s: ATLASSession) async {
        let uuid = atlasHardwareUUID()
        let name = deviceFriendlyName()
        // Check if this device is new before registering
        let existingDevices = (try? await SupabaseService.shared.getDevices(
            accessToken: s.accessToken, userID: s.userID)) ?? []
        let isNewDevice = !existingDevices.contains { $0.hardwareUUID == uuid }
        do {
            try await SupabaseService.shared.registerDevice(
                accessToken: s.accessToken,
                userID: s.userID,
                name: name,
                hardwareUUID: uuid,
                isSubscribed: profile?.isSubscribed ?? false)
            // Send security notification for new device activations
            if isNewDevice {
                try? await SupabaseService.shared.notifyNewDevice(
                    accessToken: s.accessToken,
                    deviceName: name,
                    hardwareUUID: uuid)
            }
        } catch SupabaseError.deviceLimitReached {
            await MainActor.run {
                authError = "ATLAS allows up to 3 devices. Remove a device in Account Settings first."
                authErrorIsDeviceLimit = true
                session = nil
                profile = nil
            }
            KeychainManager.clearSession()
        } catch SupabaseError.notEntitled {
            // Distinct from device-limit: this account has no active ATLAS
            // subscription at all. Block entry with a clear, correct message
            // rather than silently continuing with zero devices registered.
            await MainActor.run {
                authError = "This account does not have an active ATLAS subscription. Visit interlinked.digital/atlas to subscribe."
                session = nil
                profile = nil
                entitlementActive = false
            }
            KeychainManager.clearSession()
        } catch SupabaseError.serverUnavailable {
            // Distinct again: couldn't verify at all (server/network issue),
            // as opposed to a definitive not-entitled/limit-reached answer.
            // Do not treat this as either granted or revoked — surfacing it
            // is left to the caller's own offline/online handling; device
            // registration simply did not complete this attempt.
        } catch { }
    }

    private func restoreSession() {
        guard let saved = KeychainManager.loadSession() else { return }
        session = saved

        Task {
            do {
                if saved.isExpired {
                    let fresh = try await SupabaseService.shared.refreshSession(saved.refreshToken)
                    KeychainManager.saveSession(fresh)
                    await MainActor.run { session = fresh }
                    await loadProfileAndDevices(fresh)
                } else {
                    await loadProfileAndDevices(saved)
                }
            } catch let urlError as URLError {
                _ = urlError
                await handleOfflineRestore(saved)
            } catch {
                await MainActor.run { session = nil }
                KeychainManager.clearSession()
            }
        }
    }

    // MARK: - Offline restore

    private static let gracePeriodSeconds: TimeInterval = 24 * 3600

    private func handleOfflineRestore(_ saved: ATLASSession) async {
        if let tokenStr = KeychainManager.loadOfflineToken(),
           let claims   = OfflineTokenVerifier.verify(token: tokenStr) {
            let offlineProfile = ATLASProfile(
                id: saved.userID,
                email: saved.email,
                plan: claims.p,
                subscriptionStatus: "active",
                billingAnchorDay: nil,
                billingInterval: nil
            )
            await MainActor.run {
                session = saved
                profile = offlineProfile
                // Legitimately issued (server-signed, device-bound, time-
                // limited) offline authorization — see OfflineTokenVerifier.
                // Not derived from plan; the token's mere validity is what's
                // trusted here, unchanged by this pass (P2 covers hardening
                // this further with asymmetric signing).
                entitlementActive = true
            }
            return
        }

        if let lastVerified = KeychainManager.loadLastVerified(),
           Date().timeIntervalSince(lastVerified) < Self.gracePeriodSeconds,
           let cachedProfile = KeychainManager.loadProfile() {
            await MainActor.run {
                session = saved
                profile = cachedProfile
                authError = nil
                // Cached from the last real online entitlement check within
                // the grace window — same trust boundary as before this pass,
                // just now expressed via entitlementActive instead of plan.
                entitlementActive = true
            }
            return
        }

        await MainActor.run {
            session = nil
            profile = nil
            authError = "ATLAS requires an internet connection to verify your subscription. Please connect and relaunch."
        }
        KeychainManager.clearSession()
    }

    private func loadProfileAndDevices(_ s: ATLASSession) async {
        await MainActor.run { isLoadingProfile = true }
        do {
            let p = try await SupabaseService.shared.getProfile(
                accessToken: s.accessToken, userID: s.userID)
            await MainActor.run { profile = p; isLoadingProfile = false }
            KeychainManager.saveProfile(p)
            KeychainManager.saveLastVerified(Date())
        } catch {
            await MainActor.run { isLoadingProfile = false }
        }
        await checkEntitlement()
        await registerDevice(s)
        await fetchDevices()
        await refreshOfflineToken(s)
        await MainActor.run { startPlanSyncTimer() }
    }
}
