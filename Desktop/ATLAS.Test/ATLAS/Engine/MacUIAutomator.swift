import Cocoa
import ApplicationServices

// MARK: - MacUIAutomator
// Desktop UI automation for TITAN CORE™.
// Drives any macOS app via the Accessibility API — same permission ATLAS already
// requests during onboarding for password-dialog automation.

struct MacUIAutomator {

    // MARK: - App discovery

    static func findApp(named name: String) -> NSRunningApplication? {
        let q = name.lowercased()
        return NSWorkspace.shared.runningApplications.first {
            ($0.localizedName ?? "").lowercased().contains(q) ||
            ($0.bundleIdentifier ?? "").lowercased().contains(q)
        }
    }

    // MARK: - Launch

    /// Opens an .app URL and waits up to `timeout` seconds for it to finish launching.
    @discardableResult
    static func launch(url: URL, timeout: TimeInterval = 30) async -> NSRunningApplication? {
        let appName = url.deletingPathExtension().lastPathComponent
        NSWorkspace.shared.open(url)
        _ = await waitFor(timeout: timeout) {
            findApp(named: appName)?.isFinishedLaunching == true
        }
        return findApp(named: appName)
    }

    // MARK: - AX element access

    static func axApp(for app: NSRunningApplication) -> AXUIElement {
        AXUIElementCreateApplication(app.processIdentifier)
    }

