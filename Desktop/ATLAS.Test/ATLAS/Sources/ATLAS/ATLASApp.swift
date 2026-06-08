import SwiftUI
import AppKit
import CoreText
import UserNotifications
import Combine

@main
struct ATLASApp: App {
    @State private var showSplash = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        ATLASApp.registerFonts()
    }

    static func registerFonts() {
        registerFont(resource: "Bezmiar-Regular", ext: "otf")
        registerFont(resource: "SF Intellivised", ext: "ttf")
    }

    private static func registerFont(resource: String, ext: String) {
        let candidates: [URL?] = [
            Bundle.module.url(forResource: resource, withExtension: ext),
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
                    }
                    .transition(.opacity)
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            .onAppear { }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

// MARK: - App Delegate
// Handles menu bar icon via NSStatusItem (works on macOS 12+)

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    private var menuStatusCancellable: AnyCancellable?
    private var iconResetTask: Task<Void, Never>?

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
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }

        NSApp.activate(ignoringOtherApps: true)
        InstallLogger.captureCrashLogs()
        InstallLogger.syncExistingLogs()
        InstallEngine.cleanupStaleMounts()
        setupMenuBarIcon()

        menuStatusCancellable = WidgetStateManager.shared.$menuStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.updateMenuBarIcon(status) }

        // Intercept the red-X close button so it hides instead of destroying the window.
        if let window = NSApp.windows.first {
            AppDelegate.mainWindow = window
            window.delegate = self
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
        guard WidgetStateManager.shared.menuStatus == .installing else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Installation in Progress"
        alert.informativeText = "ATLAS is currently performing an installation or operation. Quitting now may leave files in an incomplete state.\n\nAre you sure you want to quit?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")

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

        let (symbolName, resetAfter): (String, Bool) = {
            switch status {
            case .idle:       return ("sparkle",             false)
            case .installing: return ("arrow.down.circle",   false)
            case .success:    return ("checkmark.circle",    true)
            case .failure:    return ("xmark.circle",        true)
            }
        }()

        button.image = NSImage(systemSymbolName: symbolName,
                               accessibilityDescription: "ATLAS")
        button.image?.isTemplate = true

        if resetAfter {
            iconResetTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { WidgetStateManager.shared.menuStatus = .idle }
            }
        }
    }

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkle",
                                  accessibilityDescription: "ATLAS")
            button.image?.isTemplate = true
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }

        // Build the menu
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "ATLAS by InterLinked",
                                   action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Open ATLAS",
            action: #selector(openMainWindow),
            keyEquivalent: "o"))

        menu.addItem(NSMenuItem(
            title: "View Logs",
            action: #selector(openLogs),
            keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit ATLAS",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))

        // Set targets
        for item in menu.items {
            if item.action == #selector(openMainWindow) ||
               item.action == #selector(openLogs) {
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

        // Cancel any pending idle-collapse so the window doesn't immediately
        // re-collapse to widget mode the moment it appears.
        WidgetStateManager.shared.cancelIdleCollapse()

        // Reset all AppKit widget-mode properties before ordering the window front.
        // Do this BEFORE makeKeyAndOrderFront so the layout is correct when visible.
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        [NSWindow.ButtonType.closeButton,
         .miniaturizeButton, .zoomButton].forEach {
            window.standardWindowButton($0)?.isHidden = false
        }
        window.minSize = CGSize(width: 560, height: 580)
        window.maxSize = CGSize(width: 99999, height: 99999)
        AppDelegate.centerWindow(window)

        // Order front and activate BEFORE updating SwiftUI state — this ensures
        // the window is on-screen before SwiftUI re-renders into it.
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in, then update SwiftUI state so mainLayout renders cleanly.
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            window.animator().alphaValue = 1
        }, completionHandler: {
            // Set on main queue after the window is fully visible.
            DispatchQueue.main.async {
                WidgetStateManager.shared.isWidgetMode = false
            }
        })
    }

    /// Resets the window to the default ATLAS size and centers it on the
    /// screen the user is currently working on (where the cursor is).
    static func centerWindow(_ window: NSWindow) {
        let defaultSize = NSSize(width: 600, height: 620)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
                  ?? NSScreen.main
                  ?? NSScreen.screens.first
        if let screen = screen {
            let sf = screen.visibleFrame
            let origin = NSPoint(
                x: sf.midX - defaultSize.width  / 2,
                y: sf.midY - defaultSize.height / 2
            )
            window.setFrame(NSRect(origin: origin, size: defaultSize),
                            display: true, animate: false)
        } else {
            window.setContentSize(defaultSize)
            window.center()
        }
    }

    @objc private func openLogs() {
        InstallLogger.openLogsInFinder()
    }
}

// MARK: - Notification Helper

struct ATLASNotification {
    private static let notifKey = "ATLAS.notificationsEnabled"

    static func send(title: String, body: String) {
        // Respect the toggle in Settings — only send if user enabled notifications
        guard UserDefaults.standard.bool(forKey: notifKey) else { return }

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
    }
}
