import SwiftUI
import AppKit
import UserNotifications

// MARK: - Volume info model

private struct VolumeInfo: Identifiable {
    let id       = UUID()
    let name: String
    let total: Int64
    let free: Int64
    let isInternal: Bool

    var used: Int64          { total - free }
    var usedFraction: Double { total > 0 ? min(1, Double(used) / Double(total)) : 0 }

    var freeFormatted:  String { VolumeInfo.fmt(free) }
    var totalFormatted: String { VolumeInfo.fmt(total) }

    private static func fmt(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1024) }
        return String(format: "%.0f GB", gb)
    }
}

private func loadVolumes() -> [VolumeInfo] {
    // Use StorageManager which correctly excludes disk images (DMG/ISO/sparse)
    return StorageManager.shared.availableVolumes().map { vol in
        VolumeInfo(name: vol.displayName, total: vol.totalBytes,
                   free: vol.availableBytes, isInternal: vol.isInternal)
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    var onStartTour: (() -> Void)? = nil

    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var scheme
    @ObservedObject private var appearance  = AppearanceManager.shared
    @ObservedObject private var langMgr     = LanguageManager.shared
    @ObservedObject private var titanCore   = TitanCore.shared
    @ObservedObject private var auth        = AuthManager.shared

    @State private var volumes: [VolumeInfo] = []
    @State private var showSignOutConfirm = false
    @State private var showSupport = false
    @AppStorage("atlas.tourDismissed") private var tourDismissed = false
    @AppStorage("atlas.widgetEnabled") private var widgetEnabled = true
    @State private var gatekeeperFixRunning = false
    @State private var gatekeeperFixResult: String? = nil
    @State private var notificationsEnabled = false
    @State private var notifPermissionDenied = false
    @State private var showTitanMemory = false

    private static let notifKey = "ATLAS.notificationsEnabled"

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    Text("Settings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .background(Color.atlasSeparator)

            ScrollView {
                VStack(spacing: 0) {

                    // ── TITAN CORE™ ───────────────────────────────────
                    sectionHeader("TITAN CORE™")
                    VStack(spacing: 0) {
                        titanToggleRow
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Widget Mode ───────────────────────────────────
                    sectionHeader("Widget Mode")
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(hex: "#7090B8").opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "rectangle.compress.vertical")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "#7090B8"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Widget Mode")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.atlasLabel)
                                Text(widgetEnabled
                                     ? "ATLAS will minimise to a compact widget when idle"
                                     : "ATLAS stays full size — widget mode disabled")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.atlasSubtitle)
                            }
                            Spacer()
                            Toggle("", isOn: $widgetEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .scaleEffect(0.85)
                                .tint(Color(hex: "#7090B8"))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Appearance ────────────────────────────────────
                    Group {
                    // ── Language ──────────────────────────────────────
                    sectionHeader(L(.language))
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(hex: "#7090B8").opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "globe")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "#7090B8"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L(.language))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.atlasLabel)
                                Text("\(langMgr.current.flag) \(langMgr.current.displayName)")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.atlasSubtitle)
                            }
                            Spacer()
                            Picker("", selection: $langMgr.current) {
                                ForEach(ATLASLanguage.allCases) { lang in
                                    Text("\(lang.flag) \(lang.displayName)")
                                        .tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 140)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Appearance ────────────────────────────────────
                    sectionHeader("Appearance")
                    VStack(spacing: 0) {
                        appearanceRow
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Account ───────────────────────────────────────
                    sectionHeader("Account")
                    accountSection
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Support ───────────────────────────────────────
                    sectionHeader("Support")
                    VStack(spacing: 0) {
                        infoRow(
                            icon: "questionmark.circle.fill",
                            iconColor: Color(hex: "#3ECFB2"),
                            title: "Get Help",
                            subtitle: "Contact InterLinked support",
                            action: { showSupport = true }
                        )
                        Divider().padding(.leading, 48)
                        infoRow(
                            icon: "map.fill",
                            iconColor: Color(hex: "#7090B8"),
                            title: "Tour ATLAS",
                            subtitle: "Replay the ATLAS walkthrough",
                            action: {
                                tourDismissed = false
                                dismiss()
                                onStartTour?()
                            }
                        )
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Tools ─────────────────────────────────────────
                    sectionHeader("Tools")
                    VStack(spacing: 0) {
                        // Gatekeeper fix
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(hex: "#F0A030").opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#F0A030"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fix Blocked Plugins")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.atlasLabel)
                                Text(gatekeeperFixResult ?? "Remove macOS security blocks from installed plugins")
                                    .font(.system(size: 11))
                                    .foregroundColor(gatekeeperFixResult != nil ? Color(hex: "#3ECFB2") : Color.atlasSubtitle)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if gatekeeperFixRunning {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 24, height: 24)
                            } else {
                                Button("Fix") {
                                    gatekeeperFixRunning = true
                                    gatekeeperFixResult = nil
                                    Task {
                                        let pwd = KeychainManager.loadPassword() ?? ""
                                        let result = await GatekeeperFixer.fixAllPluginLocations(adminPassword: pwd)
                                        gatekeeperFixRunning = false
                                        if result.fixed.isEmpty && result.failed.isEmpty {
                                            gatekeeperFixResult = "No blocked plugins found."
                                        } else if !result.fixed.isEmpty {
                                            gatekeeperFixResult = "Fixed \(result.fixed.count) plugin(s). Rescan in your DAW."
                                        } else {
                                            gatekeeperFixResult = "Could not fix \(result.failed.count) plugin(s). Try restarting ATLAS."
                                        }
                                    }
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#F0A030"))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color(hex: "#F0A030").opacity(0.12))
                                .cornerRadius(6)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    } // end language/support Group

                    Group {

                    // ── Install Limits ────────────────────────────────
                    sectionHeader("Install Limits")
                    VStack(spacing: 0) {
                        let isPro       = auth.isPro
                        let planColor   = isPro ? Color(hex: "#3ECFB2") : Color(hex: "#7090B8")
                        let monthlyLimit = MonthlyLimitManager.shared
                        let dailyUsed    = monthlyLimit.installsToday
                        let monthlyUsed  = monthlyLimit.installsThisPeriod
                        let monthlyMax   = isPro ? MonthlyLimitManager.proLimit : MonthlyLimitManager.standardMonthlyLimit

                        if !isPro {
                            let dailyMax = MonthlyLimitManager.standardDailyLimit
                            let dailyRem = max(0, dailyMax - dailyUsed)
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(planColor.opacity(0.12))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "sun.max")
                                        .font(.system(size: 12))
                                        .foregroundColor(planColor)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Daily Installations")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(Color.atlasLabel)
                                        Spacer()
                                        Text("\(dailyUsed) / \(dailyMax)")
                                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                            .foregroundColor(dailyRem == 0 ? Color(hex: "#F0A030") : planColor)
                                    }
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3).fill(planColor.opacity(0.15)).frame(height: 4)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(dailyRem == 0 ? Color(hex: "#F0A030") : planColor)
                                                .frame(width: geo.size.width * min(1, Double(dailyUsed) / Double(dailyMax)), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                    Text(dailyRem == 0 ? "Resets at midnight" : "\(dailyRem) remaining today")
                                        .font(.system(size: 10))
                                        .foregroundColor(Color.atlasSubtitle)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            Divider().background(Color.atlasSeparator).padding(.leading, 44)
                        }

                        let monthlyRem = max(0, monthlyMax - monthlyUsed)
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(planColor.opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "calendar")
                                    .font(.system(size: 12))
                                    .foregroundColor(planColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Monthly Installations")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(Color.atlasLabel)
                                    Spacer()
                                    Text("\(monthlyUsed) / \(monthlyMax)")
                                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                        .foregroundColor(monthlyRem == 0 ? Color(hex: "#F0A030") : planColor)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(planColor.opacity(0.15)).frame(height: 4)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(monthlyRem == 0 ? Color(hex: "#F0A030") : planColor)
                                            .frame(width: geo.size.width * min(1, Double(monthlyUsed) / Double(monthlyMax)), height: 4)
                                    }
                                }
                                .frame(height: 4)
                                Text(monthlyRem == 0 ? "Refills on billing date" : "\(monthlyRem) remaining this month")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color.atlasSubtitle)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Notifications ─────────────────────────────────
                    sectionHeader("Notifications")
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(Color(hex: "#E05555").opacity(0.12))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "bell.badge.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color(hex: "#E05555"))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Install & Uninstall Alerts")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.atlasLabel)
                                Text(notifPermissionDenied
                                     ? "Enable in System Settings → Notifications"
                                     : (notificationsEnabled ? "On — you'll be notified when operations finish" : "Off"))
                                    .font(.system(size: 11))
                                    .foregroundColor(notifPermissionDenied
                                                     ? Color(hex: "#F0A030")
                                                     : Color.atlasSubtitle)
                            }
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .scaleEffect(0.85)
                                .tint(Color(hex: "#3ECFB2"))
                                .onChange(of: notificationsEnabled) { enabled in
                                    handleNotifToggle(enabled)
                                }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── Storage ───────────────────────────────────────
                    sectionHeader("Storage")
                    VStack(spacing: 0) {
                        ForEach(Array(volumes.enumerated()), id: \.element.id) { idx, vol in
                            if idx > 0 {
                                Divider().background(Color.atlasSeparator).padding(.leading, 44)
                            }
                            volumeRow(vol)
                        }
                        if volumes.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color.atlasSubtitle)
                                Text("No volumes found")
                                    .font(.system(size: 12))
                                    .foregroundColor(Color.atlasSubtitle)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)

                    // ── About ─────────────────────────────────────────
                    sectionHeader("About")
                    VStack(spacing: 0) {
                        infoRow(
                            icon: "sparkle",
                            iconColor: Color(hex: "#3ECFB2"),
                            title: "ATLAS",
                            subtitle: "ATLAS: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") · by InterLinked®",
                            action: nil
                        )
                        Divider().background(Color.atlasSeparator).padding(.leading, 44)
                        infoRow(
                            icon: "doc.text.fill",
                            iconColor: Color.atlasSubtitle,
                            title: "View Logs",
                            subtitle: "Open install & uninstall log folder",
                            action: { InstallLogger.openLogsInFinder() }
                        )
                    }
                    .atlasCard()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)

                    } // end Group

                    adminSection
                }
                .padding(.top, 12)
            }
        }
        .frame(width: 380, height: 580)
        .atlasBackground()
        .onAppear {
            Task.detached(priority: .userInitiated) {
                let vols = loadVolumes()
                await MainActor.run { volumes = vols }
            }
            Task { await auth.fetchDevices() }
            checkNotificationState()
        }
        .confirmationDialog("Sign out of ATLAS?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again to use ATLAS.")
        }
        .sheet(isPresented: $showSupport) {
            SupportView()
        }
        .sheet(isPresented: $showTitanMemory) {
            TitanMemoryViewer()
        }
        .preferredColorScheme(appearance.override)
    }

    // MARK: - Account section

    @ViewBuilder
    private var adminSection: some View {
        if auth.isAdmin {
            sectionHeader("Admin")
            VStack(spacing: 0) {
                infoRow(
                    icon: "brain.head.profile",
                    iconColor: Color(hex: "#3ECFB2"),
                    title: "TITAN MEMORY™",
                    subtitle: "View all confirmed install patterns",
                    action: { showTitanMemory = true }
                )
            }
            .atlasCard()
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(spacing: 0) {

            // ── Email + plan badge ──────────────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(hex: "#7090B8").opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "person.fill")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#7090B8"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(auth.userEmail.isEmpty ? "—" : auth.userEmail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                    Text("ATLAS \(auth.planLabel) · \(auth.subscriptionStatusLabel)")
                        .font(.system(size: 11))
                        .foregroundColor(auth.subscriptionActive
                                         ? (auth.isPro ? Color(hex: "#F0A030") : Color.atlasSubtitle)
                                         : Color(hex: "#E05555"))
                }
                Spacer()
                Text(auth.planLabel.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(auth.isPro ? Color(hex: "#F0A030") : Color(hex: "#696E7C"))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background((auth.isPro ? Color(hex: "#F0A030") : Color(hex: "#696E7C")).opacity(0.12))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)

            // ── Plan info or subscribe prompts ──────────────────────
            Divider().background(Color.atlasSeparator).padding(.leading, 44)

            if auth.subscriptionActive {
                // Manage account on website
                subscribeRow(
                    icon: "person.crop.circle.badge.checkmark",
                    iconColor: Color(hex: "#3ECFB2"),
                    title: "Manage Account",
                    subtitle: "Billing, devices & plan details",
                    url: "https://interlinked.digital/atlas/account"
                )
                Divider().background(Color.atlasSeparator).padding(.leading, 44)

                if !auth.isPro {
                    subscribeRow(
                        icon: "star.circle.fill",
                        iconColor: Color(hex: "#F0A030"),
                        title: "Upgrade to Pro",
                        subtitle: "Bulk install, uninstall, Smart Storage & more",
                        url: "https://interlinked.digital/atlas/account"
                    )
                    Divider().background(Color.atlasSeparator).padding(.leading, 44)
                }
            } else {
                // No active sub — show subscribe options
                subscribeRow(
                    icon: "star.fill",
                    iconColor: Color(hex: "#7090B8"),
                    title: "Subscribe to Standard",
                    subtitle: "$14.99/mo · Basic installations · 1 device",
                    url: SupabaseConfig.stripeStandardURL
                )
                Divider().background(Color.atlasSeparator).padding(.leading, 44)
                subscribeRow(
                    icon: "star.circle.fill",
                    iconColor: Color(hex: "#F0A030"),
                    title: "Subscribe to Pro",
                    subtitle: "$29.99/mo · All features · up to 3 devices",
                    url: SupabaseConfig.stripeProURL
                )
                Divider().background(Color.atlasSeparator).padding(.leading, 44)
            }

            // ── Devices ────────────────────────────────────────────
            if !auth.devices.isEmpty {
                ForEach(auth.devices) { device in
                    let isCurrent = device.hardwareUUID == atlasHardwareUUID()
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: "#3ECFB2").opacity(isCurrent ? 0.15 : 0.07))
                                .frame(width: 28, height: 28)
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 11))
                                .foregroundColor(isCurrent ? Color(hex: "#3ECFB2") : Color.atlasSubtitle)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(device.deviceName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color.atlasLabel)
                                if isCurrent {
                                    Text("this mac")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(Color(hex: "#3ECFB2"))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Color(hex: "#3ECFB2").opacity(0.12))
                                        .cornerRadius(3)
                                }
                            }
                            Text("Last seen \(formattedDate(device.lastSeen))")
                                .font(.system(size: 10))
                                .foregroundColor(Color.atlasSubtitle)
                        }
                        Spacer()
                        if !isCurrent {
                            Button {
                                Task { await auth.removeDevice(device) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(Color(hex: "#E05555").opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("Remove this device")
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    Divider().background(Color.atlasSeparator).padding(.leading, 44)
                }
            }

            // ── Manage subscription ────────────────────────────────
            if auth.subscriptionActive && !auth.isLoading {
                Button {
                    NSWorkspace.shared.open(URL(string: "https://www.interlinked.digital/atlas/account")!)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: "#696E7C").opacity(0.08))
                                .frame(width: 28, height: 28)
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#696E7C"))
                        }
                        Text("Manage Subscription")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#696E7C"))
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "#696E7C").opacity(0.5))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().background(Color.atlasSeparator).padding(.leading, 44)
            }

            // ── Sign out ───────────────────────────────────────────
            Button {
                showSignOutConfirm = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(hex: "#E05555").opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#E05555"))
                    }
                    Text("Sign Out")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#E05555"))
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .buttonStyle(.plain)
        }
        .atlasCard()
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return rel.localizedString(for: date, relativeTo: Date())
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            let rel = RelativeDateTimeFormatter()
            rel.unitsStyle = .short
            return rel.localizedString(for: date, relativeTo: Date())
        }
        return "recently"
    }

    @ViewBuilder
    private func subscribeRow(icon: String, iconColor: Color, title: String, subtitle: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(iconColor.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - TITAN CORE™ toggle row

    @ViewBuilder
    private var titanToggleRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: "#3ECFB2").opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("TITAN CORE™")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.atlasLabel)
                    Text("ALL PLANS")
                        .font(.system(size: 8, weight: .black))
                        .tracking(0.8)
                        .foregroundColor(Color(hex: "#3ECFB2"))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Color(hex: "#3ECFB2").opacity(0.12))
                        .cornerRadius(4)
                }
                Text("Always active — pre-flight, smart recovery, verification")
                    .font(.system(size: 11))
                    .foregroundColor(Color.atlasSubtitle)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: "#3ECFB2"))
                    .frame(width: 6, height: 6)
                Text("ON")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#3ECFB2"))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: "#3ECFB2").opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Appearance row

    @ViewBuilder
    private var appearanceRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(hex: "#F0A030").opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "#F0A030"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Theme")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.atlasLabel)
                Text(appearance.override == nil
                     ? "Following system"
                     : (appearance.override == .dark ? "Dark" : "Light"))
                    .font(.system(size: 11))
                    .foregroundColor(Color.atlasSubtitle)
            }
            Spacer()
            AppearanceToggle()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Volume row

    @ViewBuilder
    private func volumeRow(_ vol: VolumeInfo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill((vol.isInternal ? Color(hex: "#7090B8") : Color(hex: "#F0A030")).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: vol.isInternal ? "internaldrive.fill" : "externaldrive.fill")
                    .font(.system(size: 12))
                    .foregroundColor(vol.isInternal ? Color(hex: "#7090B8") : Color(hex: "#F0A030"))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vol.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                    Spacer()
                    Text("\(vol.freeFormatted) free")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.atlasSubtitle)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.atlasSeparator)
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(vol.usedFraction > 0.9
                                  ? Color(hex: "#E05555")
                                  : vol.isInternal ? Color(hex: "#7090B8") : Color(hex: "#F0A030"))
                            .frame(width: max(4, geo.size.width * vol.usedFraction), height: 4)
                    }
                }
                .frame(height: 4)
                Text("\(vol.totalFormatted) total")
                    .font(.system(size: 10))
                    .foregroundColor(Color.atlasSubtitle.opacity(0.6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Notification helpers

    private func checkNotificationState() {
        let saved = UserDefaults.standard.bool(forKey: Self.notifKey)
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let granted = settings.authorizationStatus == .authorized ||
                              settings.authorizationStatus == .provisional
                notifPermissionDenied = settings.authorizationStatus == .denied
                notificationsEnabled  = granted && saved
            }
        }
    }

    private func handleNotifToggle(_ enabled: Bool) {
        guard !notifPermissionDenied else {
            // Bounce user to System Settings since permission was explicitly denied
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            notificationsEnabled = false
            return
        }
        if enabled {
            UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async {
                    notificationsEnabled = granted
                    notifPermissionDenied = !granted
                    UserDefaults.standard.set(granted, forKey: Self.notifKey)
                }
            }
        } else {
            UserDefaults.standard.set(false, forKey: Self.notifKey)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.atlasSubtitle)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private func infoRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        action: (() -> Void)?
    ) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundColor(iconColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.atlasLabel)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color.atlasSubtitle)
                }
                Spacer()
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.atlasSubtitle.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}
