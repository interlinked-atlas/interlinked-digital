import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState.shared
    @StateObject private var logger = Logger()
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var queue = InstallQueue()
    @State private var isTargeted = false
    @State private var needsAgreements      = !UserDefaults.standard.bool(forKey: CombinedAgreementView.tosKey)
                                           || !UserDefaults.standard.bool(forKey: CombinedAgreementView.privacyKey)
    @State private var needsPasswordSetup   = !KeychainManager.hasPassword()
    // Always re-check real permission state on every launch, not just onboarding flag.
    // Accessibility and FDA are fast sync checks; automation is verified async below.
    @State private var needsPermissionsSetup: Bool = {
        !PermissionsManager.hasCompletedOnboarding ||
        !PermissionsManager.hasAccessibility ||
        !PermissionsManager.hasFullDiskAccess
    }()
    @State private var unsupportedExtension: String? = nil
    @State private var showHistory = false
    @State private var rollingBack: InstallRecord? = nil
    @State private var rollbackInProgress = false
    @State private var rollbackProgress: Double = 0.0
    @State private var rollbackStep: String = ""
    @State private var rollbackQueue: [InstallRecord] = []
    @State private var rollbackQueueTotal: Int = 0
    @State private var rollbackQueueDone: Int = 0
    @State private var batchRollbackResults: [(InstallRecord, RollbackResult)] = []
    @State private var showRosetta = false
    @State private var uninstallResult: RollbackResult? = nil
    @State private var showDropZone = true
    @State private var showCancelConfirm = false
    @State private var queueTask: Task<Void, Never>? = nil
    @State private var pluginScanResults: [PluginCheckResult] = []
    @State private var showPluginScan = false
    @ObservedObject private var widgetState  = WidgetStateManager.shared
    @ObservedObject private var appearance   = AppearanceManager.shared
    @ObservedObject private var titanCore    = TitanCore.shared
    @ObservedObject private var auth         = AuthManager.shared
    @ObservedObject private var dailyLimit   = DailyLimitManager.shared
    @State private var widgetTimer: Task<Void, Never>? = nil
    @State private var showSettings  = false
    @State private var showAbout     = false
    @State private var showUpgrade   = false
    @State private var upgradeFeature = ""
    @State private var showStorageSelection = false
    @State private var pendingInstallURL: URL? = nil
    @State private var pendingScanResult: ScanResult? = nil
    @AppStorage("atlasGreetingShown") private var greetingShown = false
    @State private var showAtlasSelfInstallAlert = false
    // TITAN CORE™ mission state
    @State private var activeTitanMission: TitanMission? = nil
    @State private var showTitanMission            = false
    @State private var showTitanNoInstructions     = false
    @State private var showMultipleProductsGate    = false
    @State private var showComplexInstallGate      = false
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
            } else if needsPasswordSetup {
                PasswordSetupView { needsPasswordSetup = false }
                    .atlasBackground()
            } else if needsPermissionsSetup {
                PermissionsSetupView { needsPermissionsSetup = false }
            } else {
                mainLayout
            }
        }
        .preferredColorScheme(appearance.override)
        .sheet(isPresented: $showAbout) { AboutView() }
        .sheet(isPresented: $showUpgrade) {
            UpgradeView(feature: upgradeFeature) { showUpgrade = false }
        }
        // Standard plan — multiple products gate
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
        // Complex install gate — shown when blind TITAN scan finds scripts/binaries
        .sheet(isPresented: $showComplexInstallGate) {
            if let mission = activeTitanMission {
                let pkgSteps = mission.steps.filter {
                    if case .installPkg = $0.action { return true }
                    return false
                }
                ComplexInstallGateView(
                    pkgSteps: pkgSteps,
                    onInstallPKGOnly: pkgSteps.isEmpty ? nil : {
                        // Build a PKG-only mission and hand off to TitanMissionView
                        let pkgMission = TitanMission(
                            mountPoint: mission.mountPoint,
                            sourceURL:  mission.sourceURL)
                        pkgMission.steps = pkgSteps
                        activeTitanMission = pkgMission
                        showComplexInstallGate = false
                        showTitanMission = true
                    },
                    onDismiss: {
                        showComplexInstallGate = false
                        activeTitanMission = nil
                        detachTitanPreScanMount()
                        appState.reset()
                        withAnimation { showDropZone = true }
                    }
                )
            }
        }
        // TITAN CORE™ No Instructions dialog
        .sheet(isPresented: $showTitanNoInstructions) {
            TitanNoInstructionsView(
                detectedFiles: titanNoInstrFiles,
                onProvide: {
                    showTitanNoInstructions = false
                    // Open file picker for instruction file
                    let panel = NSOpenPanel()
                    panel.title = "Select Installation Instructions"
                    panel.allowedContentTypes = [.html, .text, .rtf, .pdf]
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url,
                       let mission = activeTitanMission {
                        // Copy instruction file to mount point and rebuild mission
                        let capturedMountPoint = titanMountPoint
                        let dest = URL(fileURLWithPath: capturedMountPoint)
                            .appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        Task.detached(priority: .userInitiated) {
                            let plan = await InstallIntelligence.analyze(
                                directory: capturedMountPoint, files: [])
                            let scan = InstallIntelligence.titanScan(directory: capturedMountPoint)
                            await MainActor.run {
                                mission.buildMission(plan: plan, scan: scan)
                                showTitanMission = true
                            }
                        }
                    }
                },
                onAttempt: {
                    showTitanNoInstructions = false
                    guard let mission = activeTitanMission else { return }
                    // Check if mission contains scripts or binaries — these
                    // require instruction-guided automation ATLAS hasn't fully
                    // validated yet. Gate them with a graceful "coming soon" screen.
                    let hasComplexSteps = mission.steps.contains {
                        if case .runScript = $0.action { return true }
                        if case .runBinary = $0.action { return true }
                        return false
                    }
                    if hasComplexSteps {
                        showComplexInstallGate = true
                    } else {
                        showTitanMission = true
                    }
                },
                onCancel: {
                    showTitanNoInstructions = false
                    activeTitanMission = nil
                    detachTitanPreScanMount()
                    withAnimation { showDropZone = true }
                }
            )
            .background(Color(hex: "#07080F"))
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
    }

    var mainLayout: some View {
        ZStack {
            if widgetState.isWidgetMode {
                WidgetView(appState: appState, queue: queue, onExpand: exitWidgetMode, onClose: {
                    // Use the stored main window reference — NSApp.windows.first is
                    // unreliable after orderOut and can return sheets/auxiliary windows.
                    if let w = AppDelegate.mainWindow {
                        // Undo every property changed by resizeWindow(toWidget: true)
                        w.level = .normal
                        w.isOpaque = true
                        w.backgroundColor = .windowBackgroundColor
                        w.minSize = CGSize(width: 520, height: 460)
                        w.maxSize = CGSize(width: 99999, height: 99999)
                        [NSWindow.ButtonType.closeButton,
                         .miniaturizeButton, .zoomButton].forEach {
                            w.standardWindowButton($0)?.isHidden = false
                        }
                        AppDelegate.centerWindow(w)
                        // Fade to invisible — no orderOut so Dock/menu-bar can always
                        // find and restore the window via makeKeyAndOrderFront.
                        NSAnimationContext.runAnimationGroup({ ctx in
                            ctx.duration = 0.22
                            w.animator().alphaValue = 0
                        }, completionHandler: {
                            // Set AFTER fade so SwiftUI re-render doesn't fight AppKit
                            // while the window is still animating on screen.
                            WidgetStateManager.shared.isWidgetMode = false
                        })
                    } else {
                        WidgetStateManager.shared.isWidgetMode = false
                    }
                })
            } else {
                HStack(spacing: 0) {
                    mainView.frame(minWidth: 520)
                    if showHistory {
                        Rectangle()
                            .fill(Color.atlasBorder)
                            .frame(width: 1)
                        HistoryPanelView(
                            store: historyStore,
                            logger: logger,
                            onRollback: { record in
                                if !Features.rollback {
                                    upgradeFeature = "Uninstall & Rollback"
                                    showUpgrade = true
                                } else {
                                    beginBatchUninstall(records: [record])
                                }
                            },
                            onRestore:  { record in
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
                        .transition(.move(edge: .trailing))
                    }
                }
                .frame(minWidth: showHistory ? 780 : 540, minHeight: 460)
                .atlasBackground()
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: showHistory)
            }
        }
        .onChange(of: showHistory) { visible in
            guard let window = AppDelegate.mainWindow ?? NSApp.windows.first else { return }
            let currentH = window.frame.height
            let targetW: CGFloat = visible ? 800 : 560
            let currentX = window.frame.origin.x
            let currentY = window.frame.origin.y
            // Keep the window anchored; only grow/shrink width
            let newX = max(currentX, 0)
            window.minSize = CGSize(width: 1, height: 1)
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(
                    NSRect(x: newX, y: currentY, width: targetW, height: currentH),
                    display: true)
            }, completionHandler: {
                window.minSize = CGSize(width: visible ? 780 : 540, height: 460)
            })
        }
        .onChange(of: historyStore.records.isEmpty) { isEmpty in
            if isEmpty { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showHistory = false } }
        }
        .onChange(of: queue.isProcessing) { processing in
            if processing { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showHistory = false } }
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
            widgetState.startIdleMonitoring()
        }
        .onDisappear {
            widgetState.stopIdleMonitoring()
        }
        .task {
            // Automation check is slow (spawns osascript) — run non-blocking.
            PermissionsManager.checkAutomationPermission { granted in
                if !granted { needsPermissionsSetup = true }
            }
        }
    }

    var mainView: some View {
        VStack(spacing: 0) {
            titleBar
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)

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
            SettingsView()
        }
    }

    // MARK: - Bottom bar

    var bottomBar: some View {
        HStack(spacing: 0) {
            // Settings
            BottomBarIconButton(icon: "gearshape", tooltip: "Settings") {
                showSettings = true
            }

            // Logs
            BottomBarIconButton(icon: "doc.text", tooltip: "Open Logs in Finder") {
                InstallLogger.openLogsInFinder()
            }

            // TITAN CORE™ live action indicator (Pro only, shown while active)
            if Features.titanCore && titanCore.isActive && !titanCore.currentAction.isEmpty {
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

            AppearanceToggle()
                .padding(.trailing, 12)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.atlasDeepBG)
        .overlay(alignment: .top) {
            Color.atlasBorderSubtle.frame(height: 0.5)
        }
    }

    // MARK: - Title bar

    var titleBar: some View {
        HStack(spacing: 12) {
            // Logo + ATLAS name — tap opens About
            Button { showAbout = true } label: {
                HStack(spacing: 9) {
                    AtlasStarView(size: 30, isAnimating: true)
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
            }

            Spacer()

            HStack(spacing: 5) {
                AtlasLabelButton(
                    icon: "clock",
                    label: "History",
                    isActive: showHistory
                ) {
                    withAnimation(.atlasSpring) { showHistory.toggle() }
                }

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
                "Cancel in progress?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel Installation", role: .destructive) { performCancel() }
                Button("Continue", role: .cancel) {}
            } message: {
                Text("Canceling while an installation is in progress may leave software partially installed. Items already completed will remain. Are you sure?")
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
            if active && appState.progress > 0 {
                ATLASProgressBar(
                    progress: appState.progress,
                    stepLabel: appState.progressStep
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Main content

    @ViewBuilder
    var mainContent: some View {
        // Standard plan: pending files ready to continue after lock expires
        if !auth.isPro && dailyLimit.hasPendingFiles && !dailyLimit.isLocked && showDropZone {
            pendingFilesPanel
        }

        if showDropZone && !rollbackInProgress {
            if !auth.isPro && dailyLimit.isLocked {
                dailyLimitLockedZone
            } else {
                // Standard: show remaining installs counter while not locked
                if !auth.isPro {
                    let rem = dailyLimit.remainingToday
                    if rem < DailyLimitManager.dailyLimit {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("\(rem) install\(rem == 1 ? "" : "s") remaining today")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("Standard")
                                .font(.system(size: 9.5, weight: .semibold))
                                .tracking(0.3)
                                .foregroundStyle(Color(hex: "#5B8DEF"))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#5B8DEF").opacity(0.09))
                                .clipShape(Capsule())
                                .overlay(Capsule().strokeBorder(Color(hex: "#5B8DEF").opacity(0.25), lineWidth: 0.75))
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

                DropZoneView(isTargeted: $isTargeted) { urls in
                    unsupportedExtension = nil
                    handleFilesDrop(urls: urls)
                } onUnsupported: { ext in
                    unsupportedExtension = ext
                }
            }
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
                }
            )
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

    // MARK: - Daily limit UI

    var dailyLimitLockedZone: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let t  = dailyLimit.timeUntilReset
            let hh = Int(t) / 3600
            let mm = (Int(t) % 3600) / 60
            let ss = Int(t) % 60
            let countdown = String(format: "%02d:%02d:%02d", hh, mm, ss)

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
                        Text("Daily install limit reached")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "#F0A030"))
                        Text("Standard plan: \(DailyLimitManager.dailyLimit) installs per 24 hours")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7399"))
                    }

                    if dailyLimit.hasPendingFiles {
                        HStack(spacing: 5) {
                            Image(systemName: "clock.badge.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#6B7399"))
                            Text("\(dailyLimit.pendingURLs.count) file\(dailyLimit.pendingURLs.count == 1 ? "" : "s") pending")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#6B7399"))
                        }
                    }

                    HStack(spacing: 5) {
                        Image(systemName: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7399"))
                        Text("Unlocks in \(countdown)")
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundColor(Color(hex: "#D0D8F0"))
                    }

                    Button {
                        upgradeFeature = "Unlimited Installs"
                        showUpgrade = true
                    } label: {
                        Text("Upgrade to Pro — No Limits")
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
                Text("\(dailyLimit.pendingURLs.count) file\(dailyLimit.pendingURLs.count == 1 ? "" : "s") queued from yesterday's session")
                    .font(.system(size: 11))
                    .foregroundColor(Color.atlasSubtitle)
            }

            Spacer()

            Button("Continue Install") {
                let urls = dailyLimit.pendingURLs
                dailyLimit.clearPending()
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
                        .foregroundColor(Color(hex: "#6B7399"))
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
                        .foregroundColor(Color(hex: "#6B7399"))
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
                Text("Install more")
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
                    stepLabel: rollbackStep.isEmpty ? "Preparing…" : "Moving \(rollbackStep) to Trash…",
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
            guard !dailyLimit.isLocked else { return }

            if urls.count > 1 {
                // Cap at remaining daily installs — store overflow as pending
                let remaining = dailyLimit.remainingToday
                guard remaining > 0 else { return }
                let toInstall = Array(urls.prefix(remaining))
                let pending   = Array(urls.dropFirst(remaining))
                if !pending.isEmpty { dailyLimit.setPending(pending) }
                greetingShown = true
                for url in toInstall { queue.add(url: url) }
                withAnimation { showDropZone = true }
                return
            }
        } else {
            // Pro: keep existing bulk-install queue path for multiple files
            if urls.count > 1 {
                greetingShown = true
                for url in urls { queue.add(url: url) }
                withAnimation { showDropZone = true }
                return
            }
        }

        // Dismiss first-launch greeting permanently
        greetingShown = true

        if urls.count == 1 && !queue.hasItems && appState.phase == .idle {
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

        if Features.titanCore && TitanCore.shared.isAvailable && (isMountable || isFolder) && !isPluginBundle {
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
                        // Standard plan: gate multi-product installs
                        showMultipleProductsGate = true
                    } else if scan.hasInstructions {
                        showTitanMission = true
                    } else {
                        titanNoInstrFiles = fileNames
                        showTitanNoInstructions = true
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

    // Called from ScanResultView. Routes through storage selection for large Pro installs.
    private func beginInstallFromScan(url: URL, scanResult: ScanResult) {
        if Features.smartStorage && scanResult.requiresStorageSelection {
            pendingInstallURL  = url
            pendingScanResult  = scanResult
            showStorageSelection = true
        } else {
            beginInstall(url: url)
        }
    }

    private func beginInstall(url: URL) {
        // Record single-file install against daily limit (Standard only)
        dailyLimit.recordInstall()
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
            case .success(let name):
                ATLASNotification.send(
                    title: "Installation Complete",
                    body: "\(name) installed successfully.")
                WidgetStateManager.shared.menuStatus = .success
            case .failure(let reason):
                ATLASNotification.send(
                    title: "Installation Failed",
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
            let remaining = dailyLimit.remainingToday
            if queue.items.count > remaining {
                let overflow = Array(queue.items.dropFirst(remaining))
                dailyLimit.setPending(overflow.map { $0.url })
                for item in overflow { queue.remove(id: item.id) }
            }
        }

        withAnimation { showDropZone = false }
        queue.isProcessing = true
        InstallEngine.resetCancellation()
        logger.log("--- Queue started: \(queue.items.count) file(s) ---")
        WidgetStateManager.shared.menuStatus = .installing
        startWidgetTimer()

        // All items in this queue run share a session ID for batch-uninstall grouping
        let sessionID = UUID()

        queueTask = Task {
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
                    status: scanResult.canInstall ? .waiting : .failure("Confidence too low")
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
            logger.log("--- Queue complete ---")
            cancelWidgetTimer()
            exitWidgetMode()
            if !pluginScanResults.isEmpty {
                withAnimation { showPluginScan = true }
            }

            let succeeded = queue.items.filter {
                if case .success = $0.status { return true }; return false }.count
            let failed = queue.items.filter {
                if case .failure = $0.status { return true }; return false }.count
            ATLASNotification.send(
                title: "ATLAS — Queue Complete",
                body: "\(succeeded) installed successfully" +
                      (failed > 0 ? ", \(failed) failed." : ".")
            )
            WidgetStateManager.shared.menuStatus = failed > 0 ? .failure : .success
        }
    }

    private func runInstallItem(id: UUID, sessionID: UUID) async {
        guard !InstallEngine.cancellationRequested else {
            queue.updateStatus(id: id, status: .failure("Cancelled"))
            return
        }
        guard let item = queue.items.first(where: { $0.id == id }) else { return }
        // Record against daily limit per queued file (Standard only)
        await MainActor.run { dailyLimit.recordInstall() }
        queue.updateStatus(id: id, status: .installing)
        logger.log("Installing: \(item.fileName)")

        let (result, installedFiles, receiptIDs, isPlugin) =
            await InstallEngine.install(url: item.url, logger: logger) { pct, step in
                self.queue.updateProgress(id: id, progress: pct, step: step)
            }

        let type_    = InstallerClassifier.classify(url: item.url)
        let fileType = typeLabel(type_)
        let record   = InstallLogger.writeLog(
            fileURL: item.url, fileType: fileType,
            entries: logger.entries, result: result,
            installedFiles: installedFiles, pkgReceiptIDs: receiptIDs,
            sessionID: sessionID)

        historyStore.add(record)
        let logContent = logger.entries.joined(separator: "\n")
        switch result {
        case .success(let name):
            queue.updateStatus(id: id, status: .success)
            queue.updateProgress(id: id, progress: 1.0, step: "")
            logger.log("  ✓ Installed: \(name)")
            if isPlugin && RosettaEngine.isAppleSilicon {
                withAnimation { showRosetta = true }
            }
            // Accumulate plugin scan results from queue installs
            let newScanResults = PluginScanner.scan(installedFiles: installedFiles)
            if !newScanResults.isEmpty {
                pluginScanResults.append(contentsOf: newScanResults)
            }
            syncInstallLog(logType: "install", appName: name, fileName: item.fileName, content: logContent)
        case .failure(let reason):
            queue.updateStatus(id: id, status: .failure(reason))
            logger.log("  ✗ Failed: \(reason)")
            syncInstallLog(logType: "failed", appName: item.fileName, fileName: item.fileName, content: logContent)
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

        Task {
            let result = await RollbackEngine.rollback(
                record: record, logger: logger
            ) { progress, step in
                Task { @MainActor in
                    rollbackProgress = progress
                    rollbackStep = step
                }
            }
            await MainActor.run {
                rollbackInProgress = false
                rollbackProgress   = 1.0
                rollbackStep       = ""
                rollbackQueueDone += 1

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
        } else {
            InstallEngine.cancelCurrentInstall()
            queueTask?.cancel()
            queueTask = nil
            // Mark remaining waiting/installing items as cancelled
            for item in queue.items {
                switch item.status {
                case .waiting, .installing, .scanning:
                    queue.updateStatus(id: item.id, status: .failure("Cancelled"))
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
        widgetState.cancelIdleCollapse()   // no countdown needed while already collapsed
        widgetState.isWidgetMode = true
        resizeWindow(toWidget: true)
    }

    private func exitWidgetMode() {
        guard widgetState.isWidgetMode else { return }
        // Use the stored mainWindow reference — NSApp.windows.first is unreliable
        // when sheets or auxiliary windows are open.
        let window = AppDelegate.mainWindow ?? NSApp.windows.first
        window?.minSize = CGSize(width: 1, height: 1)
        window?.maxSize = CGSize(width: 99999, height: 99999)
        widgetState.isWidgetMode = false
        // Brief pause lets SwiftUI finish swapping WidgetView → mainLayout
        // before AppKit resizes the frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            self.resizeWindow(toWidget: false)
        }
        // Restart the idle countdown so ATLAS will collapse again if left alone
        widgetState.scheduleIdleCollapse()
    }

    private func resizeWindow(toWidget: Bool) {
        guard let window = AppDelegate.mainWindow ?? NSApp.windows.first else { return }

        if toWidget {
            let screen = window.screen ?? NSScreen.main ?? NSScreen.screens[0]
            let pad: CGFloat = 20
            let w: CGFloat = 320
            let h: CGFloat = 92

            window.isOpaque = false
            window.backgroundColor = .clear
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
            window.level = .normal
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
        let sourceName = mission.sourceURL.lastPathComponent
        // Only PKG installs are critical — script/binary failures don't mean the
        // software wasn't installed (all receipts may still be present).
        let hasFailed  = mission.steps.contains(where: {
            guard $0.status == .failed else { return false }
            if case .installPkg = $0.action { return true }
            return false
        })

        // Build detailed log entries — include resultNote so failures are diagnosable
        let entries: [String] = mission.steps.map { step in
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

        // Always write the log — every plan gets a record of what happened
        let record = InstallLogger.writeLog(
            fileURL:      mission.sourceURL,
            fileType:     mission.sourceURL.pathExtension.uppercased().isEmpty
                              ? "Install"
                              : mission.sourceURL.pathExtension.uppercased(),
            entries:      entries,
            result:       hasFailed
                            ? .failure(reason: failureReason)
                            : .success(appName: sourceName),
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

        // All users see history. Pro users also get hosts-entries rollback data.
        var fullRecord = record
        if Features.rollback && !mission.addedHostsEntries.isEmpty {
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
                addedHostsEntries: mission.addedHostsEntries
            )
        }

        historyStore.add(fullRecord)
        logger.log(Features.rollback ? "📋 TITAN mission saved to history — rollback available" : "📋 TITAN mission saved to history")
    }

    private func installOneFromMultiple(step: TitanMissionStep) {
        guard let mission = activeTitanMission else { return }
        // Build a new single-step mission so the user installs only the chosen item
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
        case .app: return "APP"
        case .pkg: return "PKG"
        case .component: return "Component"
        case .vst3: return "VST3"
        case .vst: return "VST"
        case .aax: return "AAX"
        case .kontaktLibrary: return "Kontakt Library"
        case .unsupported(let e): return e.uppercased()
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
