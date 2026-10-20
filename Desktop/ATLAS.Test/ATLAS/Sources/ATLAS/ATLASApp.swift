import SwiftUI
import AppKit
import CoreText
import UserNotifications
import Combine
import QuartzCore
import os

@main
struct ATLASApp: App {
    @State private var showSplash = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appearance = AppearanceManager.shared

    private static let alog = os.Logger(subsystem: "digital.interlinked.atlas", category: "app")

    init() {
        // Build stamp — verify in Console.app (filter by subsystem: digital.interlinked.atlas).
        // This appears on every launch when the correct binary is running.
        ATLASApp.alog.notice("[ATLAS-BUILD-v18s] ATLAS launched — fixed self-trash (atlas/interlinked in receipt skipWords); VSCAN now runs in queue path (blocks malware, warns on suspicious/bundled)")
        ATLASApp.registerFonts()
    }

    static func registerFonts() {
        registerFont(resource: "Bezmiar-Regular", ext: "otf")
        registerFont(resource: "SF Intellivised", ext: "ttf")
    }

    private static func registerFont(resource: String, ext: String) {
        let candidates: [URL?] = [
            Bundle.atlasResources.url(forResource: resource, withExtension: ext),
            Bundle.main.url(forResource: resource, withExtension: ext),
            Bundle.main.resourceURL.map { $0.appendingPathComponent("\(resource).\(ext)") },
        ]
        for case let url? in candidates {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var cfError: Unmanaged<CFError>?
            let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &cfError)
            if ok { break }
            if let err = cfError?.takeRetainedValue(), CFErrorGetCode(err) == 105 { break }
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView {
                        withAnimation(.easeIn(duration: 0.4)) {
                            showSplash = false
                        }
                        // Deferred until after splash: both calls read from Keychain
                        // (via loadSession) and must not race the initial window render,
                        // which would trigger the "ATLAS wants to use confidential info"
                        // prompt before the splash is even visible.
                        InstallLogger.captureCrashLogs()
                        InstallLogger.syncExistingLogs()
                    }
                    .transition(.opacity)
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .preferredColorScheme(appearance.override)
            .onAppear { }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - App Delegate
// Handles menu bar icon via NSStatusItem (works on macOS 12+)

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem?
    private var menuStatusCancellable: AnyCancellable?
    private var iconResetTask: Task<Void, Never>?
    // Local-only transition tracker for the completion jiggle. Deliberately
    // separate from MenuBarStatusManager itself — does not alter that
    // publisher's semantics, just observes it to detect one true idle/
    // installing → success transition per logical operation.
    private var previousMenuBarStatus: ATLASMenuStatus = .idle

    // Stored once at launch so we never lose the reference — NSApp.windows.first
    // can return nil or a wrong auxiliary window (sheet/dialog) after orderOut.
    static var mainWindow: NSWindow?

    // Routes files opened via `open -a ATLAS file.iso` to ContentView.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.compactMap { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        openMainWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppState.shared.pendingOpenURLs = urls
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[ATLAS-NOTIF-DIAG] === APP IDENTITY ===")
        print("[ATLAS-NOTIF-DIAG] bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("[ATLAS-NOTIF-DIAG] bundlePath: \(Bundle.main.bundlePath)")
        print("[ATLAS-NOTIF-DIAG] executablePath: \(Bundle.main.executablePath ?? "nil")")
        print("[ATLAS-NOTIF-DIAG] isRunningFromApplications: \(Bundle.main.bundlePath.hasPrefix("/Applications/"))")
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let statusName: String
            switch settings.authorizationStatus {
            case .notDetermined: statusName = "notDetermined"
            case .denied:        statusName = "denied"
            case .authorized:    statusName = "authorized"
            case .provisional:   statusName = "provisional"
            case .ephemeral:     statusName = "ephemeral"
            @unknown default:    statusName = "unknown(\(settings.authorizationStatus.rawValue))"
            }
            print("[ATLAS-NOTIF-DIAG] launch notif status: \(statusName)(\(settings.authorizationStatus.rawValue)) alert=\(settings.alertSetting.rawValue) sound=\(settings.soundSetting.rawValue) badge=\(settings.badgeSetting.rawValue)")
        }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }

