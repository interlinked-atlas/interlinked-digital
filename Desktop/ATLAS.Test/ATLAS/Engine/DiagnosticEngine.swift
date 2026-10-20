import Foundation

// Rule-based diagnostic chat engine for admin "No — Get Help" flow.
// Reads the install log + steps to ask targeted follow-up questions.
// No external API — zero cost, works offline.

struct DiagnosticMessage: Identifiable {
    enum Sender { case user, atlas }
    let id = UUID()
    let sender: Sender
    let text: String
}

struct DiagnosticEngine {
    let steps: [InstallStep]
    let installLog: String
    let productName: String

    // MARK: - Main entry point

    /// Called with the full conversation so far. Returns ATLAS's next message.
    func respond(to userMessage: String, history: [DiagnosticMessage]) -> String {
        let lower = userMessage.lowercased()
        let logLower = installLog.lowercased()
        let turnCount = history.filter { $0.sender == .atlas }.count

        // First ATLAS turn: diagnose from initial failure description + log
        if turnCount == 0 {
            return firstResponse(failureNote: lower, logLower: logLower)
        }

        // Subsequent turns: respond to follow-up answers
        return followUp(userMessage: lower, history: history, logLower: logLower)
    }

    /// Opening question ATLAS asks, informed by the log + failure note
    private func firstResponse(failureNote: String, logLower: String) -> String {
        // Detect failure category from note + log together
        if mentionsPatch(failureNote) || mentionsPatch(logLower) {
            let mainRan = logLower.contains("pkg success") || logLower.contains("install complete") || logLower.contains("successfully installed")
            if !mainRan {
                return "Looks like the patch may have run before the main installer finished. Did you see the main setup complete its progress bar before the patch was applied?"
            }
            return "The patch step ran after the main installer. Was the target app fully closed when the patch ran? Some patches fail silently if the DAW or plugin host is open."
        }

        if mentionsMerge(failureNote) || mentionsMerge(logLower) {
            return "This sounds like a library folder conflict. When ATLAS asked you to place the folder, did you choose **Merge** or did it end up replacing the existing folder? Replacing instead of merging wipes out your existing library content."
        }

        if mentionsLicense(failureNote) || licenseFailInLog(logLower) {
            return "License activation issue. Which license manager does this product use — iLok, Native Access, PACE, or a standalone activation window? And did the license manager window actually open during the install?"
        }

        if mentionsPermission(failureNote) || permissionFailInLog(logLower) {
            return "Looks like a permissions problem. Was ATLAS running with admin rights when this happened? And did macOS show a 'wants to make changes' dialog — did you approve it or did it time out?"
        }

        if mentionsPath(failureNote) {
            return "Wrong location issue. Where did ATLAS place the files — do you remember the path it used? And where should they actually go for this product?"
        }

        if mentionsPrerequisite(failureNote) || prerequisiteInLog(logLower) {
            return "Missing prerequisite detected. Does this product require iLok License Manager, Native Access, PACE, or any other software to be installed first? Is that software already on this machine?"
        }

        if mentionsPartialInstall(logLower) {
            let failed = extractFailedSteps(logLower)
            if !failed.isEmpty {
                return "The install was partially successful — some steps completed but \(failed) failed. Was there an error dialog that appeared, or did it just silently stop?"
            }
        }

        if mentionsApp(failureNote) || appWasOpen(logLower) {
            return "Was the DAW or any plugin host (Pro Tools, Logic, Ableton, etc.) open while ATLAS was installing? Some installers require all audio apps to be fully quit first."
        }

        // Generic opening if nothing specific detected
        return "Got it. Let's figure this out. Can you describe exactly what happened — did you get an error message, did the app launch but something was missing, or did the install appear to complete but the product isn't showing up anywhere?"
    }

