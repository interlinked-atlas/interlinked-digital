import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var logger = Logger()
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var queue = InstallQueue.shared
    @StateObject private var updateChecker = UpdateChecker.shared
    @State private var isTargeted = false
    @State private var needsAgreements      = !UserDefaults.standard.bool(forKey: CombinedAgreementView.tosKey)
                                           || !UserDefaults.standard.bool(forKey: CombinedAgreementView.privacyKey)
    @State private var needsPasswordSetup   = false
    // Re-check real permission state on every launch — not just the onboarding flag.
    // FDA + Accessibility are fast sync checks. Automation is async; we use the stored
    // confirmation flag as an initial proxy then verify below.
    @State private var needsPermissionsSetup: Bool = {
        !PermissionsManager.hasCompletedOnboarding ||
        !PermissionsManager.hasAccessibility ||
        !PermissionsManager.hasFullDiskAccess ||
        !PermissionsManager.automationManuallyConfirmed
    }()
    // Live permission state for the in-app warning banner shown after onboarding.
    @State private var livePermsMissing: [String] = []
    @State private var permCheckTimer: Timer? = nil
    @State private var unsupportedExtension: String? = nil
    @State private var showHistory = false
    @State private var rollingBack: InstallRecord? = nil
    @State private var rollbackInProgress = false
    @State private var rollbackProgress: Double = 0.0
    @State private var rollbackStep: String = ""
    @State private var rollbackTask: Task<Void, Never>? = nil
    @State private var rollbackQueue: [InstallRecord] = []
    @State private var rollbackQueueTotal: Int = 0
    @State private var rollbackQueueDone: Int = 0
    @State private var batchRollbackResults: [(InstallRecord, RollbackResult)] = []
    @State private var showRosetta = false
    @State private var uninstallResult: RollbackResult? = nil
    @State private var showDropZone = true
    @State private var showCancelConfirm = false
    @State private var showTrashEmptiedAlert = false
    @State private var trashEmptiedProductName = ""
    @State private var queueTask: Task<Void, Never>? = nil
    @State private var pluginScanResults: [PluginCheckResult] = []
    @State private var showPluginScan = false
    @State private var pendingDemoAlerts: [DemoAlert] = []
    @State private var showDemoAlert = false
    @State private var preInstallWarnings: [PreInstallWarning] = []
    @ObservedObject private var zipBroker = ZIPPasswordBroker.shared
    @ObservedObject private var widgetState  = WidgetStateManager.shared
    @ObservedObject private var appearance   = AppearanceManager.shared
    @ObservedObject private var titanCore    = TitanCore.shared
    @ObservedObject private var auth         = AuthManager.shared
    @ObservedObject private var monthlyLimit  = MonthlyLimitManager.shared
    @ObservedObject private var titanVScan      = TitanVScan.shared
    @ObservedObject private var fileShare       = FileShareEngine.shared
    @State private var showVScanSheet           = false
    @State private var pendingVScanURL:         URL? = nil
    @State private var pendingVScanResult:      VScanResult? = nil
    @State private var showFileShare          = false
    @State private var showFileShareUpload    = false
    @State private var widgetTimer: Task<Void, Never>? = nil
    @State private var showSettings  = false
    @State private var showAbout     = false
    @State private var showUpgrade   = false
    @State private var upgradeFeature = ""
    @State private var showStorageSelection = false
    @State private var pendingInstallURL: URL? = nil
    @State private var pendingScanResult: ScanResult? = nil
    @AppStorage("atlasGreetingShown") private var greetingShown = false
    @AppStorage("atlas.tourDismissed") private var tourDismissed = false
    @State private var showTour = false
    @State private var feedbackProductName: String? = nil
    @State private var feedbackRecord: InstallRecord? = nil
    @State private var showFeedbackPrompt = false
    private var feedbackTimer: Timer? = nil
    @State private var showAtlasSelfInstallAlert = false
    // TITAN CORE™ mission state
    @State private var activeTitanMission: TitanMission? = nil
    @State private var showTitanMission            = false
    @State private var showTitanNoInstructions     = false
    @State private var showMultipleProductsGate    = false
