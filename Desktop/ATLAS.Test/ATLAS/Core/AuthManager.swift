import Foundation
import AppKit

final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    private init() { restoreSession() }

    @Published var session: ATLASSession?
    @Published var profile: ATLASProfile?
    @Published var isLoading = false
    @Published var isLoadingProfile = false
    @Published var authError: String?
    @Published var authErrorIsDeviceLimit = false
    @Published var devices: [ATLASDevice] = []

    private var planSyncTimer: Timer?

    var isSignedIn: Bool { session != nil }
    var isPro: Bool      { profile?.isPro ?? false }
    var isAdvanced: Bool { profile?.isAdvanced ?? false }
    var planLabel: String {
        if isAdvanced { return "Advanced" }
        if isPro      { return "Pro" }
        return "Standard"
    }
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
        do {
            let s = try await SupabaseService.shared.signIn(email: email, password: password)
            await completeAuth(s)
        } catch {
            authError = error.localizedDescription
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

    func signOut() {
        let token  = session?.accessToken
        let userID = session?.userID
        clearLocalSession()                   // update UI immediately
        if let token, let userID {
            Task {
                let uuid = atlasHardwareUUID()
                try? await SupabaseService.shared.removeCurrentDevice(
                    accessToken: token, userID: userID, hardwareUUID: uuid)
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
        session = nil
        profile = nil
        devices = []
        authError = nil
        authErrorIsDeviceLimit = false
        KeychainManager.clearSession()
        KeychainManager.clearOfflineData()
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
        planSyncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self = self, let s = self.session, !s.isExpired else { return }
            Task {
                // Sync profile (plan + subscription status)
                if let p = try? await SupabaseService.shared.getProfile(
                    accessToken: s.accessToken, userID: s.userID) {
                    let changed = p.plan != self.profile?.plan ||
                                  p.subscriptionStatus != self.profile?.subscriptionStatus
                    if changed {
                        await MainActor.run { self.profile = p }
                        KeychainManager.saveProfile(p)
                    }
                }
                // Sync device list
                if let list = try? await SupabaseService.shared.getDevices(
                    accessToken: s.accessToken, userID: s.userID) {
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
            await MainActor.run { profile = p; isLoadingProfile = false }
            KeychainManager.saveProfile(p)
        } else {
            await MainActor.run { isLoadingProfile = false }
        }
        KeychainManager.saveLastVerified(Date())
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
                isPro: profile?.isPro ?? false)
            // Send security notification for new device activations
            if isNewDevice {
                try? await SupabaseService.shared.notifyNewDevice(
                    accessToken: s.accessToken,
                    deviceName: name,
                    hardwareUUID: uuid)
            }
        } catch SupabaseError.deviceLimitReached {
            await MainActor.run {
                let isPro = profile?.isPro == true
                authError = isPro
                    ? "Pro plan limit of 3 devices reached. Remove a device in Account Settings first."
                    : "Your Standard plan allows 1 device. Sign out on your other device first, or upgrade to Pro for up to 3 devices."
                authErrorIsDeviceLimit = !isPro
                session = nil
                profile = nil
            }
            KeychainManager.clearSession()
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

    private static let gracePeriodSeconds: TimeInterval = 7 * 24 * 3600

    private func handleOfflineRestore(_ saved: ATLASSession) async {
        if let tokenStr = KeychainManager.loadOfflineToken(),
           let claims   = OfflineTokenVerifier.verify(token: tokenStr) {
            let offlineProfile = ATLASProfile(
                id: saved.userID,
                email: saved.email,
                plan: claims.p,
                subscriptionStatus: "active"
            )
            await MainActor.run {
                session = saved
                profile = offlineProfile
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
        await registerDevice(s)
        await fetchDevices()
        await refreshOfflineToken(s)
        await MainActor.run { startPlanSyncTimer() }
    }
}