        NSApp.activate(ignoringOtherApps: true)
        InstallEngine.cleanupStaleMounts()
        InstallEngine.killLeakedAuthWatchers()
        // Check for queue items that survived a crash or force-quit last session.
        // The UI in ContentView observes pendingResumeURLs and shows a resume prompt.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            InstallQueue.shared.loadPersistedQueueIfNeeded()
        }
        TitanMemory.shared.syncFromCloud()        // pull latest confirmed patterns from Supabase
        TitanMemory.shared.startRealtimeSync()    // live delta updates via Supabase Realtime
        print("[ATLAS-MENUBAR-DIAG] calling setupMenuBarIcon() from applicationDidFinishLaunching")
        setupMenuBarIcon()
        print("[ATLAS-MENUBAR-DIAG] setupMenuBarIcon() returned")

        menuStatusCancellable = MenuBarStatusManager.shared.$menuStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.updateMenuBarIcon(status) }

        // Intercept the red-X close button so it hides instead of destroying the window.
        if let window = NSApp.windows.first {
            AppDelegate.mainWindow = window
            window.delegate = self
            // Reverted: Liquid Chrome Glass shell (transparent window) caused a
            // persistent native-titlebar glass/vibrancy strip behind the traffic
            // lights that could not be cleanly eliminated — see matching config
            // in openMainWindow(). Back to a normal opaque window.
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.titlebarSeparatorStyle = .none
            AppDelegate.hideNativeTitlebarVibrancy(window)
        }

        // Center and fade in on initial launch
        if let window = AppDelegate.mainWindow {
            AppDelegate.centerWindow(window)
            window.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                window.animator().alphaValue = 1
            }
        }
    }

    // UNUserNotificationCenterDelegate — deliver banners and sound while ATLAS is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // NSWindowDelegate — intercept red-X: fade out and hide instead of closing.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            sender.animator().alphaValue = 0
        }, completionHandler: {
            sender.orderOut(nil)
            // Window is still reachable via AppDelegate.mainWindow after orderOut.
        })
        return false  // prevent close() which would remove window from NSApp.windows
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Show a warning if an install, uninstall, or TITAN mission is in progress.
        guard MenuBarStatusManager.shared.menuStatus == .installing else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = L(.quitInstallAlertTitle)
        alert.informativeText = L(.quitInstallAlertBody)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L(.quitAnyway))
        alert.addButton(withTitle: L(.cancel))

        let response = alert.runModal()
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication) -> Bool {
        return false
    }

    // Called every time the user clicks the Dock icon.
    // Returning false tells macOS we handle it ourselves (prevents it from
    // interfering with our fade-in when the window is orderOut'd).
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return false
    }

    private func updateMenuBarIcon(_ status: ATLASMenuStatus) {
        guard let button = statusItem?.button else { return }
        iconResetTask?.cancel()
        iconResetTask = nil

        // Detected locally, before updating the tracker below — does not read
        // from or modify MenuBarStatusManager itself, so its publisher's
        // semantics/behavior for the rest of the app are unchanged.
        let transitionedToSuccess = (status == .success && previousMenuBarStatus != .success)
        previousMenuBarStatus = status

        switch status {
        case .idle:
            // The approved ATLAS ✧ identity (Candidate A), not the generic
            // system "sparkle" symbol — the app's resting/idle icon.
            button.image = ATLASMenuBarIcon.image()

        case .installing, .success, .failure:
            let (symbolName, resetAfter): (String, Bool) = {
                switch status {
                case .installing: return ("arrow.down.circle", false)
                case .success:    return ("checkmark.circle",  true)
                case .failure:    return ("xmark.circle",      true)
                case .idle:       fatalError("unreachable")
                }
            }()

            button.image = NSImage(systemSymbolName: symbolName,
                                   accessibilityDescription: "ATLAS")
            button.image?.isTemplate = true

            if resetAfter {
                iconResetTask = Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { MenuBarStatusManager.shared.menuStatus = .idle }
                }
            }
        }

        // Success only — no jiggle for failure or cancellation (cancellation
        // routes to .idle directly at its existing call sites, never .success).
        if transitionedToSuccess {
            jiggleMenuBarIcon()
        }
    }

    /// Brief, restrained completion acknowledgment — a small rotational
    /// "jiggle" on the status item's own button layer. Pure Core Animation,
    /// runs independently of and cannot block/interfere with any install,
    /// uninstall, or rollback work (which lives entirely in Engine/).
    private func jiggleMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        let anim = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let a: CGFloat = 0.16   // ~9°, restrained
        anim.values = [0, a, -a, a * 0.6, -a * 0.6, a * 0.25, 0]
        anim.keyTimes = [0, 0.16, 0.38, 0.58, 0.76, 0.9, 1]
        anim.duration = 0.45
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(anim, forKey: "atlasMenuBarJiggle")
    }

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)

        print("[ATLAS-MENUBAR-DIAG] statusItem non-nil: \(statusItem != nil)")
        print("[ATLAS-MENUBAR-DIAG] statusItem?.isVisible: \(String(describing: statusItem?.isVisible))")
        print("[ATLAS-MENUBAR-DIAG] statusItem?.length: \(String(describing: statusItem?.length))")
        print("[ATLAS-MENUBAR-DIAG] statusItem?.button exists: \(statusItem?.button != nil)")

        if let button = statusItem?.button {
            // Approved ATLAS ✧ identity (Candidate A — Signature Sparkle),
            // replacing the generic system "sparkle" SF Symbol.
            button.image = ATLASMenuBarIcon.image()
            button.action = #selector(statusBarButtonClicked)
            button.target = self
            print("[ATLAS-MENUBAR-DIAG] configured icon: ATLASMenuBarIcon (Candidate A)")
            print("[ATLAS-MENUBAR-DIAG] button.image non-nil after assignment: \(button.image != nil)")
            print("[ATLAS-MENUBAR-DIAG] button.image?.isTemplate: \(String(describing: button.image?.isTemplate))")
        } else {
            print("[ATLAS-MENUBAR-DIAG] statusItem?.button was nil — could not configure image")
        }

        // Build the menu
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "ATLAS by InterLinked",
                                   action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: L(.menuOpenAtlas),
            action: #selector(openMainWindow),
            keyEquivalent: "o"))

        menu.addItem(NSMenuItem(
            title: L(.viewLogs),
            action: #selector(openLogs),
            keyEquivalent: ""))

        menu.addItem(NSMenuItem(
            title: L(.checkForUpdates),
            action: #selector(checkForUpdates),
            keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: L(.menuQuitAtlas),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))

        // Set targets
        for item in menu.items {
            if item.action == #selector(openMainWindow) ||
               item.action == #selector(openLogs) ||
               item.action == #selector(checkForUpdates) {
                item.target = self
            }
        }

        statusItem?.menu = menu
    }

    @objc private func statusBarButtonClicked() {
        openMainWindow()
    }

    @objc func openMainWindow() {
        // Prefer the stored reference; fall back to the first app window.
        guard let window = AppDelegate.mainWindow ?? NSApp.windows.first else { return }

        window.level = .normal
        // Liquid Chrome Glass shell: transparent window so ContentView's root
        // .atlasGlass(.shell) material (NSVisualEffectView + chrome edge) is the
        // actual visible surface, not a flat opaque fill. Sizing/resizing/close
        // behavior below is unchanged.
        // Reverted: see matching note in applicationDidFinishLaunching — back to
        // a normal opaque window, no transparent glass shell.
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.titlebarSeparatorStyle = .none
        AppDelegate.hideNativeTitlebarVibrancy(window)
        [NSWindow.ButtonType.closeButton,
         .miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = false
        }
        window.styleMask.remove(.resizable)
        window.minSize = CGSize(width: 760, height: 500)
        window.maxSize = CGSize(width: 760, height: 500)
        AppDelegate.centerWindow(window)

        // Order front and activate BEFORE updating SwiftUI state — this ensures
        // the window is on-screen before SwiftUI re-renders into it.
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in, then update SwiftUI state so mainLayout renders cleanly.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            window.animator().alphaValue = 1
        }
    }

    /// Hides AppKit's native titlebar vibrancy/backdrop layers so the ATLAS
    /// SwiftUI glass (which spans the full window, including under the
    /// traffic lights) is the only material visible behind them — no second,
    /// competing native fill left to create a visually distinct "bar".
    /// Confirmed via runtime view-hierarchy inspection that there are TWO
    /// independent native sources inside NSTitlebarView, both siblings of the
    /// close/zoom/miniaturize widgets, not ancestors — hiding either does not
    /// affect the buttons themselves:
    ///   1. An NSVisualEffectView (material: .titlebar).
    ///   2. A plain NSView backed directly by a CABackdropLayer
    ///      (groupName "NSTitlebarViewBackdropLayer") — a lower-level,
    ///      separate vibrancy mechanism that survives hiding #1 alone.
    /// Both are matched by their actual view/layer type, not a hardcoded
    /// subview index, so this stays resilient to AppKit's own internal
    /// subview ordering. Reached via the public
    /// standardWindowButton(.closeButton)?.superview anchor.
    static func hideNativeTitlebarVibrancy(_ window: NSWindow) {
        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }
        for subview in titlebarView.subviews {
            if subview is NSVisualEffectView {
                subview.isHidden = true
            } else if let layerClassName = subview.layer.map({ String(describing: type(of: $0)) }),
                      layerClassName.contains("Backdrop") {
                // CABackdropLayer is a private QuartzCore class (not
                // importable as a Swift type), so it's matched by its
                // runtime class name instead of a static type check.
                subview.isHidden = true
            }
        }
    }

    /// Resets the window to the default ATLAS size and centers it on the
    /// screen the user is currently working on (where the cursor is).
    static func centerWindow(_ window: NSWindow) {
        let fixedSize = NSSize(width: 760, height: 500)
        window.styleMask.remove(.resizable)
        window.minSize = fixedSize
        window.maxSize = fixedSize
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                  ?? NSScreen.main
                  ?? NSScreen.screens.first
        if let screen = screen {
            let sf = screen.visibleFrame
            let origin = NSPoint(
                x: sf.midX - fixedSize.width  / 2,
                y: sf.midY - fixedSize.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: fixedSize),
                            display: true, animate: false)
        } else {
            window.setContentSize(fixedSize)
            window.center()
        }
    }

    @objc private func openLogs() {
        InstallLogger.openLogsInFinder()
    }

    // v1: informational only — no network/version check, no Sparkle, no
    // automatic updater. Opens the main window and shows a simple notice
    // that updates ship on the website when v2 is announced. See
    // UI/UpdateNoticeView.swift.
    @objc private func checkForUpdates() {
        openMainWindow()
        NotificationCenter.default.post(name: .atlasShowUpdateNotice, object: nil)
    }

}

// MARK: - Notification Helper

struct ATLASNotification {
    private static let notifKey = "ATLAS.notificationsEnabled"

    static func send(title: String, body: String) {
        // Respect the toggle in Settings — only send if user enabled notifications
        let prefEnabled = UserDefaults.standard.bool(forKey: notifKey)
        guard prefEnabled else {
            print("[ATLAS-NOTIF-DIAG] ATLASNotification.send() BLOCKED — ATLAS.notificationsEnabled=false in UserDefaults")
            return
        }
        print("[ATLAS-NOTIF-DIAG] ATLASNotification.send() PROCEEDING — title='\(title)' pref=true")

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        print("[ATLAS-NOTIF-DIAG] ATLASNotification.send() — add(request) called (no completion handler; errors not surfaced)")
    }
}