@State private var titanNoInstrFiles: [String] = []
    @State private var titanPreScanMount: String = ""  // ISO pre-scan mount point — unmounted on dismiss
    @State private var titanMountPoint: String = ""
    @State private var titanSourceURL: URL? = nil

    var body: some View {
        Group {
            if needsAgreements {
                CombinedAgreementView { needsAgreements = false }
            } else if !auth.isSignedIn {
                AuthView()
            } else if auth.isLoadingProfile {
                // Profile fetching — brief spinner so subscription gate doesn't flash
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        AtlasStarView(size: 52, isAnimating: true)
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            } else if !auth.subscriptionActive {
                SubscriptionRequiredView()
            } else if needsPermissionsSetup {
                PermissionsSetupView {
                    needsPermissionsSetup = false
                    needsPasswordSetup = !KeychainManager.hasPassword()
                }
            } else if needsPasswordSetup {
                PasswordSetupView { needsPasswordSetup = false }
                    .atlasBackground()
            } else {
                mainLayout
            }
        }
        .background(widgetState.isWidgetMode ? Color.clear : nil)
        .preferredColorScheme(appearance.override)
        .sheet(isPresented: $showDemoAlert, onDismiss: {
            pendingDemoAlerts.removeFirst()
            if !pendingDemoAlerts.isEmpty { showDemoAlert = true }
        }) {
            if let alert = pendingDemoAlerts.first {
                DemoAlertView(alert: alert) { showDemoAlert = false }
            }
        }
        .onChange(of: pendingDemoAlerts.count) { count in
            if count > 0 && !showDemoAlert { showDemoAlert = true }
        }
        // ZIP password prompt — suspends install until user enters password or cancels
        .sheet(item: $zipBroker.pendingRequest) { request in
            ZIPPasswordView(request: request)
                .interactiveDismissDisabled(true)
        }
        // When user cancels the password prompt, stop the active install and go home
        .onChange(of: zipBroker.pendingRequest == nil) { _ in
            // The broker handles resuming the continuation; nothing else needed here
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showUpgrade) {
            UpgradeView(feature: upgradeFeature) { showUpgrade = false }
        }
        // Standard plan — let user pick which product to install when multiple are found
        .sheet(isPresented: $showMultipleProductsGate) {
            if let mission = activeTitanMission {
                let installable = mission.steps.filter {
                    if case .installPkg = $0.action { return true }
                    return false
                }
                StandardMultipleProductsView(
                    installableSteps: installable,
                    onInstallOne: { step in installOneFromMultiple(step: step) },
                    onCancel: {
                        showMultipleProductsGate = false
                        activeTitanMission = nil
                        detachTitanPreScanMount()
                        appState.reset()
                        withAnimation { showDropZone = true }
                    }
                )
            }
        }
        .sheet(isPresented: $showStorageSelection) {
            if let scanResult = pendingScanResult, let url = pendingInstallURL {
                StorageSelectionView(
                    installerName: url.lastPathComponent,
                    estimatedBytes: scanResult.estimatedPayloadBytes
                ) { volume, destURL in
                    showStorageSelection = false
                    // Log the storage decision to TITAN CORE™
                    TitanCore.shared.recordStorageDecision(
                        storageType: volume.isExternal ? "External Storage" : "Internal Drive",
                        mountPath: destURL.path,
                        packageType: typeLabel(InstallerClassifier.classify(url: url)),
                        estimatedBytes: scanResult.estimatedPayloadBytes
                    )
                    // Route install to selected volume
                    InstallEngine.storageRoot = volume.isBoot ? nil : volume.url
                    beginInstall(url: url)
                    pendingInstallURL  = nil
                    pendingScanResult  = nil
                } onCancel: {
                    showStorageSelection = false
                    pendingInstallURL    = nil
                    pendingScanResult    = nil
                }
            }
        }
        .alert("Cannot Install ATLAS", isPresented: $showAtlasSelfInstallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("ATLAS cannot install or uninstall itself. Please drag a different installer file.")
        }
        .alert("Files Permanently Deleted", isPresented: $showTrashEmptiedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(trashEmptiedProductName) cannot be recovered — its files were in the Trash but have since been permanently deleted.\n\nTo restore it, you'll need to reinstall from the original installer.")
        }
    }

    var mainLayout: some View {
        ZStack {
            if !widgetState.isWidgetMode {
                // Main content — always full window width, never resizes for history
                mainView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minWidth: 420, minHeight: 360)
                    .atlasBackground()

                // History panel slides in as a trailing overlay — window never resizes.
                // A thin scrim behind it dims the main content slightly for focus.
                if showHistory {
                    HStack(spacing: 0) {
                        // Tap-to-close scrim
                        Color.black.opacity(0.18)
                            .onTapGesture { withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { showHistory = false } }
                        HistoryPanelView(
                            store: historyStore,
                            logger: logger,
                            onClose: { withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) { showHistory = false } },
                            onRollback: { record in
                                if !Features.rollback {
                                    upgradeFeature = "Uninstall & Rollback"
                                    showUpgrade = true
                                } else {
                                    beginBatchUninstall(records: [record])
                                }
                            },
                            onRestore: { record in
                                if !Features.restore {
                                    upgradeFeature = "Restore"
                                    showUpgrade = true
                                } else {
                                    beginRestore(record: record)
                                }
                            },
                            onBatchRollback: { records in
                                if !Features.rollback {
                                    upgradeFeature = "Uninstall & Rollback"
                                    showUpgrade = true
                                } else {
                                    beginBatchUninstall(records: records)
                                }
                            }
                        )
                        .shadow(color: .black.opacity(0.25), radius: 16, x: -4, y: 0)
                    }
                    .transition(.move(edge: .trailing))
                    .zIndex(50)
                    .animation(.spring(response: 0.32, dampingFraction: 0.84), value: showHistory)
                }
            }

            // Tour overlay — injected via overlayPreferenceValue below


            // Resume banner — shown when waiting queue items survived a crash/force-quit
            if !queue.pendingResumeURLs.isEmpty {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resume previous installs?")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("\(queue.pendingResumeURLs.count) item\(queue.pendingResumeURLs.count == 1 ? "" : "s") from last session")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        Spacer()
                        Button("Resume") {
                            queue.resumePersistedQueue()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Button("Dismiss") {
                            queue.clearPersistedQueue()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 12))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: queue.pendingResumeURLs.isEmpty)
            }

            // Post-install feedback prompt (bottom-right, 60s after success)
            if showFeedbackPrompt, let product = feedbackProductName {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        InstallFeedbackPrompt(
                            productName: product,
                            steps: [],
                            hostsEntries: [],
                            installLog: "",
                            installRecord: feedbackRecord,
                            historyStore: historyStore,
                            onDismiss: {
                                withAnimation { showFeedbackPrompt = false }
                            }
                        )
                        .padding(.trailing, 20)
                        .padding(.bottom, 56)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(998)
                .animation(.spring(response: 0.4, dampingFraction: 0.78), value: showFeedbackPrompt)
            }
        }
        .onChange(of: historyStore.records.isEmpty) { isEmpty in
            if isEmpty { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showHistory = false } }
        }
        .onChange(of: rollbackInProgress) { inProgress in
            if inProgress { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showHistory = false } }
        }
        .onChange(of: widgetState.idleCollapseRequested) { requested in
            guard requested else { return }
            widgetState.idleCollapseRequested = false
            // Only collapse if the app is truly idle (no install, no queue, drop zone visible)
            if isIdle { enterWidgetMode() }
        }
        .onChange(of: appState.pendingOpenURLs) { urls in
            guard !urls.isEmpty else { return }
            appState.pendingOpenURLs = []
            handleFilesDrop(urls: urls)
        }
        .onOpenURL { url in
            handleFilesDrop(urls: [url])
        }
        .onAppear {
            // Defer Keychain access until main app appears — avoids system prompt at launch
            if !needsPasswordSetup {
                needsPasswordSetup = !KeychainManager.hasPassword()
            }
            widgetState.startIdleMonitoring()
            startPermissionPolling()
            if !tourDismissed {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    showTour = true
                }
            }
            // Check for app update in background — non-blocking
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                updateChecker.check()
            }
        }
        .onDisappear {
            widgetState.stopIdleMonitoring()
            stopPermissionPolling()
        }
        .task {
            // Automation check is slow (spawns osascript) — run non-blocking.
            // If not granted, send back to permissions setup screen.
            PermissionsManager.checkAutomationPermission { granted in
                if granted {
                    PermissionsManager.automationManuallyConfirmed = true
                } else if !PermissionsManager.automationManuallyConfirmed {
                    needsPermissionsSetup = true
                }
                checkLivePermissions()
            }
        }
        // Resolve tour anchors into concrete CGRects and show tour overlay
        .overlayPreferenceValue(TourAnchorKey.self) { anchors in
            if showTour && !widgetState.isWidgetMode {
                GeometryReader { proxy in
                    let frames = anchors.mapValues { proxy[$0] }
                    TourView(isShowing: $showTour,
                             frames: frames,
                             containerSize: proxy.size)
                        .transition(.opacity)
                }
            }
        }
    }

    var mainView: some View {
        VStack(spacing: 0) {
            titleBar
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // ── Update available banner ───────────────────────────────────
            if updateChecker.showBanner, let info = updateChecker.updateInfo {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ATLAS \(info.version) is available")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                        if !info.releaseNotes.isEmpty {
                            Text(info.releaseNotes)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#3ECFB2").opacity(0.7))
                        }
                    }
                    Spacer()
                    Button {
                        updateChecker.openDownload()
                    } label: {
                        Text("Download")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "#0A0A0B"))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color(hex: "#3ECFB2"))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    Button { updateChecker.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#3ECFB2").opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color(hex: "#3ECFB2").opacity(0.08))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color(hex: "#3ECFB2").opacity(0.2)), alignment: .bottom)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Plan change notice ────────────────────────────────────────
            if let notice = auth.planChangeNotice {
                HStack(spacing: 10) {
                    Image(systemName: auth.isPro ? "star.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(auth.isPro ? Color(hex: "#F0A030") : Color(hex: "#8890B0"))
                    Text(notice)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(auth.isPro ? Color(hex: "#F0A030") : Color(hex: "#8890B0"))
                    Spacer()
                    Button { auth.planChangeNotice = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(hex: "#696E7C"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(auth.isPro ? Color(hex: "#F0A030").opacity(0.08) : Color(hex: "#1A1D2E"))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(auth.isPro ? Color(hex: "#F0A030").opacity(0.2) : Color(hex: "#2A2D3E"), lineWidth: 1))
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation { auth.planChangeNotice = nil }
                    }
                }
            }

            // ── Payment failed banner ─────────────────────────────────────
            if auth.profile?.subscriptionStatus == "payment_failed" {
                paymentFailedBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // ── Live permission warning banner ────────────────────────────
            if !livePermsMissing.isEmpty {
                permissionsBanner
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Inline mission view replaces the scroll area during TITAN installs
            if showTitanMission, let mission = activeTitanMission {
                TitanMissionView(
                    mission: mission,
                    adminPassword: KeychainManager.loadPassword() ?? "",
                    onDone: {
                        if let m = activeTitanMission, m.isComplete {
                            saveTitanRecord(mission: m)
                        }
                        showTitanMission = false
                        activeTitanMission = nil
                        appState.reset()
                        detachTitanPreScanMount()
                        withAnimation { showDropZone = true }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {

            ScrollView {
                VStack(spacing: 16) {

                    // Greeting shown once on very first launch only
                    if isIdle && !greetingShown {
                        Text("What are we installing today?")
                            .font(.system(size: 14, weight: .light))
                            .tracking(0.4)
                            .foregroundStyle(Color.atlasTertiary)
                            .padding(.top, 6)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Queue star (each queue row has its own progress bar)
                    if queue.isProcessing {
                        InstallingStarView()
                            .padding(.vertical, 8)
                            .transition(.opacity.combined(with: .scale))
                    }

                    // Futuristic install overlay for single-file installs
                    let isSingleInstall = (
                        appState.phase == .installing  ||
                        appState.phase == .processing  ||
                        appState.phase == .verifying   ||
                        appState.phase == .cleanup
                    ) && !queue.isProcessing

                    if isSingleInstall {
                        ATLASInstallOverlayView(
                            appState: appState,
                            logger:   logger,
                            fileName: appState.selectedFileURL?.lastPathComponent ?? ""
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    } else if !queue.isProcessing {
                        statusBar
                        progressBar
                    }
                    unsupportedWarning
                    rollbackBanner
                    mainContent

                    if showRosetta && RosettaEngine.isAppleSilicon {
                        RosettaView(logger: logger) {
                            withAnimation { showRosetta = false }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            } // end else (not showTitanMission)

            bottomBar
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(onStartTour: {
                // Wait for the sheet dismiss animation to finish before showing tour
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    showTour = true
                }
            })
        }
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        let busy = queue.isProcessing || rollbackInProgress
            || appState.phase == .installing || appState.phase == .processing
            || appState.phase == .verifying  || appState.phase == .cleanup
        return HStack(spacing: 0) {
            // Settings — disabled while installing/uninstalling
            BottomBarIconButton(icon: "gearshape", tooltip: busy ? "Unavailable during install" : "Settings") {
                showSettings = true
            }
            .disabled(busy)
            .opacity(busy ? 0.3 : 1)
            .tourAnchor("settings")

            // Logs — disabled while installing/uninstalling
            BottomBarIconButton(icon: "doc.text", tooltip: busy ? "Unavailable during install" : "Open Logs in Finder") {
                InstallLogger.openLogsInFinder()
            }
            .disabled(busy)
            .opacity(busy ? 0.3 : 1)

            // TITAN CORE™ live action indicator (Pro only, shown while active)
            if titanCore.isActive && !titanCore.currentAction.isEmpty {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.48)
                        .tint(Color.atlasAccent)
                    Text(titanCore.currentAction)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.atlasAccent)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.atlasAccent.opacity(0.07))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.atlasAccent.opacity(0.20), lineWidth: 0.75))
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .padding(.leading, 4)
            }

            Spacer()

            // Widget mode button — disabled while installing/uninstalling
            if Features.widget {
                BottomBarIconButton(icon: "rectangle.compress.vertical", tooltip: busy ? "Unavailable during install" : "Minimise to widget") {
                    enterWidgetMode()
                }
                .disabled(busy)
                .opacity(busy ? 0.3 : 1)
                .tourAnchor("widget")
            } else {
                BottomBarIconButton(icon: "rectangle.compress.vertical", tooltip: "Widget — Pro only") {
                    // show pro upsell
                }
                .opacity(0.3)
                .tourAnchor("widget")
            }

            // Appearance toggle — disabled while installing/uninstalling
            AppearanceToggle()
                .disabled(busy)
                .opacity(busy ? 0.3 : 1)
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.atlasDeepBG)
        .overlay(alignment: .top) {
            Color.atlasBorderSubtle.frame(height: 0.5)
        }
    }

    // MARK: - Permissions banner

    var paymentFailedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "#E05555"))
            Text("Payment failed — update your billing to keep access.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "#E05555"))
            Spacer()
            Button("Update →") {
                if let url = URL(string: "https://www.interlinked.digital/atlas/account") {
                    NSWorkspace.shared.open(url)
                }
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(hex: "#E05555"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#E05555").opacity(0.12))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color(hex: "#E05555").opacity(0.3), lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "#E05555").opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(hex: "#E05555").opacity(0.25), lineWidth: 1))
    }

    var permissionsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundColor(Color(hex: "#F0A030"))
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text("Permission\(livePermsMissing.count == 1 ? "" : "s") required: \(livePermsMissing.joined(separator: ", "))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F0A030"))
                Text("Installs will fail without these. Tap to fix.")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#C8A060"))
            }

            Spacer()

            Button("Fix →") {
                needsPermissionsSetup = true
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(Color(hex: "#F0A030"))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(hex: "#F0A030").opacity(0.12))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7)
                .stroke(Color(hex: "#F0A030").opacity(0.3), lineWidth: 1))
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: "#F0A030").opacity(0.06))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(hex: "#F0A030").opacity(0.25), lineWidth: 1))
        .animation(.easeInOut(duration: 0.3), value: livePermsMissing)
    }

    // Checks all three permissions and updates livePermsMissing.
    // Called on appear and every 5 seconds while in the main view.
    private func checkLivePermissions() {
        var missing: [String] = []
        if !PermissionsManager.hasFullDiskAccess  { missing.append("Full Disk Access") }
        if !PermissionsManager.hasAccessibility   { missing.append("Accessibility") }
        // Automation is async — use confirmation flag as proxy
        if !PermissionsManager.automationManuallyConfirmed { missing.append("Automation") }
        withAnimation { livePermsMissing = missing }
    }

    private func startPermissionPolling() {
        checkLivePermissions()
        permCheckTimer?.invalidate()
        permCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            checkLivePermissions()
            // Also verify automation for real (async) and clear flag if it passes
            PermissionsManager.checkAutomationPermission { granted in
                if granted && !PermissionsManager.automationManuallyConfirmed {
                    PermissionsManager.automationManuallyConfirmed = true
                }
                checkLivePermissions()
            }
        }
    }

    private func stopPermissionPolling() {
        permCheckTimer?.invalidate()
        permCheckTimer = nil
    }

    // MARK: - Title bar

    var titleBar: some View {
        let busy = queue.isProcessing || rollbackInProgress
            || appState.phase == .installing || appState.phase == .processing
            || appState.phase == .verifying  || appState.phase == .cleanup
        return HStack(spacing: 12) {
            // Logo + ATLAS name — tap opens About
            Button { showAbout = true } label: {
                HStack(spacing: 9) {
                    LiquidMetalView(size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        AtlasTitleText(size: 20, tracking: 5)
                        Text("by InterLinked©")
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundStyle(Color.atlasTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("About ATLAS")

            // TITAN CORE™ active badge
            if titanCore.isActive {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.atlasAccent)
                        .frame(width: 5, height: 5)
                        .shadow(color: Color.atlasAccent.opacity(0.6), radius: 3)
                    Text("TITAN CORE™")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.atlasAccent)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.atlasAccent.opacity(0.07))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.atlasAccent.opacity(0.22), lineWidth: 0.75))
                .transition(.opacity.combined(with: .scale(scale: 0.85)))
                .tourAnchor("titanCore")
            }

            // Invisible anchor for TITAN CORE™ tour step (always registered)
            Color.clear.frame(width: 1, height: 1).tourAnchor("titanCore")

            Spacer()

            HStack(spacing: 5) {
                AtlasLabelButton(
                    icon: "clock",
                    label: "History",
                    isActive: showHistory
                ) {
                    withAnimation(.atlasSpring) { showHistory.toggle() }
                }
                .disabled(busy)
                .opacity(busy ? 0.3 : 1)
                .tourAnchor("history")

                if queue.isProcessing || appState.phase == .installing ||
                   appState.phase == .processing || rollbackInProgress {
                    AtlasLabelButton(icon: "stop.circle", label: "Cancel") {
                        showCancelConfirm = true
                    }
                } else if !isIdle {
                    AtlasLabelButton(icon: "arrow.counterclockwise", label: "Reset") {
                        resetAll()
                    }
                }
            }
            .confirmationDialog(
                L(.cancelConfirmTitle),
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button(L(.cancelConfirmStop), role: .destructive) { performCancel() }
                Button(L(.cancelConfirmContinue), role: .cancel) {}
            } message: {
                Text(L(.cancelConfirmMessage))
            }
        }
    }

    // MARK: - Status bar

    @ViewBuilder
    var statusBar: some View {
        if appState.phase != .idle || !isIdle {
            HStack(spacing: 10) {
                statusDot
                Text(appState.statusMessage)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color.atlasLabel)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.atlasPanelBG)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75)
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        }
    }

    @ViewBuilder
    var statusDot: some View {
        switch appState.phase {
        case .success:
            Circle().fill(Color(hex: "#2ECC8A"))
                .shadow(color: Color(hex: "#2ECC8A").opacity(0.55), radius: 4)
                .frame(width: 7, height: 7)
        case .failure:
            Circle().fill(Color(hex: "#E05555"))
                .shadow(color: Color(hex: "#E05555").opacity(0.55), radius: 4)
                .frame(width: 7, height: 7)
        case .installing, .processing:
            Circle().fill(Color.atlasAccent)
                .shadow(color: Color.atlasAccent.opacity(0.60), radius: 4)
                .frame(width: 7, height: 7)
        default:
            Circle().fill(Color.atlasTertiary).frame(width: 7, height: 7)
        }
    }

    // MARK: - Progress bar

    @ViewBuilder
    var progressBar: some View {
        // When the queue is active, each row has its own bar — suppress the global one.
        if !queue.isProcessing {
            let active = appState.phase == .installing ||
                         appState.phase == .processing ||
                         appState.phase == .classifying
            if active {
                // progress == 0 → indeterminate animated bar (classifying, early install)
                // progress > 0  → determinate fill bar
                ATLASProgressBar(
                    progress: appState.progress,
                    stepLabel: appState.progressStep.isEmpty && appState.phase == .classifying
                        ? "Classifying installer…"
                        : appState.progressStep
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    var mainContent: some View {
        // Standard plan: pending files ready to continue after lock expires
        if !auth.isPro && monthlyLimit.hasPendingFiles && !monthlyLimit.isLocked && showDropZone {
            pendingFilesPanel
        }

        if showDropZone && !rollbackInProgress {
            if !auth.isPro && monthlyLimit.isLocked {
                monthlyLimitLockedZone
            } else {
                // Standard: show remaining installs counter while not locked
                if !auth.isPro {
                    let rem = monthlyLimit.remaining
                    if rem < MonthlyLimitManager.standardDailyLimit {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("\(rem) install\(rem == 1 ? "" : "s") remaining today")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("Standard")
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(0.3)
                                .foregroundStyle(Color(hex: "#7090B8"))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#7090B8").opacity(0.09))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color(hex: "#7090B8").opacity(0.25), lineWidth: 0.75))
                        }
                        .foregroundStyle(Color.atlasSubtitle)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.atlasPanelBG)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.atlasBorderSubtle, lineWidth: 0.75))
                    }
                }

                DropZoneView(isTargeted: $isTargeted, isQueuing: queue.isProcessing) { urls in
                    unsupportedExtension = nil
                    handleFilesDrop(urls: urls)
                } onUnsupported: { ext in
                    unsupportedExtension = ext
                }
                .tourAnchor("dropZone")

                // FileSharing panel — Coming Soon
                if Features.isPro {
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.and.arrow.up")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#525260"))
                        Text("File Sharing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#525260"))
                        Spacer()
                        Text("Coming Soon")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Color(hex: "#3ECFB2"))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color(hex: "#3ECFB2").opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(Color(hex: "#3ECFB2").opacity(0.2), lineWidth: 0.75))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.75))
                }
            }
        }

        // Pre-install system warnings (non-blocking — dismissed automatically when install starts)
        ForEach(preInstallWarnings, id: \.message) { warning in
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "#F0A030"))
                    .font(.system(size: 12))
                Text(warning.message)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C8A060"))
                    .lineLimit(2)
                Spacer()
                Button { preInstallWarnings.removeAll { $0.message == warning.message } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#696E7C"))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(hex: "#1A1200"))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(hex: "#F0A030").opacity(0.25), lineWidth: 1))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .transition(.opacity)
        }

        if queue.hasItems {
            QueueView(
                queue: queue,
                onStartQueue: { startQueue() },
                onRemove: { id in queue.remove(id: id) },
                onRetry: { id in queue.retrySingle(id: id) }
            )
        }

        if appState.phase == .scanning { scanningIndicator }

        if appState.phase == .scanned,
           let scanResult = appState.scanResult,
           !queue.hasItems {
            ScanResultView(
                result: scanResult,
                onInstall: { beginInstallFromScan(url: scanResult.fileURL, scanResult: scanResult) },
                onCancel: {
                    appState.reset()
                    logger.clear()
                    withAnimation { showDropZone = true }
                },
                onShare: nil
            )
            .tourAnchor("scanResult")
            .sheet(isPresented: $fileShare.showDevicePicker) {
                if let pendingURL = fileShare.pendingUploadURL {
                    DevicePickerView(fileURL: pendingURL, arch: fileShare.pendingArch) {
                        fileShare.showDevicePicker = false
                        fileShare.pendingUploadURL = nil
                        fileShare.pendingArch = nil
                        Task { await fileShare.loadFiles() }
                        showFileShare = true
                    }
                    .padding(20)
                    .background(Color(hex: "#080809"))
                }
            }
            .sheet(isPresented: $showVScanSheet) {
                if let vsResult = pendingVScanResult, let url = pendingVScanURL {
                    TitanVScanView(
                        result: vsResult,
                        onProceed: {
                            showVScanSheet = false
                            pendingVScanURL = nil
                            pendingVScanResult = nil
                            beginInstall(url: url)
                        },
                        onQuarantine: {
                            let types  = vsResult.threats.map(\.type.rawValue)
                            let names  = vsResult.threats.map(\.name)
                            let notes  = vsResult.threats.map(\.detail).joined(separator: "\n")
                            _ = QuarantineManager.shared.quarantine(
                                fileURL: url,
                                verdict: vsResult.verdict.rawValue,
                                threatTypes: types,
                                threatNames: names,
                                notes: notes
                            )
                            showVScanSheet = false
                            pendingVScanURL = nil
                            pendingVScanResult = nil
                            appState.reset(); logger.clear()
                            withAnimation { showDropZone = true }
                            ATLASNotification.send(
                                title: "TITAN VSCAN™ — Quarantined",
                                body: "\(url.lastPathComponent) moved to ATLAS Quarantine."
                            )
                        },
                        onDelete: {
                            try? FileManager.default.removeItem(at: url)
                            showVScanSheet = false
                            pendingVScanURL = nil
                            pendingVScanResult = nil
                            appState.reset(); logger.clear()
                            withAnimation { showDropZone = true }
                            ATLASNotification.send(
                                title: "TITAN VSCAN™ — Deleted",
                                body: "\(url.lastPathComponent) permanently deleted."
                            )
                        },
                        onStripAndInstall: {
                            // For now: proceed — strip logic runs inside InstallationManager
                            // based on the vscan result stored on appState
                            showVScanSheet = false
                            pendingVScanURL = nil
                            pendingVScanResult = nil
                            beginInstall(url: url)
                        },
                        onCancel: {
                            showVScanSheet = false
                            pendingVScanURL = nil
                            pendingVScanResult = nil
                            appState.reset(); logger.clear()
                            withAnimation { showDropZone = true }
                        }
                    )
                }
            }
        }

        if appState.phase == .success || appState.phase == .failure {
            resultBanner
        }

        // TITAN CORE™ inline recovery notice — shown after failure/recovery
        if let recovery = titanCore.lastRecovery,
           appState.phase == .failure || appState.phase == .success {
            titanRecoveryNotice(recovery)
        }

        if showPluginScan && !pluginScanResults.isEmpty {
            PluginScanView(results: pluginScanResults) {
                withAnimation { showPluginScan = false }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }

        if !queue.isProcessing && queue.hasItems {
            let succeeded = queue.items.filter {
                if case .success = $0.status { return true }
                return false }.count
            let failed = queue.items.filter {
                if case .failure = $0.status { return true }
                return false }.count
            if succeeded + failed == queue.items.count &&
               queue.items.count > 0 {
                queueSummary(succeeded: succeeded, failed: failed)
            }
        }
    }

    // MARK: - Monthly limit UI

    var monthlyLimitLockedZone: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let t  = monthlyLimit.timeUntilReset
            let days = Int(t) / 86400
            let hh   = (Int(t) % 86400) / 3600
            let mm   = (Int(t) % 3600) / 60
            let ss   = Int(t) % 60
            let countdown = days > 0
                ? String(format: "%dd %02d:%02d:%02d", days, hh, mm, ss)
                : String(format: "%02d:%02d:%02d", hh, mm, ss)

            let planName   = auth.isPro ? "Pro" : "Standard"
            let cap        = monthlyLimit.currentLimit
            let nextPlan   = "Pro"
            let upgradeMsg = "Upgrade to Pro"

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.atlasDeepBG)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "#F0A030").opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                    )

                VStack(spacing: 14) {
                    Image(systemName: "lock.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(Color(hex: "#F0A030"))

                    VStack(spacing: 4) {
                        Text("Monthly install limit reached")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0A030"))
                        Text("\(planName) plan: \(cap) installs per month")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#696E7C"))
                    }

                    if monthlyLimit.hasPendingFiles {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.badge.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#696E7C"))
                            Text("\(monthlyLimit.pendingURLs.count) file\(monthlyLimit.pendingURLs.count == 1 ? "" : "s") pending")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#696E7C"))
                        }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#696E7C"))
                        Text("Refills in \(countdown)")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundColor(Color(hex: "#D0D8F0"))
                    }

                    if !auth.isPro {
                        Button {
                            upgradeFeature = nextPlan
                            showUpgrade = true
                        } label: {
                            Text(upgradeMsg)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#3ECFB2"))
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(Color(hex: "#3ECFB2").opacity(0.1))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(hex: "#3ECFB2").opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    var pendingFilesPanel: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 22))
                .foregroundColor(Color(hex: "#3ECFB2"))

            VStack(alignment: .leading, spacing: 3) {
                Text("Pending installation ready")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
                Text("\(monthlyLimit.pendingURLs.count) file\(monthlyLimit.pendingURLs.count == 1 ? "" : "s") queued from previous session")
                    .font(.system(size: 11))
                    .foregroundColor(Color.atlasSubtitle)
            }

            Spacer()

            Button("Continue Install") {
                let urls = monthlyLimit.pendingURLs
                monthlyLimit.clearPending()
                for url in urls { queue.add(url: url) }
                withAnimation { showDropZone = true }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color(hex: "#0D0F1A"))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color(hex: "#3ECFB2"))
            .cornerRadius(8)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(hex: "#3ECFB2").opacity(0.07))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(hex: "#3ECFB2").opacity(0.25), lineWidth: 1))
    }

    // MARK: - TITAN CORE™ recovery notice

    @ViewBuilder
    func titanRecoveryNotice(_ recovery: TitanCore.TitanRecovery) -> some View {
        switch recovery {
        case .recovered(let action):
            HStack(spacing: 10) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#3ECFB2"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("TITAN CORE™ recovered the installation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#3ECFB2"))
                    Text(action.prefix(1).uppercased() + action.dropFirst())
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#3ECFB2").opacity(0.75))
                }
                Spacer()
                Button {
                    withAnimation { titanCore.clearLastRecovery() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#696E7C"))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(hex: "#3ECFB2").opacity(0.07))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#3ECFB2").opacity(0.2), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .bottom)))

        case .guidance(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#F0A030"))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TITAN CORE™ recommendation")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#F0A030"))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#C8A060"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    withAnimation { titanCore.clearLastRecovery() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "#696E7C"))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(hex: "#F0A030").opacity(0.07))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#F0A030").opacity(0.2), lineWidth: 1))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    var scanningIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .tint(Color(hex: "#3ECFB2"))
            Text("Scanning \(appState.selectedFileURL?.lastPathComponent ?? "")...")
                .font(.system(size: 13))
                .foregroundColor(Color.atlasSubtitle)
            Spacer()
            Button {
                appState.reset()
                withAnimation { showDropZone = true }
            } label: {
                Text("Cancel")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.atlasSubtitle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.atlasPanelBG)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.atlasBorder, lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atlasCard()
    }

    var installMoreButton: some View {
        Button {
            appState.reset()
            logger.clear()
            queue.items.removeAll()
            withAnimation { showDropZone = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(Color(hex: "#3ECFB2"))
                Text(L(.installMore))
                    .foregroundColor(Color.atlasLabel)
            }
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.atlasPanelBG)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "#3ECFB2").opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    func queueSummary(succeeded: Int, failed: Int) -> some View {
        VStack(spacing: 12) {
            HStack {
                Label("\(succeeded) installed",
                      systemImage: "checkmark.circle.fill")
                    .foregroundColor(Color(hex: "#2ECC8A"))
                    .font(.system(size: 13, weight: .medium))
                if failed > 0 {
                    Label("\(failed) failed",
                          systemImage: "xmark.circle.fill")
                        .foregroundColor(Color(hex: "#E05555"))
                        .font(.system(size: 13, weight: .medium))
                }
                Spacer()
            }
            installMoreButton
        }
        .padding(14)
        .atlasCard()
    }

    @ViewBuilder
    var resultBanner: some View {
        if let record = historyStore.records.first {
            InstallSummaryCard(record: record,
                               installerURL: appState.selectedFileURL,
                               onDone: resetAll)
        }
    }

    @ViewBuilder
    var unsupportedWarning: some View {
        if let ext = unsupportedExtension {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(hex: "#F0A030"))
                Text(".\(ext) files are not supported yet.")
                    .font(.system(size: 13))
                    .foregroundColor(Color.atlasLabel)
                Spacer()
                Button("Dismiss") { unsupportedExtension = nil }
                    .font(.system(size: 12))
                    .foregroundColor(Color.atlasSubtitle)
                    .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color(hex: "#F0A030").opacity(0.08))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "#F0A030").opacity(0.3), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    var rollbackBanner: some View {
        if rollbackInProgress {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if rollbackQueueTotal > 1 {
                        Text("Uninstalling \(rollbackQueueDone + 1) of \(rollbackQueueTotal)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#E05555"))
                    } else {
                        Text("Uninstalling")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#E05555"))
                    }
                    Text(rollingBack?.fileName ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(Color.atlasLabel)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                ATLASProgressBar(
                    progress: rollbackProgress,
                    stepLabel: rollbackStep.isEmpty ? "Preparing…" : rollbackStep,
                    danger: true
                )
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }

        // Single uninstall result
        if let result = uninstallResult, rollbackQueueTotal <= 1 {
            UninstallSummaryCard(
                removedFiles: result.removedFiles,
                failedFiles: result.failedFiles,
                appName: rollingBack?.fileName ?? "",
                onDone: resetAll,
                onRecover: result.manifestPath != nil ? {
                    if let record = historyStore.records.first(where: {
                        $0.status == .uninstalled && $0.rollbackBackupPath == result.manifestPath
                    }) {
                        beginRestore(record: record)
                        uninstallResult = nil
                    }
                } : nil
            )
        }

        // Batch uninstall result
        if !batchRollbackResults.isEmpty && !rollbackInProgress && rollbackQueueTotal > 1 {
            batchResultCard
        }
    }

    @ViewBuilder
    private var batchResultCard: some View {
        let succeeded = batchRollbackResults.filter { $0.1.success }.count
        let failed    = batchRollbackResults.filter { !$0.1.success }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: failed == 0
                    ? "checkmark.circle.fill"
                    : "exclamationmark.triangle.fill")
                    .foregroundColor(failed == 0
                        ? Color(hex: "#2ECC8A")
                        : Color(hex: "#F0A030"))
                    .font(.system(size: 14))
                Text(failed == 0
                    ? "Session uninstall complete"
                    : "Session uninstall finished with errors")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.atlasLabel)
            }
            HStack(spacing: 16) {
                Label("\(succeeded) removed", systemImage: "trash")
                    .foregroundColor(Color(hex: "#2ECC8A"))
                    .font(.system(size: 12))
                if failed > 0 {
                    Label("\(failed) failed", systemImage: "xmark.circle")
                        .foregroundColor(Color(hex: "#E05555"))
                        .font(.system(size: 12))
                }
            }
            Button("Done") { resetAll() }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.atlasLabel)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.atlasElevated)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#2E3350"), lineWidth: 1))
                .buttonStyle(.plain)
        }
        .padding(14)
        .atlasCard()
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Helpers

    private var isIdle: Bool {
        appState.phase == .idle &&
        !rollbackInProgress &&
        !queue.hasItems &&
        showDropZone
    }

    private func handleFilesDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }

        // Block ATLAS installers
        if urls.contains(where: { InstallerClassifier.isAtlasItself($0) }) {
            showAtlasSelfInstallAlert = true
            return
        }

        // Standard plan: daily limit gate
        if !auth.isPro {
            guard !monthlyLimit.isLocked else { return }

            if urls.count > 1 {
                // Cap at remaining daily installs — store overflow as pending
                let remaining = monthlyLimit.remaining
                guard remaining > 0 else { return }
                let toInstall = Array(urls.prefix(remaining))
                let pending   = Array(urls.dropFirst(remaining))
                if !pending.isEmpty { monthlyLimit.setPending(pending) }
                greetingShown = true
                let bundles = BundleGrouper.group(toInstall)
                for bundle in bundles {
                    for url in bundle.files { queue.add(url: url) }
                }
                withAnimation { showDropZone = true }
                return
            }
        } else {
            // Pro: group related files into bundles, then queue them in install order
            if urls.count > 1 {
                greetingShown = true
                let bundles = BundleGrouper.group(urls)
                if bundles.count < urls.count {
                    // At least one bundle was formed — log it
                    for bundle in bundles where !bundle.isSingleFile {
                        logger.log("📦 Bundle detected: \"\(bundle.name)\" (\(bundle.files.count) files — installing in order)")
                    }
                }
                // Add files in the resolved install order (PKG → library → patch)
                for bundle in bundles {
                    for url in bundle.files { queue.add(url: url) }
                }
                withAnimation { showDropZone = true }
                return
            }
        }

        // Dismiss first-launch greeting permanently
        greetingShown = true

        if urls.count == 1 && !queue.hasItems && appState.phase == .idle && !queue.isProcessing {
            withAnimation { showDropZone = false }
            beginScan(url: urls[0])
        } else {
            for url in urls { queue.add(url: url) }
            withAnimation { showDropZone = true }
        }
    }

    private func beginScan(url: URL) {
        guard !InstallerClassifier.isAtlasItself(url) else {
            showAtlasSelfInstallAlert = true
            return
        }

        // TITAN CORE™: check if this warrants mission activation (ISO or folder with complex content)
        let ext = url.pathExtension.lowercased()
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let isMountable = ext == "iso" || ext == "dmg"

        // Plugin bundles (.vst3, .component, .vst, .aaxplugin) are directories on macOS,
        // so isFolder=true — but they are NOT complex installs. Skip TITAN and go straight
        // to the regular plugin install path which just copies + codesigns the bundle.
        let isPluginBundle = ["vst3", "component", "vst", "aaxplugin"].contains(ext)

        if TitanCore.shared.isAvailable && (isMountable || isFolder) && !isPluginBundle {
            // Run on a background thread — hdiutil attach is a blocking call that would
            // freeze the UI if called on the MainActor (Task {} inherits MainActor).
            Task.detached(priority: .userInitiated) {
                var scanDir = url.path
                var mountedAt = ""

                await MainActor.run {
                    logger.log("TITAN CORE™: Analyzing \(url.lastPathComponent)…")
                    appState.phase = .scanning
                }

                if isMountable {
                    if let existing = InstallEngine.findExistingMount(for: url.path) {
                        scanDir = existing
                        await MainActor.run { logger.log("TITAN CORE™: Volume already mounted at \(existing)") }
                    } else {
                        await MainActor.run { logger.log("TITAN CORE™: Mounting…") }
                        var args = ["attach", url.path, "-nobrowse", "-readonly", "-mountrandom", "/tmp"]
                        if ext == "iso" { args.append("-noverify") }
                        let mountResult = InstallEngine.runProcess(path: "/usr/bin/hdiutil", arguments: args)
                        if mountResult.success {
                            let lines = mountResult.output.components(separatedBy: .newlines)
                            if let mp = lines.last(where: { $0.contains("/tmp/") || $0.contains("/Volumes/") })?
                                .components(separatedBy: "\t").last?
                                .trimmingCharacters(in: .whitespaces), !mp.isEmpty {
                                scanDir = mp
                                mountedAt = mp
                                await MainActor.run { logger.log("TITAN CORE™: Mounted at \(mp)") }
                            }
                        } else {
                            await MainActor.run { logger.log("TITAN CORE™: Mount failed — \(mountResult.output.prefix(100))") }
                        }
                    }
                }

                let capturedScanDir = scanDir
                await MainActor.run { logger.log("TITAN CORE™: Scanning \(capturedScanDir)…") }
                let scan = InstallIntelligence.titanScan(directory: capturedScanDir)
                await MainActor.run {
                    logger.log("TITAN CORE™: isComplex=\(scan.isComplex) scripts=\(scan.scripts.count) binaries=\(scan.binaries.count) hasInstructions=\(scan.hasInstructions)")
                }

                // Not complex — run the normal InstallerScanner flow
                guard scan.isComplex else {
                    if !mountedAt.isEmpty {
                        _ = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
                                                     arguments: ["detach", mountedAt, "-quiet"])
                    }
                    await MainActor.run {
                        appState.selectedFileURL = url
                        appState.phase = .scanning
                        logger.log("File selected: \(url.lastPathComponent)")
                        logger.log("Scanning contents...")
                    }
                    let result = await InstallerScanner.scan(url: url)
                    await MainActor.run {
                        appState.scanResult = result
                        appState.phase = .scanned
                        logger.log("Scan complete — \(result.installerType)")
                        for item in result.contentsFound {
                            logger.log("  Found: \(item.name) (\(item.type.label))")
                        }
                        for warning in result.warnings {
                            logger.log("  Warning: \(warning)")
                        }
                    }
                    return
                }

                let finalScanDir  = scanDir
                let finalMountedAt = mountedAt

                // Enumerate recursively — ISOs commonly place their files inside
                // a subfolder (e.g. "noteGRABBER v2.0.0 macOS U2B Incl.K BTCR/")
                // rather than at the root, so non-recursive contentsOfDirectory would
                // miss the PKG installer entirely.
                let installableExts: Set<String> = [
                    "pkg", "mpkg", "app", "component", "vst3", "vst", "aaxplugin"
                ]
                var allFiles: [URL] = []
                if let enumerator = FileManager.default.enumerator(
                    at: URL(fileURLWithPath: finalScanDir),
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]) {
                    for case let url as URL in enumerator {
                        let isDir = (try? url.resourceValues(
                            forKeys: [.isDirectoryKey]).isDirectory) ?? false
                        if !isDir && installableExts.contains(url.pathExtension.lowercased()) {
                            allFiles.append(url)
                        }
                    }
                }
                let capturedAllFiles = allFiles
                await MainActor.run { logger.log("TITAN CORE™: Found \(capturedAllFiles.count) installable file(s)") }

                // ── Waves Audio — dedicated engine ──────────────────────────
                // Checked before generic TITAN plan so Waves always uses its
                // specific uninstall → Central → patch → AU reg flow.
                if WavesInstallEngine.isWavesContent(directory: finalScanDir, files: capturedAllFiles) {
                    let adminPwd = await MainActor.run { KeychainManager.loadPassword() ?? "" }
                    await MainActor.run {
                        appState.phase = .installing
                        logger.log("WAVES: Waves Audio detected — routing to Waves Install Engine.")
                    }
                    let (wavesOK, wavesError) = await WavesInstallEngine.install(
                        sourceDir: finalScanDir,
                        adminPassword: adminPwd,
                        logger: logger
                    )
                    if !finalMountedAt.isEmpty {
                        _ = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
                                                     arguments: ["detach", finalMountedAt, "-quiet"])
                    }
                    // ── TITAN VERIFY™ for Waves ───────────────────────────
                    let wavesBaseOK = wavesOK
                    var wavesFinalOK = wavesBaseOK
                    if wavesBaseOK {
                        let verify = await TitanVerify.verify(
                            installedFiles: [],
                            pkgReceiptIDs: [],
                            sourceURL: url,
                            logger: logger)
                        if !verify.passed { wavesFinalOK = false }
                    }
                    let wavesLogType = wavesFinalOK ? "install" : "failed"

                    // Write install record + sync log (same pipeline as normal installs)
                    let wavesInstallResult: InstallResult = wavesFinalOK
                        ? .success(appName: "Waves Audio V16")
                        : .failure(reason: wavesError ?? "Waves install failed — check log for details")
                    await MainActor.run {
                        let installResult: InstallResult = wavesInstallResult
                        let record = InstallLogger.writeLog(
                            fileURL: url,
                            fileType: "Waves Audio Bundle",
                            entries: logger.entries,
                            result: installResult,
                            installedFiles: [],
                            pkgReceiptIDs: [],
                            sessionID: UUID())
                        historyStore.add(record)
                        appState.phase = .idle
                    }
                    await MainActor.run {
                        let logContent = logger.entries.joined(separator: "\n")
                        syncInstallLog(
                            logType: wavesLogType,
                            appName: "Waves Audio V16",
                            fileName: url.lastPathComponent,
                            content: logContent)
                    }
                    return
                }
                // ────────────────────────────────────────────────────────────

                let plan = await InstallIntelligence.analyze(directory: finalScanDir, files: capturedAllFiles)
                await MainActor.run { logger.log("TITAN CORE™: Plan has \(plan.orderedSteps.count) step(s), instructions=\(plan.instructions != nil)") }

                await MainActor.run {
                    let mission = TitanMission(mountPoint: finalScanDir, sourceURL: url)
                    mission.buildMission(plan: plan, scan: scan)
                    logger.log("TITAN CORE™: Mission built — \(mission.steps.count) step(s). Showing panel…")
                    activeTitanMission  = mission
                    titanMountPoint     = finalScanDir
                    titanPreScanMount   = finalMountedAt
                    titanSourceURL      = url

                    let fileNames = capturedAllFiles.map { $0.lastPathComponent }.filter { !$0.hasPrefix(".") }

                    let installableCount = mission.steps.filter {
                        if case .installPkg = $0.action { return true }
                        return false
                    }.count

                    if !auth.isPro && installableCount > 1 {
                        // Standard plan: let user pick which product to install
                        showMultipleProductsGate = true
                    } else {
                        showTitanMission = true
                    }
                }
            }
            return
        }

        appState.selectedFileURL = url
        appState.phase = .scanning
        logger.log("File selected: \(url.lastPathComponent)")
        logger.log("Scanning contents...")
        Task {
            let result = await InstallerScanner.scan(url: url)
            await MainActor.run {
                appState.scanResult = result
                appState.phase = .scanned
                logger.log("Scan complete — \(result.installerType)")
                for item in result.contentsFound {
                    logger.log("  Found: \(item.name) (\(item.type.label))")
                }
                for warning in result.warnings {
                    logger.log("  Warning: \(warning)")
                }
            }
        }
    }

    // Called from ScanResultView. Routes through storage selection then TITAN VSCAN™.
    private func beginInstallFromScan(url: URL, scanResult: ScanResult) {
        if Features.smartStorage && scanResult.requiresStorageSelection {
            pendingInstallURL  = url
            pendingScanResult  = scanResult
            showStorageSelection = true
        } else if Features.titanVScan {
            // TITAN VSCAN™ — Pro only
            pendingVScanURL = url
            Task {
                appState.phase = .scanning
                appState.selectedFileURL = url
                let result = await titanVScan.scan(url: url)
                appState.phase = .scanned

                guard let result else {
                    // Scan failed (unexpected) — proceed without blocking
                    pendingVScanURL = nil
                    beginInstall(url: url)
                    return
                }

                if result.verdict == .clean {
                    // Silently pass — no need to show sheet for clean files
                    pendingVScanURL = nil
                    beginInstall(url: url)
                } else {
                    // Show TITAN VSCAN™ sheet for everything else
                    pendingVScanResult = result
                    showVScanSheet = true
                }
            }
        } else {
            beginInstall(url: url)
        }
    }

    private func beginInstall(url: URL) {
        // Record single-file install against daily limit (Standard only)
        monthlyLimit.recordInstall()
        withAnimation { showDropZone = false }
        pluginScanResults = []
        showPluginScan = false
        WidgetStateManager.shared.menuStatus = .installing
        startWidgetTimer()
        InstallationManager.shared.install(
            url: url, appState: appState,
            logger: logger, historyStore: historyStore
        ) { isPlugin in
            InstallEngine.storageRoot = nil   // clear TITAN CORE™ storage routing
            cancelWidgetTimer()
            exitWidgetMode()
            if isPlugin && RosettaEngine.isAppleSilicon {
                withAnimation { showRosetta = true }
            }
            // Post notification and update menu bar icon
            switch appState.lastResult {
            case .success(let name, _):
                ATLASNotification.send(
                    title: L(.notifySuccessTitle),
                    body: "\(name) installed successfully.")
                WidgetStateManager.shared.menuStatus = .success
            case .failure(let reason):
                ATLASNotification.send(
                    title: L(.notifyFailedTitle),
                    body: reason)
                WidgetStateManager.shared.menuStatus = .failure
                // TITAN CORE™ handles recovery automatically during install —
                // no manual activate needed here
            case nil:
                WidgetStateManager.shared.menuStatus = .idle
            }
            // Run plugin visibility scan after any successful install
            if let record = historyStore.records.first {
                let results = PluginScanner.scan(installedFiles: record.installedFiles)
                if !results.isEmpty {
                    pluginScanResults = results
                    withAnimation { showPluginScan = true }
                }
            }
        }
    }

    private func startQueue() {
        // Standard plan: cap queue at remaining daily installs, store overflow as pending
        if !auth.isPro {
            let remaining = monthlyLimit.remaining
            if queue.items.count > remaining {
                let overflow = Array(queue.items.dropFirst(remaining))
                monthlyLimit.setPending(overflow.map { $0.url })
                for item in overflow { queue.remove(id: item.id) }
            }
        }

        withAnimation { showDropZone = true }   // keep drop zone visible so users can queue more
        queue.isProcessing = true
        InstallEngine.resetCancellation()
        logger.log("--- Queue started: \(queue.items.count) file(s) ---")
        WidgetStateManager.shared.menuStatus = .installing
        startWidgetTimer()

        // All items in this queue run share a session ID for batch-uninstall grouping
        let sessionID = UUID()

        queueTask = Task {
            // Pre-install system checks — run before touching any file
            let urlsToCheck = queue.items.map { $0.url }
            let checks = PreInstallChecker.check(urls: urlsToCheck)
            await MainActor.run { preInstallWarnings = checks.filter { !$0.isBlocker } }
            if let blocker = checks.first(where: { $0.isBlocker }) {
                logger.log("⛔ Install blocked: \(blocker.message)")
                for item in queue.items {
                    if case .waiting = item.status {
                        queue.updateStatus(id: item.id, status: .failure(blocker.message))
                    }
                }
                queue.isProcessing = false
                appState.phase = .idle
                return
            }

            // Phase 1: Scan all items sequentially (fast, read-only)
            let items = queue.items
            for item in items {
                guard case .waiting = item.status else { continue }
                queue.updateStatus(id: item.id, status: .scanning)
                logger.log("Scanning: \(item.fileName)")
                let scanResult = await InstallerScanner.scan(url: item.url)
                queue.updateScanResult(id: item.id, result: scanResult)
                queue.updateStatus(
                    id: item.id,
                    status: scanResult.canInstall ? .waiting : .failure("confidence too low")
                )
            }

            // Phase 2: Split ready items into parallel (plugins/apps) and serial (pkg/dmg/iso/zip)
            let parallelItems = queue.items.filter {
                if case .waiting = $0.status { return $0.canRunParallel }
                return false
            }
            let serialItems = queue.items.filter {
                if case .waiting = $0.status { return !$0.canRunParallel }
                return false
            }

            if !parallelItems.isEmpty {
                logger.log("Running \(parallelItems.count) parallel install(s) simultaneously...")
            }

            // Phase 3: Launch parallel installs as concurrent Tasks,
            //          run serial installs one-by-one — both groups start together.
            var parallelTasks: [Task<Void, Never>] = []
            for item in parallelItems {
                let id = item.id
                parallelTasks.append(Task { await runInstallItem(id: id, sessionID: sessionID) })
            }
            for item in serialItems {
                await runInstallItem(id: item.id, sessionID: sessionID)
            }
            for t in parallelTasks { await t.value }

            queue.isProcessing = false
            queue.currentIndex = nil
            preInstallWarnings = []
            logger.log("--- Queue complete ---")
            cancelWidgetTimer()
            exitWidgetMode()
            if !pluginScanResults.isEmpty {
                withAnimation { showPluginScan = true }
            }

            let succeeded = queue.items.filter {
                if case .success = $0.status { return true }
                if case .demoWarning = $0.status { return true }
                return false }.count
            let demoCount = queue.items.filter {
                if case .demoWarning = $0.status { return true }; return false }.count
            let failed = queue.items.filter {
                if case .failure = $0.status { return true }; return false }.count
            let demoNote = demoCount > 0 ? ", \(demoCount) in demo mode" : ""
            let rescanNote: String = {
                let daws = DAWRescanAdvisor.runningDAWs()
                if succeeded > 0 && !daws.isEmpty {
                    return " Rescan plugins in \(daws.joined(separator: " & "))."
                }
                return ""
            }()
            ATLASNotification.send(
                title: "ATLAS — Queue Complete",
                body: "\(succeeded) installed successfully\(demoNote)" +
                      (failed > 0 ? ", \(failed) failed." : ".") + rescanNote
            )
            WidgetStateManager.shared.menuStatus = failed > 0 ? .failure : .success
        }
    }

    private func runInstallItem(id: UUID, sessionID: UUID) async {
        guard !InstallEngine.cancellationRequested else {
            queue.updateStatus(id: id, status: .failure("cancelled"))
            return
        }
        guard let item = queue.items.first(where: { $0.id == id }) else { return }
        // Record against daily limit per queued file (Standard only)
        await MainActor.run { monthlyLimit.recordInstall() }
        queue.updateStatus(id: id, status: .installing)
        logger.log("Installing: \(item.fileName)")

        var (result, installedFiles, receiptIDs, isPlugin, runtimeCreatedPaths) =
            await InstallEngine.install(url: item.url, logger: logger) { pct, step in
                self.queue.updateProgress(id: id, progress: pct, step: step)
            }

        // Silent retry — if the first attempt failed and the user didn't cancel,
        // wait 2 s and try exactly once more (covers transient permission dialogs,
        // file-lock races, and PKG installer timing issues).
        if case .failure(let reason) = result,
           !reason.lowercased().contains("cancelled"),
           !InstallEngine.cancellationRequested {
            logger.log("  ↺ Retrying install in 2 s…")
            queue.updateProgress(id: id, progress: 0.05, step: L(.retrying))
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !InstallEngine.cancellationRequested {
                var retryRuntimePaths: [String]
                (result, installedFiles, receiptIDs, isPlugin, retryRuntimePaths) =
                    await InstallEngine.install(url: item.url, logger: logger) { pct, step in
                        self.queue.updateProgress(id: id, progress: pct, step: step)
                    }
                // Merge paths from both attempts so nothing discovered during the
                // first attempt is lost if the second attempt's snapshot starts fresh.
                runtimeCreatedPaths = Array(Set(runtimeCreatedPaths + retryRuntimePaths))
                if case .success = result {
                    logger.log("  ✓ Retry succeeded")
                } else {
                    logger.log("  ✗ Retry also failed — marking as failed")
                }
            }
        }

        // ── TITAN VERIFY™ ─────────────────────────────────────────────────────
        var finalResult = result
        var demoWarnings: [DemoHit] = []
        var verifyPassed = false
        if case .success = result {
            queue.updateProgress(id: id, progress: 0.95, step: "Verifying install…")
            let verify = await TitanVerify.verify(
                installedFiles: installedFiles,
                pkgReceiptIDs: receiptIDs,
                sourceURL: item.url,
                logger: logger)
            demoWarnings = verify.demoWarnings
            if !verify.passed {
                finalResult = .failure(reason: verify.summary)
            } else {
                verifyPassed = true
            }
        }

        let type_    = InstallerClassifier.classify(url: item.url)
        let fileType = typeLabel(type_)
        var record   = InstallLogger.writeLog(
            fileURL: item.url, fileType: fileType,
            entries: logger.entries, result: finalResult,
            installedFiles: installedFiles, pkgReceiptIDs: receiptIDs,
            sessionID: sessionID)
        record.titanVerified = verifyPassed && demoWarnings.isEmpty
        record.demoDetected  = !demoWarnings.isEmpty
        if !runtimeCreatedPaths.isEmpty {
            record.runtimeCreatedPaths = runtimeCreatedPaths
        }

        historyStore.add(record)

        // ── ATLAS LEARN™ — upload verified clean installs as learned patterns ──
        if verifyPassed && demoWarnings.isEmpty, case .success(let learnName, _) = finalResult {
            let capturedFiles    = installedFiles
            let capturedReceipts = receiptIDs
            let capturedURL      = item.url
            Task.detached {
                await ATLASLearn.shared.contribute(
                    productName: learnName,
                    sourceURL: capturedURL,
                    installedFiles: capturedFiles,
                    pkgReceiptIDs: capturedReceipts)
            }
        }

        let logContent = logger.entries.joined(separator: "\n")
        switch finalResult {
        case .success(let name, let postNote):
            queue.updateStatus(id: id, status: .success)
            queue.updateProgress(id: id, progress: 1.0, step: "")
            if let note = postNote {
                logger.log("  ℹ️ Post-install note: \(note)")
                queue.updateStatus(id: id, status: .demoWarning(note))
            }
            if !demoWarnings.isEmpty {
                logger.log("  ⚠️ Installed with warning: Demo Mode detected (\(demoWarnings.count) signal(s))")
                queue.updateStatus(id: id, status: .demoWarning(ATLASMessages.friendlyDemoWarning(keywords: demoWarnings.map { $0.keyword })))
                await MainActor.run { pendingDemoAlerts.append(DemoAlert(productName: name, hits: demoWarnings)) }
            } else {
                logger.log("  ✓ Installed & TITAN VERIFIED™: \(name)")
            }
            if isPlugin && RosettaEngine.isAppleSilicon {
                withAnimation { showRosetta = true }
            }
            let newScanResults = PluginScanner.scan(installedFiles: installedFiles)
            if !newScanResults.isEmpty {
                pluginScanResults.append(contentsOf: newScanResults)
            }
            syncInstallLog(logType: demoWarnings.isEmpty ? "install" : "install-demo",
                           appName: name, fileName: item.fileName, content: logContent)
            // Feedback prompt — ask user 60s after success
            let feedbackName = name
            let capturedRecord = record
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [self] in
                guard !showFeedbackPrompt else { return }
                guard !UserDefaults.standard.bool(forKey: "atlas.feedbackSubmitted.\(feedbackName)") else { return }
                feedbackProductName = feedbackName
                feedbackRecord = capturedRecord
                withAnimation { showFeedbackPrompt = true }
            }
        case .failure(let reason):
            let isCancelled = reason.lowercased() == "cancelled"
            queue.updateStatus(id: id, status: .failure(reason))
            logger.log(isCancelled ? "  ✗ Cancelled" : "  ✗ Failed: \(reason)")
            syncInstallLog(logType: "failed", appName: item.fileName, fileName: item.fileName, content: logContent)
            if !isCancelled {
                ATLASFailureReporter.report(
                    productName:    item.fileName,
                    sourceURL:      item.url,
                    failureReason:  reason,
                    stepsAttempted: logger.entries.filter { $0.hasPrefix("[") }.map { $0 },
                    installLog:     logContent)
            }
            // ZIP password cancel — clear queue and go back to home
            if reason.lowercased().contains("password required") || isCancelled {
                await MainActor.run {
                    queue.clear()
                    queue.items.removeAll()
                    logger.clear()
                    withAnimation { showDropZone = true }
                    appState.reset()
                }
            }
        }
    }

    private func syncInstallLog(logType: String, appName: String, fileName: String, content: String) {
        guard UserDefaults.standard.bool(forKey: "ATLAS.privacyConsentGiven"),
              let session = auth.session else { return }
        let deviceName = Host.current().localizedName ?? "Unknown Mac"
        let hwUUID = atlasHardwareUUID()
        Task.detached {
            try? await SupabaseService.shared.uploadLog(
                accessToken: session.accessToken,
                logType: logType,
                appName: appName,
                filename: fileName,
                content: content,
                deviceName: deviceName,
                hardwareUUID: hwUUID
            )
        }
    }

    // MARK: - Batch uninstall engine

    private func beginBatchUninstall(records: [InstallRecord]) {
        guard !rollbackInProgress else { return }
        let eligible = records.filter {
            $0.status == .success &&
            (!$0.installedFiles.isEmpty || !$0.pkgReceiptIDs.isEmpty)
        }
        guard !eligible.isEmpty else { return }

        rollbackQueue     = Array(eligible.dropFirst())
        rollbackQueueTotal = eligible.count
        rollbackQueueDone  = 0
        batchRollbackResults = []
        uninstallResult    = nil

        runNextRollback(eligible[0])
    }

    private func runNextRollback(_ record: InstallRecord) {
        appState.reset()
        rollingBack       = record
        rollbackInProgress = true
        rollbackProgress   = 0.0
        rollbackStep       = ""
        WidgetStateManager.shared.menuStatus = .installing
        startWidgetTimer()
        logger.log(rollbackQueueTotal > 1
            ? "--- Uninstall \(rollbackQueueDone + 1) of \(rollbackQueueTotal): \(record.fileName) ---"
            : "--- Uninstall initiated ---")

        rollbackTask = Task {
            let result = await RollbackEngine.rollback(
                record: record,
                otherRecords: historyStore.records,
                logger: logger
            ) { progress, step in
                Task { @MainActor in
                    rollbackProgress = progress
                    rollbackStep = step
                }
            }
            await MainActor.run {
                rollbackInProgress = false
                rollbackTask = nil
                rollbackProgress   = 1.0
                rollbackStep       = ""
                rollbackQueueDone += 1

                // User cancelled before any files were removed — reset silently
                if result.detail == "Cancelled." {
                    logger.log("⚠ Uninstall cancelled.")
                    resetAll()
                    WidgetStateManager.shared.menuStatus = .idle
                    return
                }

                if result.success {
                    logger.log("✓ Uninstall complete: \(result.detail)")
                    historyStore.markUninstalled(id: record.id,
                                                 backupPath: result.manifestPath)
                    syncInstallLog(logType: "uninstall", appName: record.fileName, fileName: record.fileName, content: logger.entries.joined(separator: "\n"))
                } else {
                    logger.log("✗ Uninstall failed: \(result.detail)")
                }
                InstallLogger.writeUninstallLog(
                    record: record, result: result, entries: logger.entries)

                if rollbackQueueTotal == 1 {
                    // Single uninstall — existing summary card
                    cancelWidgetTimer()
                    exitWidgetMode()
                    uninstallResult = result
                    ATLASNotification.send(
                        title: result.success ? "Uninstall Complete" : "Uninstall Failed",
                        body:  result.success
                            ? "\(record.fileName) was removed successfully."
                            : "\(record.fileName): \(result.detail)")
                    WidgetStateManager.shared.menuStatus = result.success ? .success : .failure
                    rollingBack = nil
                } else {
                    // Batch — accumulate result and continue
                    batchRollbackResults.append((record, result))
                    rollingBack = nil
                    if let next = rollbackQueue.first {
                        rollbackQueue.removeFirst()
                        runNextRollback(next)
                    } else {
                        cancelWidgetTimer()
                        exitWidgetMode()
                        let ok  = batchRollbackResults.filter {  $0.1.success }.count
                        let bad = batchRollbackResults.filter { !$0.1.success }.count
                        ATLASNotification.send(
                            title: "Session Uninstall Complete",
                            body:  "\(ok) item\(ok == 1 ? "" : "s") removed" +
                                   (bad > 0 ? ", \(bad) failed." : "."))
                        WidgetStateManager.shared.menuStatus = bad > 0 ? .failure : .success
                    }
                }
            }
        }
    }

    func beginRestore(record: InstallRecord) {
        guard let backupPath = record.rollbackBackupPath else { return }

        // Check if any files still exist in the Trash before starting recovery.
        // If the manifest exists but every file is gone, the Trash was emptied.
        if let data = try? Data(contentsOf: URL(fileURLWithPath: backupPath)),
           let trashRecords = try? JSONDecoder().decode([TrashRecord].self, from: data),
           !trashRecords.isEmpty {
            let anyInTrash = trashRecords.contains {
                FileManager.default.fileExists(atPath: $0.trashPath)
            }
            if !anyInTrash {
                trashEmptiedProductName = record.fileName
                showTrashEmptiedAlert = true
                return
            }
        }

        rollbackInProgress = true
        rollbackProgress = 0.0
        rollbackStep = "Restoring..."
        logger.log("--- Recovery initiated: \(record.fileName) ---")
        Task {
            let ok = await RollbackEngine.restore(from: backupPath, logger: logger)
            await MainActor.run {
                rollbackInProgress = false
                rollbackProgress = 1.0
                rollbackStep = ""
                if ok {
                    logger.log("✓ Recovery complete: \(record.fileName)")
                    historyStore.markRestored(id: record.id)
                    ATLASNotification.send(
                        title: "Restore Complete",
                        body: "\(record.fileName) has been restored.")
                    WidgetStateManager.shared.menuStatus = .success
                } else {
                    logger.log("✗ Recovery failed: \(record.fileName)")
                    ATLASNotification.send(
                        title: "Restore Failed",
                        body: "\(record.fileName) could not be restored.")
                    WidgetStateManager.shared.menuStatus = .failure
                }
            }
        }
    }

    private func performCancel() {
        if rollbackInProgress {
            RollbackEngine.cancelRollback()
            rollbackTask?.cancel()
            rollbackTask = nil
        } else {
            InstallEngine.cancelCurrentInstall()
            queueTask?.cancel()
            queueTask = nil
            // Mark remaining waiting/installing items as cancelled
            for item in queue.items {
                switch item.status {
                case .waiting, .installing, .scanning:
                    queue.updateStatus(id: item.id, status: .failure("cancelled"))
                default:
                    break
                }
            }
            queue.isProcessing = false
        }
        logger.log("⚠ Operation cancelled by user.")
    }

    private func resetAll() {
        cancelWidgetTimer()
        exitWidgetMode()
        appState.reset()
        logger.clear()
        queue.items.removeAll()
        unsupportedExtension = nil
        showRosetta = false
        uninstallResult = nil
        rollingBack = nil
        rollbackInProgress = false
        rollbackTask?.cancel()
        rollbackTask = nil
        rollbackQueue = []
        rollbackQueueTotal = 0
        rollbackQueueDone  = 0
        batchRollbackResults = []
        queueTask = nil
        pluginScanResults = []
        showPluginScan = false
        InstallEngine.resetCancellation()
        RollbackEngine.cancellationRequested = false
        WidgetStateManager.shared.menuStatus = .idle
        TitanCore.shared.deactivate()
        InstallEngine.storageRoot = nil
        withAnimation { showDropZone = true }
    }

    // MARK: - Widget mode

    private func startWidgetTimer() {
        widgetTimer?.cancel()
        widgetTimer = Task {
            try? await Task.sleep(nanoseconds: 2 * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // Use the reference-type WidgetStateManager so the check
                // reflects live state even after 2 minutes.
                if WidgetStateManager.shared.menuStatus == .installing {
                    enterWidgetMode()
                }
            }
        }
    }

    private func cancelWidgetTimer() {
        widgetTimer?.cancel()
        widgetTimer = nil
    }

    private func enterWidgetMode() {
        guard !widgetState.isWidgetMode else { return }
        guard UserDefaults.standard.bool(forKey: "atlas.widgetEnabled") else { return }
        widgetState.cancelIdleCollapse()
        if showTour { showTour = false }
        guard let mainWindow = AppDelegate.mainWindow ?? NSApp.windows.first else { return }

        // Fade out main window
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            mainWindow.animator().alphaValue = 0
        }, completionHandler: {
            mainWindow.orderOut(nil)
            widgetState.isWidgetMode = true
            AppDelegate.showWidgetPanel(appState: self.appState, queue: self.queue,
                onExpand: { self.exitWidgetMode() },
                onClose:  { self.exitWidgetMode(); AppDelegate.mainWindow?.orderOut(nil) })
        })
    }

    private func exitWidgetMode() {
        guard widgetState.isWidgetMode else { return }
        widgetState.isWidgetMode = false
        AppDelegate.closeWidgetPanel()
        guard let window = AppDelegate.mainWindow else { return }
        AppDelegate.centerWindow(window)
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            window.animator().alphaValue = 1
        }
        widgetState.scheduleIdleCollapse()
    }

    private func resizeWindow(toWidget: Bool) {
        guard let window = AppDelegate.mainWindow ?? NSApp.windows.first else { return }

        if toWidget {
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let pad: CGFloat = 20
            let w: CGFloat = 320
            let h: CGFloat = 92

            window.level = .floating
            window.minSize = CGSize(width: w, height: h)
            window.maxSize = CGSize(width: w, height: h)
            [NSWindow.ButtonType.closeButton,
             .miniaturizeButton, .zoomButton].forEach {
                window.standardWindowButton($0)?.isHidden = true
            }
            let x = screen.visibleFrame.maxX - w - pad
            let y = screen.visibleFrame.minY + pad
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.38
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(
                    NSRect(x: x, y: y, width: w, height: h), display: true)
            }
        } else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.hasShadow = true
            window.level = .normal
            window.contentView?.layer?.backgroundColor = nil
            // Free all constraints so the animation target is reachable
            window.minSize = CGSize(width: 1, height: 1)
            window.maxSize = CGSize(width: 99999, height: 99999)
            [NSWindow.ButtonType.closeButton,
             .miniaturizeButton, .zoomButton].forEach {
                window.standardWindowButton($0)?.isHidden = false
            }
            let w: CGFloat = 560
            let h: CGFloat = 680
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let x = screen.visibleFrame.midX - w / 2
            let y = screen.visibleFrame.midY - h / 2
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.40
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(
                    NSRect(x: x, y: y, width: w, height: h), display: true)
            }, completionHandler: {
                // Restore proper minimum after animation settles
                window.minSize = CGSize(width: 540, height: 460)
            })
        }
    }

    // Saves a history record after a completed TITAN CORE™ mission so the user
    // can roll back the install (uninstall PKG files + remove hosts entries) from
    // the History panel. PRO-only feature.
    private func saveTitanRecord(mission: TitanMission) {
        Task {
            await saveTitanRecordAsync(mission: mission)
        }
    }

    private func saveTitanRecordAsync(mission: TitanMission) async {
        let sourceName = mission.sourceURL.lastPathComponent
        // Only PKG installs are critical — script/binary failures don't mean the
        // software wasn't installed (all receipts may still be present).
        var hasFailed  = mission.steps.contains(where: {
            guard $0.status == .failed else { return false }
            if case .installPkg = $0.action { return true }
            return false
        })

        // Build detailed log entries — include resultNote so failures are diagnosable
        var entries: [String] = mission.steps.map { step in
            let note = step.resultNote.isEmpty ? "" : " — \(step.resultNote)"
            return "[\(step.status)] \(step.title)\(note)"
        }

        // First critical (PKG) failure reason for the log header
        let failureReason: String = mission.steps
            .first(where: { step in
                guard step.status == .failed else { return false }
                if case .installPkg = step.action { return true }
                return false
            })
            .map { "\($0.title): \($0.resultNote.isEmpty ? "Step failed" : $0.resultNote)" }
            ?? "One or more steps failed"

        // ── TITAN VERIFY™ ─────────────────────────────────────────────────────
        var titanDemoWarnings: [DemoHit] = []
        if !hasFailed {
            let verify = await TitanVerify.verify(
                installedFiles: mission.installedFiles,
                pkgReceiptIDs: mission.installedPKGReceipts,
                sourceURL: mission.sourceURL,
                logger: logger)
            entries.append(contentsOf: verify.checks.map {
                "[\($0.passed ? "verify-pass" : "verify-fail")] \($0.label): \($0.detail)"
            })
            titanDemoWarnings = verify.demoWarnings
            if !verify.passed {
                hasFailed = true
            }
        }

        // Always write the log — every plan gets a record of what happened
        let finalResult: InstallResult = hasFailed
            ? .failure(reason: failureReason)
            : .success(appName: sourceName)

        let record = InstallLogger.writeLog(
            fileURL:      mission.sourceURL,
            fileType:     mission.sourceURL.pathExtension.uppercased().isEmpty
                              ? "Install"
                              : mission.sourceURL.pathExtension.uppercased(),
            entries:      entries,
            result:       finalResult,
            installedFiles:   mission.installedFiles,
            pkgReceiptIDs:    mission.installedPKGReceipts,
            remediationAttempted: false
        )

        logger.log(hasFailed ? "⚠️ TITAN mission completed with failures — log saved" : "📋 TITAN mission saved")

        syncInstallLog(
            logType: hasFailed ? "failed" : "install",
            appName: sourceName,
            fileName: sourceName,
            content: entries.joined(separator: "\n")
        )

        if hasFailed {
            ATLASFailureReporter.report(
                productName:    sourceName,
                sourceURL:      mission.sourceURL,
                failureReason:  failureReason,
                stepsAttempted: mission.steps.map { "[\($0.status)] \($0.title)" },
                installLog:     entries.joined(separator: "\n"),
                planSource:     mission.plan?.planSource ?? "")
        }

        // Always save hosts entries to history so rollback can clean them up for any user.
        // (Hosts entries must be removed on uninstall regardless of plan tier.)
        let titanVerifyPassed = !hasFailed && titanDemoWarnings.isEmpty
        var fullRecord = record
        fullRecord.titanVerified = titanVerifyPassed
        fullRecord.demoDetected  = !titanDemoWarnings.isEmpty
        if !mission.addedHostsEntries.isEmpty {
            fullRecord = InstallRecord(
                id:                record.id,
                date:              record.date,
                fileName:          record.fileName,
                fileType:          record.fileType,
                installedFiles:    record.installedFiles,
                pkgReceiptIDs:     record.pkgReceiptIDs,
                status:            record.status,
                failureReason:     record.failureReason,
                logFileName:       record.logFileName,
                addedHostsEntries: mission.addedHostsEntries,
                titanVerified:     titanVerifyPassed,
                demoDetected:      !titanDemoWarnings.isEmpty
            )
        }

        historyStore.add(fullRecord)

        // ── ATLAS LEARN™ ──────────────────────────────────────────────────────
        if titanVerifyPassed {
            let capturedHosts  = mission.addedHostsEntries
            let capturedSource = mission.plan?.planSource ?? ""
            Task.detached {
                await ATLASLearn.shared.contribute(
                    productName:  sourceName,
                    sourceURL:    mission.sourceURL,
                    installedFiles: mission.installedFiles,
                    pkgReceiptIDs:  mission.installedPKGReceipts,
                    hostsEntries:   capturedHosts,
                    planSource:     capturedSource)
            }
        }

        if !titanDemoWarnings.isEmpty {
            logger.log("⚠️ Demo Mode detected — \(titanDemoWarnings.count) signal(s): \(titanDemoWarnings.map { $0.keyword }.joined(separator: ", "))")
            await MainActor.run {
                pendingDemoAlerts.append(DemoAlert(productName: sourceName, hits: titanDemoWarnings))
            }
        }
        logger.log(Features.rollback ? "📋 TITAN mission saved to history — rollback available" : "📋 TITAN mission saved to history")
    }

    private func installOneFromMultiple(step: TitanMissionStep) {
        guard let mission = activeTitanMission else { return }
        let single = TitanMission(mountPoint: mission.mountPoint, sourceURL: mission.sourceURL)
        single.steps = [step]
        activeTitanMission = single
        showMultipleProductsGate = false
        showTitanMission = true
    }

    private func detachTitanPreScanMount() {
        let mp = titanPreScanMount
        titanPreScanMount = ""
        guard !mp.isEmpty else { return }
        Task.detached(priority: .background) {
            _ = InstallEngine.runProcess(path: "/usr/bin/hdiutil",
                                         arguments: ["detach", mp, "-quiet", "-force"])
        }
    }

    private func typeLabel(_ type_: InstallerType) -> String {
        switch type_ {
        case .dmg: return "DMG"
        case .iso: return "ISO"
        case .zip: return "ZIP"
        case .app:                  return "APP"
        case .interactiveInstaller: return "Interactive Installer"
        case .pkg:                  return "PKG"
        case .component:            return "Component"
        case .vst3:                 return "VST3"
        case .vst:                  return "VST"
        case .aax:                  return "AAX"
        case .kontaktLibrary:       return "Kontakt Library"
        case .exe:                  return "EXE (Wine)"
        case .unsupported(let e):   return e.uppercased()
        }
    }
}