    private static func attr<T>(_ key: String, of el: AXUIElement) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success,
              let r = v else { return nil }
        return r as? T
    }

    static func role(of el: AXUIElement) -> String {
        attr(kAXRoleAttribute as String, of: el) as String? ?? ""
    }

    static func label(of el: AXUIElement) -> String {
        let t: String = attr(kAXTitleAttribute as String, of: el) ?? ""
        if !t.isEmpty { return t }
        let d: String = attr(kAXDescriptionAttribute as String, of: el) ?? ""
        if !d.isEmpty { return d }
        return attr(kAXValueAttribute as String, of: el) as String? ?? ""
    }

    static func doubleValue(of el: AXUIElement) -> Double? {
        if let d: Double = attr(kAXValueAttribute as String, of: el) { return d }
        if let i: Int    = attr(kAXValueAttribute as String, of: el) { return Double(i) }
        return nil
    }

    static func maxDoubleValue(of el: AXUIElement) -> Double? {
        if let d: Double = attr(kAXMaxValueAttribute as String, of: el) { return d }
        if let i: Int    = attr(kAXMaxValueAttribute as String, of: el) { return Double(i) }
        return nil
    }

    static func children(of el: AXUIElement) -> [AXUIElement] {
        attr(kAXChildrenAttribute as String, of: el) as [AXUIElement]? ?? []
    }

    static func windows(of axApp: AXUIElement) -> [AXUIElement] {
        attr(kAXWindowsAttribute as String, of: axApp) as [AXUIElement]? ?? []
    }

    static func frontWindow(of axApp: AXUIElement) -> AXUIElement? {
        attr(kAXFocusedWindowAttribute as String, of: axApp) as AXUIElement?
            ?? windows(of: axApp).first
    }

    // MARK: - Tree traversal (breadth-first, depth-limited)

    static func allElements(under root: AXUIElement, maxDepth: Int = 10) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        while !queue.isEmpty {
            let (el, depth) = queue.removeFirst()
            guard depth < maxDepth else { continue }
            let kids = children(of: el)
            result.append(contentsOf: kids)
            kids.forEach { queue.append(($0, depth + 1)) }
        }
        return result
    }

    // MARK: - Find elements

    static func findElement(under root: AXUIElement,
                            role targetRole: String? = nil,
                            matching query: String? = nil,
                            partial: Bool = true) -> AXUIElement? {
        for el in allElements(under: root) {
            if let r = targetRole, role(of: el) != r { continue }
            if let q = query {
                let l = label(of: el)
                let hit = partial
                    ? l.localizedCaseInsensitiveContains(q)
                    : l.localizedCaseInsensitiveCompare(q) == .orderedSame
                if !hit { continue }
            }
            return el
        }
        return nil
    }

    static func findButton(under root: AXUIElement,
                           labeled query: String, partial: Bool = true) -> AXUIElement? {
        findElement(under: root, role: "AXButton", matching: query, partial: partial)
    }

    static func findProgressBar(under root: AXUIElement) -> AXUIElement? {
        findElement(under: root, role: "AXProgressIndicator")
    }

    static func findCheckboxes(under root: AXUIElement) -> [AXUIElement] {
        allElements(under: root).filter { role(of: $0) == "AXCheckBox" }
    }

    /// Collects all visible text (labels + static text) under an element, joined with spaces.
    static func allText(under root: AXUIElement) -> String {
        allElements(under: root).compactMap { el -> String? in
            let r = role(of: el)
            guard r == "AXStaticText" || r == "AXTextField" || r == "AXTextArea" ||
                  r == "AXButton" || r == "AXCheckBox" else { return nil }
            return label(of: el)
        }.joined(separator: " ")
    }

    /// Returns all text fields under root. If secureOnly is true, returns only password fields.
    static func findTextFields(under root: AXUIElement, secureOnly: Bool = false) -> [AXUIElement] {
        allElements(under: root).filter { el in
            let r = role(of: el)
            if secureOnly { return r == "AXSecureTextField" }
            return r == "AXTextField" || r == "AXSecureTextField" || r == "AXTextArea"
        }
    }

    /// Sets the value of a text/secure field directly via AX attribute, then simulates Return.
    @discardableResult
    static func setValue(of el: AXUIElement, to value: String) -> Bool {
        let result = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, value as CFTypeRef)
        // Also focus the field and type it in case the AX set is ignored
        AXUIElementPerformAction(el, kAXFocusedAttribute as CFString)
        return result == .success
    }

    // MARK: - Actions

    @discardableResult
    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func clickButton(labeled query: String, under root: AXUIElement,
                            partial: Bool = true) -> Bool {
        guard let btn = findButton(under: root, labeled: query, partial: partial) else { return false }
        return press(btn)
    }

    // MARK: - Keyboard

    /// Sends a single key event (down + up) with optional modifier flags.
    static func sendKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let dn = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) {
            dn.flags = flags
            up.flags = flags
            dn.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Injects Unicode text into the currently focused field via CGEvent.
    static func typeText(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var ch = UniChar(scalar.value & 0xFFFF)
            if let dn = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                dn.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &ch)
                dn.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Wait

    /// Polls `condition` every `interval` seconds until it returns true or `timeout` expires.
    @discardableResult
    static func waitFor(timeout: TimeInterval, interval: TimeInterval = 0.5,
                        condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return condition()
    }

    // MARK: - High-level async operations

    /// Waits for any window of `appName` to appear, optionally filtered by title fragment.
    static func waitForWindow(appName: String,
                              titleContaining titleHint: String? = nil,
                              timeout: TimeInterval = 30) async -> AXUIElement? {
        var found: AXUIElement?
        _ = await waitFor(timeout: timeout) {
            guard let app = findApp(named: appName), app.isFinishedLaunching else { return false }
            let ax   = axApp(for: app)
            let wins = windows(of: ax)
            if let hint = titleHint {
                found = wins.first {
                    (attr(kAXTitleAttribute as String, of: $0) as String? ?? "")
                        .localizedCaseInsensitiveContains(hint)
                }
            } else {
                found = wins.first
            }
            return found != nil
        }
        return found
    }

    /// Retries clicking a button in `appName`'s front window until found or timeout.
    @discardableResult
    static func clickButton(inApp appName: String,
                            labeled query: String,
                            partial: Bool = true,
                            timeout: TimeInterval = 15) async -> Bool {
        var clicked = false
        _ = await waitFor(timeout: timeout) {
            guard let app = findApp(named: appName) else { return false }
            let ax = axApp(for: app)
            guard let win = frontWindow(of: ax) else { return false }
            clicked = clickButton(labeled: query, under: win, partial: partial)
            return clicked
        }
        return clicked
    }

    /// Tries a "Select All" button first; falls back to checking every visible checkbox.
    /// Returns number of items selected (-1 if the Select All button was used).
    @discardableResult
    static func selectAll(inApp appName: String,
                          timeout: TimeInterval = 15) async -> Int {
        for lbl in ["Select All", "Select all", "All"] {
            if await clickButton(inApp: appName, labeled: lbl, partial: false, timeout: 3) {
                return -1
            }
        }
        guard let app = findApp(named: appName),
              let win = frontWindow(of: axApp(for: app)) else { return 0 }
        var count = 0
        for cb in findCheckboxes(under: win) {
            let v = doubleValue(of: cb) ?? 0
            if v == 0 {
                press(cb)
                count += 1
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
        return count
    }

    /// Waits until a progress bar reaches max OR a recognisable "done" button appears.
    /// Generous default timeout for large plugin installs (1 hour).
    static func waitForCompletion(inApp appName: String,
                                  doneLabels: [String] = ["Done", "Close", "Finish", "Finished", "OK"],
                                  pollInterval: TimeInterval = 2,
                                  timeout: TimeInterval = 3600) async -> Bool {
        guard let app = findApp(named: appName) else { return false }
        let ax = axApp(for: app)
        return await waitFor(timeout: timeout, interval: pollInterval) {
            guard let win = frontWindow(of: ax) else { return false }
            for lbl in doneLabels {
                if findButton(under: win, labeled: lbl, partial: false) != nil { return true }
            }
            if let bar = findProgressBar(under: win),
               let val = doubleValue(of: bar),
               let max = maxDoubleValue(of: bar),
               max > 0, val >= max { return true }
            return false
        }
    }

    /// Terminates the app and waits for it to exit.
    static func quitApp(named name: String, timeout: TimeInterval = 15) async {
        findApp(named: name)?.terminate()
        _ = await waitFor(timeout: timeout) { findApp(named: name) == nil }
    }

    /// Moves an .app bundle (in /Applications or ~/Applications) to Trash.
    @discardableResult
    static func moveToTrash(appNamed name: String) -> Bool {
        let appFile = name.hasSuffix(".app") ? name : "\(name).app"
        for dir in ["/Applications", "\(NSHomeDirectory())/Applications"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(appFile)
            if FileManager.default.fileExists(atPath: url.path) {
                if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                    return true
                }
            }
        }
        return false
    }

    /// Moves any file or folder at `path` to Trash.
    @discardableResult
    static func trashItem(atPath path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return true }
        return (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    // MARK: - Menu bar navigation

    /// Clicks an item in an app's native menu bar via AX.
    /// Example: clickMenuBarItem(appName:"Ableton Live", menu:"Live", item:"Settings...")
    @discardableResult
    static func clickMenuBarItem(appName: String,
                                 menu: String,
                                 item: String,
                                 timeout: TimeInterval = 15) async -> Bool {
        // Bring the app to front first so its menu bar is active
        findApp(named: appName)?.activate(options: .activateIgnoringOtherApps)
        try? await Task.sleep(nanoseconds: 300_000_000)

        var success = false
        _ = await waitFor(timeout: timeout) {
            guard let app = findApp(named: appName) else { return false }
            let ax = axApp(for: app)

            // AXMenuBar → find menu by title → find menu item by title
            guard let menuBar: AXUIElement = {
                var v: CFTypeRef?
                guard AXUIElementCopyAttributeValue(ax, kAXMenuBarAttribute as CFString, &v) == .success else { return nil }
                return v as! AXUIElement
            }() else { return false }

            // Find the top-level menu (e.g. "Live", "File")
            guard let topMenu = findElement(under: menuBar, matching: menu, partial: false) else { return false }
            // Open it
            AXUIElementPerformAction(topMenu, kAXPressAction as CFString)
            // Brief pause for menu to open
            Thread.sleep(forTimeInterval: 0.3)

            // Find the menu item (e.g. "Settings...")
            if let menuItem = findElement(under: topMenu, matching: item, partial: true) {
                success = AXUIElementPerformAction(menuItem, kAXPressAction as CFString) == .success
                return success
            }
            // Close menu if item not found
            AXUIElementPerformAction(topMenu, kAXPressAction as CFString)
            return false
        }
        return success
    }

    // MARK: - Popup / segmented control value setting

    /// Finds a popup button near a label containing `hint` and selects `value`.
    /// Works for NSPopUpButton (AXPopUpButton) — Ableton settings use native controls.
    @discardableResult
    static func setPopupValue(inApp appName: String,
                              popupHint: String,
                              value: String,
                              timeout: TimeInterval = 10) async -> Bool {
        var success = false
        _ = await waitFor(timeout: timeout) {
            guard let app = findApp(named: appName) else { return false }
            let ax = axApp(for: app)
            guard let win = frontWindow(of: ax) else { return false }
            let all = allElements(under: win)

            // Strategy 1: find a popup whose current value or title matches the hint or is near it
            let popups = all.filter { role(of: $0) == "AXPopUpButton" }
            for popup in popups {
                let lbl = label(of: popup)
                let val: String = attr(kAXValueAttribute as String, of: popup) as String? ?? ""
                // Accept if popup is labeled with hint OR its current value contains hint text
                let nearby = lbl.localizedCaseInsensitiveContains(popupHint) ||
                             val.localizedCaseInsensitiveContains(popupHint)
                if nearby || lbl.isEmpty {
                    // Open the popup
                    AXUIElementPerformAction(popup, kAXPressAction as CFString)
                    Thread.sleep(forTimeInterval: 0.3)
                    // Now find the menu item with our target value
                    if let item = findElement(under: popup, matching: value, partial: true) {
                        success = AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                        if success { return true }
                    }
                    // Close popup if value not found here
                    AXUIElementPerformAction(popup, kAXPressAction as CFString)
                }
            }

            // Strategy 2: find a static text element containing the hint, then find the nearest popup
            if !success {
                if let labelEl = findElement(under: win, matching: popupHint, partial: true) {
                    // Find any popup in the same row/group by checking siblings
                    let parent = children(of: labelEl).isEmpty ? labelEl : labelEl
                    _ = parent  // silence unused warning
                    for popup in popups {
                        AXUIElementPerformAction(popup, kAXPressAction as CFString)
                        Thread.sleep(forTimeInterval: 0.3)
                        if let item = findElement(under: popup, matching: value, partial: true) {
                            success = AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                            if success { return true }
                        }
                        AXUIElementPerformAction(popup, kAXPressAction as CFString)
                    }
                }
            }
            return success
        }
        return success
    }

    // MARK: - State-aware installer wizard driver

    /// Drives an InstallBuilder-style (or similar) setup wizard to completion using
    /// the Accessibility API. Detects the current wizard page from visible UI elements
    /// and performs the appropriate action. No screen coordinates are used.
    ///
    /// Page detection logic:
    ///   Finish page   — Finish/Done/Close button visible → click it, return success
    ///   Progress page — progress bar running, no finish button → wait
    ///   License page  — agreement checkboxes or I Agree button → tick + click
    ///   Component page — plugin-format checkboxes → select AU/VST/VST3/AAX/CLAP, then Next
    ///   Welcome page  — Next/Continue/Proceed → click
    ///
    /// Targets only the named app. Does not interact with other windows or apps.
    @discardableResult
    static func driveWizard(appName: String, timeout: TimeInterval = 1800) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)

        // Plugin format stems — case-insensitive exact or boundary match on checkbox label
        let pluginFormatStems: [String] = [
            "au", "audio unit", "audio units", "audiounit",
            "vst", "vst2", "vst 2",
            "vst3", "vst 3",
            "aax", "aax plug-in", "aax plugin", "aax (avid audio extension)",
            "clap", "lv2", "rtas",
        ]
        // Non-format items we never auto-select
        let avoidStems: [String] = [
            "standalone", "preset", "presets", "documentation", "manual",
            "samples", "content", "tutorial", "tutorials", "demo", "readme",
            "extras", "resources", "help",
        ]

        let finishLabels   = ["Done", "Finish", "Finished", "Close"]
        let agreeLabels    = ["I Agree", "I Accept", "Agree", "Accept"]
        let progressLabels = ["Install", "Next", "Continue", "Proceed"]
        let agreeCBKeys    = ["agree", "accept", "terms", "license"]

        while Date() < deadline {
            // App exited on its own → done
            guard findApp(named: appName) != nil else {
                NSLog("[ATLAS-WIZARD] %@ exited — installation complete", appName)
                return true
            }
            guard let app = findApp(named: appName),
                  let win = frontWindow(of: axApp(for: app)) else {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                continue
            }

            let allEls   = allElements(under: win)
            let buttons  = allEls.filter { role(of: $0) == "AXButton" }
            let checkboxes = findCheckboxes(under: win)
            let hasBar   = findProgressBar(under: win) != nil

            // ── FINISH PAGE ──────────────────────────────────────────────────
            if let finBtn = buttons.first(where: { finishLabels.contains(label(of: $0)) }) {
                let lbl = label(of: finBtn)
                NSLog("[ATLAS-WIZARD] %@: clicking '%@' — done", appName, lbl)
                press(finBtn)
                _ = await waitFor(timeout: 15) { findApp(named: appName) == nil }
                return true
            }

            // ── PROGRESS PAGE ────────────────────────────────────────────────
            if hasBar {
                NSLog("[ATLAS-WIZARD] %@: installation in progress — waiting", appName)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }

            // ── LICENSE AGREEMENT CHECKBOXES ─────────────────────────────────
            var tickedAgreement = false
            for cb in checkboxes {
                let lbl = label(of: cb).lowercased()
                guard agreeCBKeys.contains(where: { lbl.contains($0) }) else { continue }
                if (doubleValue(of: cb) ?? 0) == 0 {
                    press(cb)
                    tickedAgreement = true
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }

            // ── COMPONENT SELECTION ──────────────────────────────────────────
            var selectedFormats: [String] = []
            for cb in checkboxes {
                let raw = label(of: cb)
                let lbl = raw.lowercased().trimmingCharacters(in: .whitespaces)
                // Skip agreement checkboxes (handled above)
                if agreeCBKeys.contains(where: { lbl.contains($0) }) { continue }
                // Skip avoided non-format items
                if avoidStems.contains(where: { lbl == $0 || lbl.contains($0) }) { continue }
                // Select if it matches a known plugin format and is not already checked
                let isFormat = pluginFormatStems.contains(where: {
                    lbl == $0 ||
                    lbl.hasPrefix($0 + " ") || lbl.hasSuffix(" " + $0) ||
                    lbl.contains(" " + $0 + " ") || lbl.contains("(" + $0 + ")")
                })
                if isFormat && (doubleValue(of: cb) ?? 0) == 0 {
                    press(cb)
                    selectedFormats.append(raw)
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }
            if !selectedFormats.isEmpty {
                NSLog("[ATLAS-WIZARD] %@: selected formats: %@",
                      appName, selectedFormats.joined(separator: ", "))
                try? await Task.sleep(nanoseconds: 600_000_000)  // let UI update
            }

            // ── AGREE / PROGRESS BUTTONS ─────────────────────────────────────
            var clicked = false
            if let agreeBtn = buttons.first(where: { agreeLabels.contains(label(of: $0)) }) {
                let lbl = label(of: agreeBtn)
                NSLog("[ATLAS-WIZARD] %@: clicking '%@'", appName, lbl)
                press(agreeBtn)
                clicked = true
            } else if let progBtn = buttons.first(where: { progressLabels.contains(label(of: $0)) }) {
                let lbl = label(of: progBtn)
                NSLog("[ATLAS-WIZARD] %@: clicking '%@'", appName, lbl)
                press(progBtn)
                clicked = true
            }

            if !clicked && !tickedAgreement && selectedFormats.isEmpty {
                // Nothing actionable — might be a transition; just wait
                NSLog("[ATLAS-WIZARD] %@: no actionable element found — waiting", appName)
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        NSLog("[ATLAS-WIZARD] %@: wizard timed out after %.0f min", appName, timeout / 60)
        await quitApp(named: appName)
        return false
    }
}