    /// Follow-up responses based on the conversation thread
    private func followUp(userMessage: String, history: [DiagnosticMessage], logLower: String) -> String {
        let lastAtlasMessage = history.last(where: { $0.sender == .atlas })?.text.lowercased() ?? ""
        let atlasCount = history.filter { $0.sender == .atlas }.count

        // Patch follow-up thread
        if lastAtlasMessage.contains("patch") || lastAtlasMessage.contains("progress bar") {
            if containsYes(userMessage) {
                if lastAtlasMessage.contains("fully closed") {
                    return "That's the cause. The patch binary locks onto the running process and fails silently. Fix: close the DAW first, then re-run just the patch step. Want me to save this to TITAN MEMORY™ with the correct order noted?"
                }
                return "Good — main installer completed first. Was the DAW or plugin host completely closed when the patch ran? Check Activity Monitor to make sure no audio processes were running."
            }
            if containsNo(userMessage) {
                return "That's the issue — the patch ran before the main installer finished. The correct order is: main installer first, let it complete fully, then run the patch. Want me to save the corrected step order to TITAN MEMORY™?"
            }
        }

        // Merge follow-up thread
        if lastAtlasMessage.contains("merge") {
            if userMessage.contains("replace") || userMessage.contains("replaced") {
                return "That's what broke it — replacing wipes your existing library content instead of adding to it. The fix is to re-copy the folder and choose Merge this time. ATLAS will prompt you again if you re-run the install. Want me to flag this product as 'always merge' in TITAN MEMORY™?"
            }
            if userMessage.contains("merge") || userMessage.contains("merged") {
                return "Merge was correct — so the folder placement isn't the issue. Did the product show up in your DAW after merging, or is it completely absent from the browser/library? That'll tell us if it's a path issue vs a registration issue."
            }
        }

        // License follow-up thread
        if lastAtlasMessage.contains("license") || lastAtlasMessage.contains("ilok") || lastAtlasMessage.contains("native access") {
            if userMessage.contains("didn't open") || userMessage.contains("never opened") || userMessage.contains("no window") {
                return "The license step was skipped or failed silently. This usually means the license manager app isn't installed, or it launched but closed immediately. Is iLok License Manager (or Native Access) installed and up to date on this machine?"
            }
            if userMessage.contains("ilok") {
                return "For iLok: the license needs to be on either your iLok dongle or your iLok cloud account. Was the iLok dongle plugged in during activation, or are you using cloud licensing? And is the license actually in your iLok account?"
            }
            if userMessage.contains("native access") || userMessage.contains("native instruments") {
                return "Native Access needs to be open and logged in *before* the installer runs — it won't auto-activate if NI servers can't be reached. Was Native Access open and online when ATLAS ran the install?"
            }
            if containsYes(userMessage) && lastAtlasMessage.contains("open during") {
                return "License manager opened — good. Did it show the activation completing, or did it hang or show an error? Sometimes PACE/iLok needs the machine restarted after a fresh install before it recognizes the license."
            }
        }

        // Permissions follow-up
        if lastAtlasMessage.contains("admin rights") || lastAtlasMessage.contains("wants to make changes") {
            if userMessage.contains("timed out") || userMessage.contains("didn't see") || userMessage.contains("no dialog") {
                return "The auth dialog probably appeared behind another window. ATLAS uses an auth watcher to auto-approve these, but if the password wasn't saved in Keychain it would have timed out. Is your admin password saved in ATLAS settings?"
            }
            if containsNo(userMessage) && lastAtlasMessage.contains("admin rights") {
                return "That's the issue — the installer needs elevated permissions. Make sure ATLAS is running as an admin user, and that your password is saved in ATLAS → Settings → Password. Want me to flag this product as 'requires admin' in TITAN MEMORY™?"
            }
        }

        // Prerequisite follow-up
        if lastAtlasMessage.contains("prerequisite") || lastAtlasMessage.contains("ilok license manager") || lastAtlasMessage.contains("native access") {
            if containsNo(userMessage) || userMessage.contains("not installed") || userMessage.contains("missing") {
                return "That's the blocker. ATLAS needs to install the prerequisite first before this product. Which one is missing — iLok License Manager, Native Access, PACE iLok, or something else? Once you install it, re-run the product install and it should work."
            }
        }

        // Generic resolution check
        if atlasCount >= 3 {
            return "Based on what you've described — do you have enough to re-run the install with the fix in mind? If yes, hit 'Save to TITAN MEMORY™' below and I'll make sure ATLAS handles this correctly for every future user. If you're still stuck, describe what's still wrong."
        }

        return "Can you give me a bit more detail — specifically what error message appeared (if any) and at which step the install stopped or produced the wrong result?"
    }

    // MARK: - Keyword helpers

    private func mentionsPatch(_ s: String) -> Bool {
        s.contains("patch") || s.contains("update") || s.contains("r2r") || s.contains("keygen")
    }
    private func mentionsMerge(_ s: String) -> Bool {
        s.contains("merge") || s.contains("library") || s.contains("folder") || s.contains("heatup") || s.contains("content")
    }
    private func mentionsLicense(_ s: String) -> Bool {
        s.contains("licens") || s.contains("ilok") || s.contains("native access") || s.contains("activat") || s.contains("pace")
    }
    private func mentionsPermission(_ s: String) -> Bool {
        s.contains("permission") || s.contains("denied") || s.contains("admin") || s.contains("password") || s.contains("unauthorized")
    }
    private func mentionsPath(_ s: String) -> Bool {
        s.contains("path") || s.contains("location") || s.contains("wrong folder") || s.contains("wrong place") || s.contains("can't find")
    }
    private func mentionsPrerequisite(_ s: String) -> Bool {
        s.contains("missing") || s.contains("not installed") || s.contains("prerequisite") || s.contains("requirement")
    }
    private func mentionsApp(_ s: String) -> Bool {
        s.contains("open") || s.contains("running") || s.contains("logic") || s.contains("ableton") || s.contains("pro tools") || s.contains("reaper")
    }

    private func licenseFailInLog(_ log: String) -> Bool {
        log.contains("license") && (log.contains("fail") || log.contains("error") || log.contains("timeout"))
    }
    private func permissionFailInLog(_ log: String) -> Bool {
        log.contains("permission denied") || log.contains("operation not permitted") || log.contains("auth") && log.contains("fail")
    }
    private func prerequisiteInLog(_ log: String) -> Bool {
        log.contains("ilok") || log.contains("native access") || log.contains("pace") || log.contains("prerequisite")
    }
    private func appWasOpen(_ log: String) -> Bool {
        log.contains("process running") || log.contains("app is open") || log.contains("close") && log.contains("daw")
    }
    private func mentionsPartialInstall(_ log: String) -> Bool {
        log.contains("✗") || log.contains("failed:") || log.contains("error:")
    }
    private func extractFailedSteps(_ log: String) -> String {
        let lines = log.components(separatedBy: "\n").filter { $0.contains("✗") || $0.contains("failed:") }
        return lines.prefix(2).joined(separator: ", ")
    }
    private func containsYes(_ s: String) -> Bool {
        s.hasPrefix("yes") || s.contains(" yes") || s.hasPrefix("yeah") || s.hasPrefix("yep") || s.hasPrefix("correct") || s.hasPrefix("it did")
    }
    private func containsNo(_ s: String) -> Bool {
        s.hasPrefix("no") || s.contains(" no ") || s.hasPrefix("nope") || s.hasPrefix("didn't") || s.hasPrefix("it didn")
    }
}