// MARK: - Bottom bar icon button

struct BottomBarIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovered ? Color.atlasLabel : Color.atlasSubtitle)
                .frame(width: 30, height: 30)
                .background(hovered ? Color.atlasHover : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.05 : 1.0)
        .animation(.atlasSnap, value: hovered)
        .onHover { hovered = $0 }
        .help(tooltip)
    }
}

// MARK: - Reusable icon button (history / etc.)

struct AtlasIconButton: View {
    let icon: String
    let tooltip: String
    var isActive: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Color.atlasAccent : Color.atlasSubtitle)
                .frame(width: 30, height: 30)
                .background(
                    isActive
                        ? Color.atlasAccent.opacity(0.10)
                        : (hovered ? Color.atlasHover : Color.atlasPanelBG)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isActive ? Color.atlasAccent.opacity(0.35) : Color.atlasBorderSubtle,
                            lineWidth: 0.75
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.04 : 1.0)
        .animation(.atlasSnap, value: hovered)
        .onHover { hovered = $0 }
        .help(tooltip)
    }
}

// MARK: - Labeled button component

struct AtlasLabelButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(
                isActive ? Color.atlasAccent
                : (hovered ? Color.atlasLabel : Color.atlasSubtitle)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isActive
                    ? Color.atlasAccent.opacity(0.09)
                    : (hovered ? Color.atlasHover : Color.atlasPanelBG)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isActive ? Color.atlasAccent.opacity(0.35) : Color.atlasBorderSubtle,
                        lineWidth: 0.75
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered ? 1.02 : 1.0)
        .animation(.atlasSnap, value: hovered)
        .onHover { hovered = $0 }
    }
}
