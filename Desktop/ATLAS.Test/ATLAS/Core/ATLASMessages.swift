import Foundation

// ATLASMessages — translates internal technical strings into plain English for the user-facing UI.
// The raw technical detail is always preserved in the install log; only the UI label is softened.

struct ATLASMessages {

    // MARK: - Install failure reasons

    static func friendlyFailureReason(_ raw: String) -> String {
        let lower = raw.lowercased()

        if lower.contains("pkg receipt") || lower.contains("receipt") {
            return L(.failReasonIncomplete)
        }
        if lower.contains("files on disk") || lower.contains("missing:") {
            return L(.failReasonFilesNotLanded)
        }
        if lower.contains("app did not appear") || lower.contains("bundle not found") {
            return L(.failReasonAppNoLaunch)
        }
        if lower.contains("auval") || lower.contains("au (") || lower.contains("audio unit") {
            return L(.failReasonAUNotRecognized)
        }
        if lower.contains("mach-o") || lower.contains("binary not recognized") || lower.contains("contents/macos is empty") {
            return L(.failReasonDamaged)
        }
        if lower.contains("titan verify") {
            return L(.failReasonVerifyFailed)
        }
        if lower.contains("confidence too low") || lower.contains("confidence") {
            return L(.failReasonConfidenceLow)
        }
        if lower.contains("script") || lower.contains("bash") || lower.contains("exit code") {
            return L(.failReasonScriptError)
        }
        if lower.contains("pkg") || lower.contains("installer") {
            return L(.failReasonPkgFailed)
        }
        if lower.contains("cancelled") {
            return L(.failReasonCancelled)
        }
        if lower.contains("waves") {
            return L(.failReasonWaves)
        }
        if raw.count > 80 {
            return L(.failReasonGeneric)
        }
        return raw
    }

    // MARK: - Demo / trial warning

    static func friendlyDemoWarning(keywords: [String]) -> String {
        L(.demoWarningLabel)
    }

    // MARK: - Progress step labels

    static func friendlyProgressStep(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("scanning") || lower.contains("pre-scan") { return L(.progressScanningFile) }
        if lower.contains("mounting") || lower.contains("mount")    { return L(.progressOpeningInstaller) }
        if lower.contains("copying") || lower.contains("copy")      { return L(.progressCopyingFiles) }
        if lower.contains("pkg") || lower.contains("package")       { return L(.progressRunningInstaller) }
        if lower.contains("script") || lower.contains("bash")       { return L(.progressRunningScript) }
        if lower.contains("hosts")                                   { return L(.progressApplyingLicense) }
        if lower.contains("titan verify") || lower.contains("verify") { return L(.progressVerifying) }
        if lower.contains("demo") || lower.contains("demo scan")    { return L(.progressCheckingLicense) }
        if lower.contains("learn") || lower.contains("atlas learn") { return L(.progressSavingProfile) }
        if lower.contains("unmount") || lower.contains("cleanup")   { return L(.progressCleaningUp) }
        if lower.contains("complete") || lower.contains("done")     { return L(.progressDone) }
        return raw
    }

    // MARK: - Queue item status label

    static func queueStatusLabel(_ status: QueueItemStatus) -> String {
        switch status {
        case .waiting:              return L(.queueStatusWaiting)
        case .scanning:             return L(.queueStatusScanning)
        case .installing:           return L(.queueStatusInstalling)
        case .success:              return L(.queueStatusInstalled)
        case .failure(let reason):  return friendlyFailureReason(reason)
        case .demoWarning:          return L(.queueStatusDemoWarning)
        case .activationRequired:   return L(.queueStatusActivation)
        case .verificationWarning:  return L(.queueStatusVerification)
        }
    }
}
