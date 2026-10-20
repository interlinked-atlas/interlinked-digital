import Foundation
import SwiftUI

// MARK: - Supported languages

enum ATLASLanguage: String, CaseIterable, Identifiable {
    case english    = "en"
    case spanish    = "es"
    case french     = "fr"
    case german     = "de"
    case portuguese = "pt"
    case japanese   = "ja"
    case chinese    = "zh"
    case korean     = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:    return "English"
        case .spanish:    return "Español"
        case .french:     return "Français"
        case .german:     return "Deutsch"
        case .portuguese: return "Português"
        case .japanese:   return "日本語"
        case .chinese:    return "中文"
        case .korean:     return "한국어"
        }
    }

    var flag: String {
        switch self {
        case .english:    return "🇺🇸"
        case .spanish:    return "🇪🇸"
        case .french:     return "🇫🇷"
        case .german:     return "🇩🇪"
        case .portuguese: return "🇧🇷"
        case .japanese:   return "🇯🇵"
        case .chinese:    return "🇨🇳"
        case .korean:     return "🇰🇷"
        }
    }
}

// MARK: - Manager

final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    private static let key = "ATLAS.language"

    @Published var current: ATLASLanguage {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: Self.key) }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? "en"
        current = ATLASLanguage(rawValue: saved) ?? .english
    }

    func str(_ key: ATLASString) -> String {
        ATLASStrings.get(key, language: current)
    }
}

// Convenience global accessor
func L(_ key: ATLASString) -> String {
    LanguageManager.shared.str(key)
}

// MARK: - String keys

enum ATLASString: CaseIterable {
    // TITAN CORE™ Mission Panel
    case titanMissionTitle
    case titanMissionSubtitle
    case titanBegin
    case titanCancel
    case titanRunning
    case titanComplete
    case titanStepPending
    case titanStepRunning
    case titanStepDone
    case titanStepFailed
    case titanStepSkipped

    // TITAN step labels
    case titanStepXcodeTools
    case titanStepInstallPkg
    case titanStepRunScript
    case titanStepRunBinary
    case titanStepEditHosts
    case titanStepRunCommand

    // No instructions dialog
    case titanNoInstrTitle
    case titanNoInstrBody
    case titanNoInstrProvide
    case titanNoInstrAttempt
    case titanNoInstrWarning
    case titanNoInstrHelp

    // Drop zone
    case dropFilesHere
    case releaseToAdd
    case chooseFile

    // Notifications & queue results
    case notifySuccessTitle
    case notifySuccessBody
    case notifyFailedTitle
    case notifyQueueCompleteTitle
    case notifyQueueCompleteBody
    case notifyUninstallComplete
    case notifyUninstallFailed
    case notifyRestoreComplete
    case notifyRestoreFailed
    case installMore
    case retrying

    // Cancel confirmation dialog
    case cancelConfirmTitle
    case cancelConfirmMessage
    case cancelConfirmStop
    case cancelConfirmContinue

    // General UI
    case settings
    case language
    case getHelp
    case signOut
    case upgrade
    case done
    case cancel
    case retry
    case close

    // Queue
    case queueInstallQueue
    case queueClearWaiting
    case queueInstallAll
    case queueWaitingForSteps
    case queueStatusWaiting
    case queueStatusScanning
    case queueStatusInstalling
    case queueStatusInstalled
    case queueStatusDemoWarning
    case queueStatusActivation
    case queueStatusVerification

    // Tour
    case tourDontShowAgain
    case tourBack
    case tourNext
    case tourStepOfFmt
    case tourStep0Title
    case tourStep0Body
    case tourStep1Title
    case tourStep1Body
    case tourStep2Title
    case tourStep2Body
    case tourStep3Title
    case tourStep3Body
    case tourStep4Title
    case tourStep4Body
    case tourStep5Title
    case tourStep5Body
    case tourStep6Title
    case tourStep6Body
    case tourStep7Title
    case tourStep7Body
    case tourStep8Title
    case tourStep8Body

    // Demo Alert
    case demoModeDetected
    case demoSignalsFound
    case demoWhatThisMeans
    case demoTip1
    case demoTip2
    case demoTip3

    // Recovery Mode
    case filterAll
    case filterReady
    case filterInstalling
    case filterInstalled
    case filterFailed
    case filterPending
    case installReadyProducts
    case dropInstallersAbove
    case recoveryComplete
    case viewInLibrary
    case exitRecoveryMode
    case statDone
    case statSkipped
    case statLimit
    case statReinstalled
    case statPending

    // Recovery Slot
    case stateLimitReached
    case dropInstallerHere
    case orLabel
    case installAction

    // Subscription
    case backToSignIn
    case reJoinAtlas
    case paymentFailed
    case subscriptionRequired
    case checkingEllipsis
    case iveSubscribed
    case subscribeNow
    case updateBilling
    case subBodyReJoin
    case subBodyPayment
    case subBodyNew

    // Pro Feature Lock
    case proFeature
    case proFeatureAvailOnFmt

    // ZIP Password
    case passwordRequired
    case filePasswordProtected
    case archivePassword
    case enterPassword
    case rememberPassword
    case unlockAndInstall

    // Rosetta
    case appleSiliconDetected
    case enableRosettaQ
    case scanningDAWs
    case noDAWsFound
    case selectDAWsRosetta
    case rosettaEnabledMsg
    case noThanks
    case applying
    case enableRosettaAction
    case alreadyEnabled

    // Storage/Library
    case available
    case total
    case nothingToClean
    case scanUnavailable
    case quickScan
    case overview
    case disabled
    case archived
    case review

    // Log View
    case fullLog
    case logSummary
    case less
    case logDetails
    case copied
    case copyLabel

    // Recovery Kit
    case portableSnapshot
    case generating
    case exportFailed
    case generate
    case cloudBackupLabel
    case checking
    case notBackedUp
    case syncing
    case restoring
    case loadRecoveryKit
    case openKitFile
    case loading
    case kitLoaded
    case fileRejected
    case couldNotLoad
    case replace
    case open
    case crossMacKitNote
    case hashMismatchNote
    case beginRecovery
    case recoveryModeProNote
    case products
    case update
    case backUp
    case retryCloudBackup

    // TITAN VSCAN
    case detectedThreats
    case showLess
    case showAllFmt
    case foundIn
    case continueInstall
    case proceedWithInstall
    case proceedAnyway
    case moveToQuarantine
    case deletePermanently
    case stripMalwareInstall
    case vscanLicenseTip
    case vscanSuspiciousTip
    case vscanMalwareTip
    case vscanQuarantineConfirmMsg
    case vscanDeleteConfirmMsg

    // Install Overlay
    case stillWorkingFmt

    // Scan Result
    case keygenDetected
    case windowsExe
    case keygenWarning
    case readyDropInstaller
    case dropNewFile
    case imDoneReady
    case confirmationRequired
    case contentsFound
    case alreadyInstalled
    case insufficientSpace
    case cannotInstallAuto
    case share
    case installAction2

    // Summary Card
    case userActionRequired
    case installerMovedToTrash
    case moveInstallerToTrash
    case backToHome
    case removed
    case supportFiles
    case couldNotRemove
    case filesMovedToTrash
    case recover

    // Settings
    case appearance
    case account
    case supportLabel
    case tourAtlasTitle
    case replayWalkthrough
    case tools
    case fixBlockedPlugins
    case removeSecurityBlocks
    case fix
    case installLimits
    case dailyInstallations
    case monthlyInstallations
    case resetsAtMidnight
    case refillsOnBillingDate
    case remainingTodayFmt
    case remainingThisMonthFmt
    case notificationsLabel
    case installAlerts
    case notifOn
    case notifOff
    case vscanSettingTitle
    case vscanSettingSubtitle
    case enableInSystemSettings
    case storageLabel
    case noVolumesFound
    case about
    case viewLogs
    case openLogFolder
    case signOutConfirmMsg
    case signOutTitle

    // Support
    case getSupport
    case replyWithin24
    case product
    case issueType
    case describeIssue
    case attachLog
    case sendRequest
    case sending
    case thankYou
    case requestReceived
    case supportTeamReplyFmt
    case backToAtlas

    // Cleaner
    case quickClean
    case scanSystemForClutter
    case itemsMovedToTrashNote
    case startScan
    case scanning
    case selectAll
    case deselectAll
    case cleanerTitle
    case noCleanupFound
    case systemIsClean
    case noCleanerHistory
    case cleanerHistory
    case movingToTrash

    // Failure reasons
    case failReasonIncomplete
    case failReasonFilesNotLanded
    case failReasonAppNoLaunch
    case failReasonAUNotRecognized
    case failReasonDamaged
    case failReasonVerifyFailed
    case failReasonConfidenceLow
    case failReasonScriptError
    case failReasonPkgFailed
    case failReasonCancelled
    case failReasonWaves
    case failReasonGeneric

    // Demo warning
    case demoWarningLabel

    // Progress steps
    case progressScanningFile
    case progressOpeningInstaller
    case progressCopyingFiles
    case progressRunningInstaller
    case progressRunningScript
    case progressApplyingLicense
    case progressVerifying
    case progressCheckingLicense
    case progressSavingProfile
    case progressCleaningUp
    case progressDone

    // Notification titles (not covered above)
    case notifyRestoreCompleteTitle
    case notifyRestoreFailedTitle

    // Uninstall notification body
    case notifyUninstallSuccessBody    // "%@ was removed successfully."

    // VSCAN notification bodies
    case vscanQuarantineNotifBody      // "%@ moved to ATLAS Quarantine."
    case vscanDeletedNotifBody         // "%@ permanently deleted."

    // NSAlert — quit during install
    case quitInstallAlertTitle        // "Installation in Progress"
    case quitInstallAlertBody         // long warning text
    case quitAnyway                   // "Quit Anyway"

    // AppKit menu
    case checkForUpdates              // "Check for Updates"
    case menuOpenAtlas
    case menuQuitAtlas

    // FileShare notification
    case fileShareNotifTitle          // "📦 New File Shared"
    case fileShareNotifBodyFmt        // "%@ (%@) is ready to install."

    // Batch uninstall notification
    case notifyBatchUninstallTitle    // "Session Uninstall Complete"

    // ATLAS Library (HistoryPanelView)
    case atlasLibrary
    case noInstallsYet
    case clearAll
    case deleteAll
    case formatsLabel
    case signingLabel                 // "Signing…"
    case signedLabel                  // "Signed!"
    case permanentlyDeleted
    case feedbackReceived             // "Feedback ✓"
    case filesPresent
    case inTrash
    case filesGone
    case unArchive
    case installedOnFmt               // "Installed %@"
    case archivedOnFmt                // "Archived %@"
    case archiveLabelFmt              // "Archive (%d)"
    case sessionFmt                   // "Session · %d · %@"
    case filesTrackedFmt              // "%d file(s) tracked"
    case receiptsAndFilesFmt          // "%d receipt(s) · %d files"
    case uninstall
    case remove
    case feedback
    case support
    case sign
    case enable
    case disable

    // HistoryPanelView alerts
    case clearAtlasLibraryTitle
    case clearLibraryMsgFmt
    case removeFromLibraryTitle
    case removeRecordMsgFmt
    case uninstallConfirmTitle
    case uninstallConfirmMsgFmt
    case disabledFormatsNoteFmt
    case recoverFilesTitle
    case recoverFilesMsgFmt
    case recoveryNotAvailable
    case uninstallSessionTitle
    case uninstallSessionMsgFmt
    case deleteArchivesTitle
    case deleteArchivesMsg
    case deleteAllArchivesBtn
    case deleteArchiveTitle
    case deleteArchiveMsgFmt
    case disableFmtConfirmTitleFmt
    case disableFmtConfirmMsgFmt
    case proFeatureAlertTitleFmt
    case proFeatureAlertMsgFmt
}


// MARK: - Strings table

enum ATLASStrings {

    static func get(_ key: ATLASString, language: ATLASLanguage) -> String {
        table[language]?[key] ?? table[.english]?[key] ?? "[\(key)]"
    }

    private static let table: [ATLASLanguage: [ATLASString: String]] = [

        .english: [
            // Existing
            .notifySuccessTitle:          "Installation Complete",
            .notifySuccessBody:           "%@ installed successfully.",
            .notifyFailedTitle:           "Installation Failed",
            .notifyQueueCompleteTitle:    "ATLAS — Queue Complete",
            .notifyQueueCompleteBody:     "%d installed successfully",
            .notifyUninstallComplete:     "Uninstall Complete",
            .notifyUninstallFailed:       "Uninstall Failed",
            .notifyRestoreComplete:       "%@ has been restored.",
            .notifyRestoreFailed:         "%@ could not be restored.",
            .installMore:                 "Install more",
            .retrying:                    "Retrying…",
            .cancelConfirmTitle:          "Stop installation?",
            .cancelConfirmMessage:        "The current install will be cancelled and any partial changes may need to be undone.",
            .cancelConfirmStop:           "Stop",
            .cancelConfirmContinue:       "Continue",
            .titanMissionTitle:           "TITAN CORE™ — Mission Plan",
            .titanMissionSubtitle:        "ATLAS has detected a multi-step installation. Review the plan, then begin.",
            .titanBegin:                  "Begin Installation",
            .titanCancel:                 "Cancel",
            .titanRunning:                "Running…",
            .titanComplete:               "Installation complete",
            .titanStepPending:            "Pending",
            .titanStepRunning:            "Running…",
            .titanStepDone:               "Done",
            .titanStepFailed:             "Failed",
            .titanStepSkipped:            "Skipped",
            .titanStepXcodeTools:         "Install Xcode Command Line Tools",
            .titanStepInstallPkg:         "Install package",
            .titanStepRunScript:          "Run script",
            .titanStepRunBinary:          "Run tool",
            .titanStepEditHosts:          "Block license server (edit /etc/hosts)",
            .titanStepRunCommand:         "Run terminal command",
            .titanNoInstrTitle:           "No Installation Guide Found",
            .titanNoInstrBody:            "ATLAS found files that suggest a complex installation, but no instruction guide was included.",
            .titanNoInstrProvide:         "Provide Instructions",
            .titanNoInstrAttempt:         "Attempt Without Guide",
            .titanNoInstrWarning:         "⚠ This installation may fail without a guide.",
            .titanNoInstrHelp:            "Get Help from InterLinked Support",
            .dropFilesHere:               "Drop files here",
            .releaseToAdd:                "Release to add",
            .chooseFile:                  "Choose File or Folder…",
            .settings:                    "Settings",
            .language:                    "Language",
            .getHelp:                     "Get Help",
            .signOut:                     "Sign Out",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "Done",
            .cancel:                      "Cancel",
            .retry:                       "Retry",
            .close:                       "Close",
            // Queue
            .queueInstallQueue:           "Install Queue",
            .queueClearWaiting:           "Clear Waiting",
            .queueInstallAll:             "Install All",
            .queueWaitingForSteps:        "Waiting for steps…",
            .queueStatusWaiting:          "Waiting",
            .queueStatusScanning:         "Scanning",
            .queueStatusInstalling:       "Installing",
            .queueStatusInstalled:        "Installed",
            .queueStatusDemoWarning:      "Demo Warning",
            .queueStatusActivation:       "Activation",
            .queueStatusVerification:     "Verification",
            // Tour
            .tourDontShowAgain:           "Don't show again",
            .tourBack:                    "Back",
            .tourNext:                    "Next",
            .tourStepOfFmt:               "%d of %d",
            .tourStep0Title:              "Drop & Install",
            .tourStep0Body:               "Drag any installer here — DMG, ZIP, PKG, VST3, AAX, or RAR. ATLAS scans it, shows you exactly what it found, and installs it with one tap. Nothing touches your system until you say so.",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "Everything ATLAS knows about your setup lives here. Your installed products, plugin formats, storage, cleanup tools, and recovery options — all in one place.",
            .tourStep2Title:              "Your Installed Products",
            .tourStep2Body:               "Every install is recorded here. Tap to expand and manage your products — enable or disable individual plugin formats (AU, VST3, VST, AAX) and sign them directly from your Library.",
            .tourStep3Title:              "Uninstall & Recovery",
            .tourStep3Body:               "Tap any product to expand it. Pro users can uninstall with one tap — ATLAS moves files to Trash and saves a rollback snapshot so you can recover them anytime.",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "Find leftover installation files, orphaned components, and reclaimable temp caches. ATLAS shows you exactly what it found before removing anything.",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "Export an encrypted snapshot of your entire library — every product, format, and path. Keep it safe and rebuild your full setup on any Mac, any time. Cloud backup available on Pro.",
            .tourStep6Title:              "Settings",
            .tourStep6Body:               "Manage your account, subscription, devices, and language. Switch between Light, Dark, or System appearance. Replay this tour anytime from Settings.",
            .tourStep7Title:              "You're Ready",
            .tourStep7Body:               "Drop your first installer to get started. Your Library, cleanup tools, and recovery options are always one tap away.",
            .tourStep8Title:              "You're Ready",
            .tourStep8Body:               "Drop your first installer to get started. Your Library, cleanup tools, and recovery options are always one tap away.",
            // Demo Alert
            .demoModeDetected:            "DEMO MODE DETECTED",
            .demoSignalsFound:            "SIGNALS FOUND",
            .demoWhatThisMeans:           "WHAT THIS MEANS",
            .demoTip1:                    "Open the plugin in your DAW and look for a watermark, banner, or activation prompt.",
            .demoTip2:                    "If demo mode appears, you may need to activate or re-enter your license.",
            .demoTip3:                    "Contact the vendor if you believe your license is valid but the plugin still shows demo mode.",
            // Recovery Mode
            .filterAll:                   "All",
            .filterReady:                 "Ready",
            .filterInstalling:            "Installing",
            .filterInstalled:             "Installed",
            .filterFailed:                "Failed",
            .filterPending:               "Pending",
            .installReadyProducts:        "INSTALL READY PRODUCTS",
            .dropInstallersAbove:         "Drop installers above to get started",
            .recoveryComplete:            "Recovery Complete",
            .viewInLibrary:               "View in Library",
            .exitRecoveryMode:            "Exit Recovery Mode",
            .statDone:                    "Done",
            .statSkipped:                 "Skipped",
            .statLimit:                   "Limit",
            .statReinstalled:             "Reinstalled",
            .statPending:                 "Pending",
            // Recovery Slot
            .stateLimitReached:           "Limit reached",
            .dropInstallerHere:           "Drop installer here",
            .orLabel:                     "or",
            .installAction:               "Install",
            // Subscription
            .backToSignIn:                "Back to Sign In",
            .reJoinAtlas:                 "Re-join ATLAS",
            .paymentFailed:               "Payment Failed",
            .subscriptionRequired:        "Subscription Required",
            .checkingEllipsis:            "Checking…",
            .iveSubscribed:               "I've subscribed — Refresh",
            .subscribeNow:                "Subscribe Now",
            .updateBilling:               "Update Billing",
            .subBodyReJoin:               "Your subscription has expired. Re-join ATLAS to continue installing.",
            .subBodyPayment:              "Your last payment failed. Update your billing details to continue.",
            .subBodyNew:                  "Subscribe to ATLAS to start installing plugins in seconds.",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "PASSWORD REQUIRED",
            .filePasswordProtected:       "This file is password protected",
            .archivePassword:             "ARCHIVE PASSWORD",
            .enterPassword:               "Enter password",
            .rememberPassword:            "ATLAS will remember this password for future installs of this product.",
            .unlockAndInstall:            "Unlock & Install",
            // Rosetta
            .appleSiliconDetected:        "Apple Silicon detected",
            .enableRosettaQ:              "Enable Rosetta for your DAWs to load Intel plugins?",
            .scanningDAWs:                "Scanning for installed DAWs...",
            .noDAWsFound:                 "No DAWs found on this Mac.",
            .selectDAWsRosetta:           "Select DAWs to enable Rosetta:",
            .rosettaEnabledMsg:           "Rosetta enabled for selected DAWs. Restart your DAW to load Intel plugins.",
            .noThanks:                    "No thanks",
            .applying:                    "Applying...",
            .enableRosettaAction:         "Enable Rosetta",
            .alreadyEnabled:              "Already enabled",
            // Storage/Library
            .available:                   "Available",
            .total:                       "Total",
            .nothingToClean:              "Nothing to clean",
            .scanUnavailable:             "Scan unavailable",
            .quickScan:                   "Quick Scan",
            .overview:                    "OVERVIEW",
            .disabled:                    "Disabled",
            .archived:                    "Archived",
            .review:                      "Review",
            // Log View
            .fullLog:                     "Full log",
            .logSummary:                  "Summary",
            .less:                        "Less",
            .logDetails:                  "Details",
            .copied:                      "Copied!",
            .copyLabel:                   "Copy",
            // Recovery Kit
            .portableSnapshot:            "Portable install snapshot",
            .generating:                  "Generating…",
            .exportFailed:                "Export failed",
            .generate:                    "Generate",
            .cloudBackupLabel:            "Cloud Backup",
            .checking:                    "Checking…",
            .notBackedUp:                 "Not backed up",
            .syncing:                     "Syncing…",
            .restoring:                   "Restoring…",
            .loadRecoveryKit:             "Load Recovery Kit",
            .openKitFile:                 "Open a .atlaskit file",
            .loading:                     "Loading…",
            .kitLoaded:                   "Kit loaded — ready to enter Recovery Mode",
            .fileRejected:                "File rejected — tampered or corrupted",
            .couldNotLoad:                "Could not load file",
            .replace:                     "Replace",
            .open:                        "Open",
            .crossMacKitNote:             "Exported from another Mac — all file paths are shown for reference only.",
            .hashMismatchNote:            "This Recovery Kit file has been modified or corrupted and cannot be loaded.",
            .beginRecovery:               "BEGIN ATLAS RECOVERY",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "Products",
            .update:                      "Update",
            .backUp:                      "Back Up",
            .retryCloudBackup:            "Retry Cloud Backup",
            // TITAN VSCAN
            .detectedThreats:             "DETECTED THREATS",
            .showLess:                    "Show less",
            .showAllFmt:                  "Show all %d",
            .foundIn:                     "Found in",
            .continueInstall:             "Continue Install",
            .proceedWithInstall:          "Proceed with Install",
            .proceedAnyway:               "Proceed Anyway",
            .moveToQuarantine:            "Move to Quarantine",
            .deletePermanently:           "Delete Permanently",
            .stripMalwareInstall:         "Strip Malware & Install Clean",
            .vscanLicenseTip:             "This is a license tool (keygen/patch). TITAN VSCAN™ detected no additional malware. Proceed at your own discretion.",
            .vscanSuspiciousTip:          "Unusual patterns detected. These may be false positives from legitimate software. Review the threats above before proceeding.",
            .vscanMalwareTip:             "TITAN VSCAN™ has blocked this installation. The file contains malware and cannot be safely installed. Move it to quarantine or delete it permanently.",
            .vscanQuarantineConfirmMsg:   "The file will be isolated in a secure ATLAS quarantine folder. You can review or permanently delete it later in ATLAS Settings.",
            .vscanDeleteConfirmMsg:       "This will permanently remove the file from your Mac. This cannot be undone.",
            // Install Overlay
            .stillWorkingFmt:             "Still working… %ds elapsed",
            // Scan Result
            .keygenDetected:              "Keygen / Activation Tool Detected",
            .windowsExe:                  "Windows Executable",
            .keygenWarning:               "⚠ Warning: Keygen File Detected",
            .readyDropInstaller:          "Ready — drop your Mac installer into ATLAS to continue",
            .dropNewFile:                 "Drop New File",
            .imDoneReady:                 "I'm Done — Ready to Continue",
            .confirmationRequired:        "Confirmation required",
            .contentsFound:               "Contents found",
            .alreadyInstalled:            "Already installed",
            .insufficientSpace:           "Insufficient Space",
            .cannotInstallAuto:           "Cannot install automatically",
            .share:                       "Share",
            .installAction2:              "Install",
            // Summary Card
            .userActionRequired:          "USER ACTION REQUIRED",
            .installerMovedToTrash:       "Installer moved to Trash",
            .moveInstallerToTrash:        "Move Installer to Trash",
            .backToHome:                  "Back to Home",
            .removed:                     "REMOVED",
            .supportFiles:                "SUPPORT FILES",
            .couldNotRemove:              "COULD NOT REMOVE",
            .filesMovedToTrash:           "Files moved to Trash — empty Trash in Finder to free space.",
            .recover:                     "Recover",
            // Settings
            .appearance:                  "Appearance",
            .account:                     "Account",
            .supportLabel:                "Support",
            .tourAtlasTitle:              "Tour ATLAS",
            .replayWalkthrough:           "Replay the ATLAS walkthrough",
            .tools:                       "Tools",
            .fixBlockedPlugins:           "Fix Blocked Plugins",
            .removeSecurityBlocks:        "Remove macOS security blocks from installed plugins",
            .fix:                         "Fix",
            .installLimits:               "Install Limits",
            .dailyInstallations:          "Daily Installations",
            .monthlyInstallations:        "Monthly Installations",
            .resetsAtMidnight:            "Resets at midnight",
            .refillsOnBillingDate:        "Refills on billing date",
            .remainingTodayFmt:           "%d remaining today",
            .remainingThisMonthFmt:       "%d remaining this month",
            .notificationsLabel:          "Notifications",
            .installAlerts:               "Install & Uninstall Alerts",
            .notifOn:                     "On — you'll be notified when operations finish",
            .notifOff:                    "Off",
            .vscanSettingTitle:           "Built-In Virus Scanner",
            .vscanSettingSubtitle:        "Scan installers for threats before installation",
            .enableInSystemSettings:      "Enable in System Settings → Notifications",
            .storageLabel:                "Storage",
            .noVolumesFound:              "No volumes found",
            .about:                       "About",
            .viewLogs:                    "View Logs",
            .openLogFolder:               "Open install & uninstall log folder",
            .signOutConfirmMsg:           "You will need to sign in again to use ATLAS.",
            .signOutTitle:                "Sign out of ATLAS?",
            // Support
            .getSupport:                  "GET SUPPORT",
            .replyWithin24:               "We'll reply within 24 hours",
            .product:                     "PRODUCT",
            .issueType:                   "ISSUE TYPE",
            .describeIssue:               "DESCRIBE YOUR ISSUE",
            .attachLog:                   "ATTACH A LOG (OPTIONAL)",
            .sendRequest:                 "Send Support Request",
            .sending:                     "Sending…",
            .thankYou:                    "Thank You!",
            .requestReceived:             "Your support request has been received.",
            .supportTeamReplyFmt:         "Our support team will be with you shortly.\nWe'll reply to %@ within 24 hours.",
            .backToAtlas:                 "Back to ATLAS",
            // Cleaner
            .quickClean:                  "Quick Clean",
            .scanSystemForClutter:        "Scan your system for audio software clutter",
            .itemsMovedToTrashNote:       "Items are moved to macOS Trash — nothing is permanently deleted.",
            .startScan:                   "Start Scan",
            .scanning:                    "Scanning",
            .selectAll:                   "Select All",
            .deselectAll:                 "Deselect All",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "No cleanup items found",
            .systemIsClean:               "Your system is clean",
            .noCleanerHistory:            "No cleaner history yet",
            .cleanerHistory:              "Cleaner History",
            .movingToTrash:               "Moving to Trash…",
            // Failure reasons
            .failReasonIncomplete:        "Installation incomplete — files may not have copied correctly.",
            .failReasonFilesNotLanded:    "Some files didn't land in the right place. Try reinstalling.",
            .failReasonAppNoLaunch:       "The app couldn't launch after install. It may need to be opened manually.",
            .failReasonAUNotRecognized:   "The audio plugin installed but may not be recognised by your DAW yet. Try rescanning plugins.",
            .failReasonDamaged:           "The plugin file appears to be damaged. Try re-downloading the original.",
            .failReasonVerifyFailed:      "ATLAS couldn't confirm the install completed successfully. Check the install log for details.",
            .failReasonConfidenceLow:     "ATLAS wasn't confident this file is safe to install. Try a different version or source.",
            .failReasonScriptError:       "An install script encountered an error. Check the install log for the full output.",
            .failReasonPkgFailed:         "The package installer didn't complete. You may need to run it manually.",
            .failReasonCancelled:         "Install cancelled.",
            .failReasonWaves:             "This Waves product requires a manual install step. See the log for guidance.",
            .failReasonGeneric:           "Something went wrong during install. See the install log for details.",
            // Demo warning
            .demoWarningLabel:            "Installed — but may be running in Demo or Trial mode. Check the product.",
            // Progress steps
            .progressScanningFile:        "Scanning file…",
            .progressOpeningInstaller:    "Opening installer…",
            .progressCopyingFiles:        "Copying files…",
            .progressRunningInstaller:    "Running installer…",
            .progressRunningScript:       "Running setup script…",
            .progressApplyingLicense:     "Applying license settings…",
            .progressVerifying:           "Verifying installation…",
            .progressCheckingLicense:     "Checking license status…",
            .progressSavingProfile:       "Saving install profile…",
            .progressCleaningUp:          "Cleaning up…",
            .progressDone:                "Done.",
            .notifyRestoreCompleteTitle:  "Restore Complete",
            .notifyRestoreFailedTitle:    "Restore Failed",
            .notifyUninstallSuccessBody:  "%@ was removed successfully.",
            .vscanQuarantineNotifBody:    "%@ moved to ATLAS Quarantine.",
            .vscanDeletedNotifBody:       "%@ permanently deleted.",
            .quitInstallAlertTitle:       "Installation in Progress",
            .quitInstallAlertBody:        "ATLAS is currently performing an installation or operation. Quitting now may leave files in an incomplete state.\n\nAre you sure you want to quit?",
            .quitAnyway:                  "Quit Anyway",
            .checkForUpdates:             "Check for Updates",
            .menuOpenAtlas:               "Open ATLAS",
            .menuQuitAtlas:               "Quit ATLAS",
            .fileShareNotifTitle:         "📦 New File Shared",
            .fileShareNotifBodyFmt:       "%@ (%@) is ready to install.",
            .notifyBatchUninstallTitle:   "Session Uninstall Complete",
            .atlasLibrary:                "ATLAS Library",
            .noInstallsYet:               "No installs yet",
            .clearAll:                    "Clear All",
            .deleteAll:                   "Delete All",
            .formatsLabel:                "Formats",
            .signingLabel:                "Signing…",
            .signedLabel:                 "Signed!",
            .permanentlyDeleted:          "Permanently deleted",
            .feedbackReceived:            "Feedback ✓",
            .filesPresent:                "Files present",
            .inTrash:                     "In Trash",
            .filesGone:                   "Files gone",
            .unArchive:                   "Un-Archive",
            .installedOnFmt:              "Installed %@",
            .archivedOnFmt:               "Archived %@",
            .archiveLabelFmt:             "Archive (%d)",
            .sessionFmt:                  "Session · %d · %@",
            .filesTrackedFmt:             "%d file(s) tracked",
            .receiptsAndFilesFmt:         "%d receipt(s) · %d files",
            .uninstall:                   "Uninstall",
            .remove:                      "Remove",
            .feedback:                    "Feedback",
            .support:                     "Support",
            .sign:                        "Sign",
            .enable:                      "Enable",
            .disable:                     "Disable",
            .clearAtlasLibraryTitle:      "Clear ATLAS Library?",
            .clearLibraryMsgFmt:          "All %d install records will be moved to Archive. Installed files are not affected. You can Un-Archive any record at any time.",
            .removeFromLibraryTitle:      "Remove from Library?",
            .removeRecordMsgFmt:          "'%@' will be moved to Archive. Installed files are not affected.",
            .uninstallConfirmTitle:       "Uninstall?",
            .uninstallConfirmMsgFmt:      "ATLAS will move %@ installed by %@ to the Trash.%@\n\nYou can recover them from Trash or use the Recover button.",
            .disabledFormatsNoteFmt:      "\n\nThis also includes %d disabled format(s) in ATLAS storage.",
            .recoverFilesTitle:           "Recover files?",
            .recoverFilesMsgFmt:          "ATLAS will move the files trashed when %@ was uninstalled back to their original locations.",
            .recoveryNotAvailable:        "Recovery Not Available",
            .uninstallSessionTitle:       "Uninstall Session?",
            .uninstallSessionMsgFmt:      "ATLAS will uninstall %d item(s) from this session. Files will be moved to the Trash.",
            .deleteArchivesTitle:         "Permanently Delete Archives?",
            .deleteArchivesMsg:           "This will permanently delete all archived program history from your ATLAS Library. This action cannot be undone.\n\nYour existing Logs are not deleted. For installation history and recorded details, view Logs on your device or in your ATLAS account settings.",
            .deleteAllArchivesBtn:        "Delete All Archives",
            .deleteArchiveTitle:          "Delete Archive Record?",
            .deleteArchiveMsgFmt:         "This permanently removes '%@' from your Archive history. No files on disk are affected.",
            .disableFmtConfirmTitleFmt:   "Disable %@?",
            .disableFmtConfirmMsgFmt:     "ATLAS will move %@ (%@) out of its plugin folder. It will not appear in your DAW until re-enabled.\n\nYou can re-enable it at any time from ATLAS Library.",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .spanish: [
            // Existing
            .notifySuccessTitle:          "Instalación completa",
            .notifySuccessBody:           "%@ instalado correctamente.",
            .notifyFailedTitle:           "Instalación fallida",
            .notifyQueueCompleteTitle:    "ATLAS — Cola completada",
            .notifyQueueCompleteBody:     "%d instalados correctamente",
            .notifyUninstallComplete:     "Desinstalación completa",
            .notifyUninstallFailed:       "Error al desinstalar",
            .notifyRestoreComplete:       "%@ ha sido restaurado.",
            .notifyRestoreFailed:         "%@ no pudo ser restaurado.",
            .installMore:                 "Instalar más",
            .retrying:                    "Reintentando…",
            .cancelConfirmTitle:          "¿Detener la instalación?",
            .cancelConfirmMessage:        "La instalación actual se cancelará y es posible que sea necesario deshacer los cambios parciales.",
            .cancelConfirmStop:           "Detener",
            .cancelConfirmContinue:       "Continuar",
            .titanMissionTitle:           "TITAN CORE™ — Plan de Misión",
            .titanMissionSubtitle:        "ATLAS detectó una instalación de varios pasos. Revisa el plan y comienza.",
            .titanBegin:                  "Iniciar Instalación",
            .titanCancel:                 "Cancelar",
            .titanRunning:                "Ejecutando…",
            .titanComplete:               "Instalación completada",
            .titanStepPending:            "Pendiente",
            .titanStepRunning:            "Ejecutando…",
            .titanStepDone:               "Listo",
            .titanStepFailed:             "Fallido",
            .titanStepSkipped:            "Omitido",
            .titanStepXcodeTools:         "Instalar Xcode Command Line Tools",
            .titanStepInstallPkg:         "Instalar paquete",
            .titanStepRunScript:          "Ejecutar script",
            .titanStepRunBinary:          "Ejecutar herramienta",
            .titanStepEditHosts:          "Bloquear servidor de licencias",
            .titanStepRunCommand:         "Ejecutar comando",
            .titanNoInstrTitle:           "No se encontró guía de instalación",
            .titanNoInstrBody:            "ATLAS encontró archivos que sugieren una instalación compleja, pero no hay guía.",
            .titanNoInstrProvide:         "Proporcionar instrucciones",
            .titanNoInstrAttempt:         "Intentar sin guía",
            .titanNoInstrWarning:         "⚠ Esta instalación puede fallar sin una guía.",
            .titanNoInstrHelp:            "Obtener ayuda de InterLinked",
            .dropFilesHere:               "Soltar archivos aquí",
            .releaseToAdd:                "Suelta para añadir",
            .chooseFile:                  "Elegir archivo o carpeta…",
            .settings:                    "Configuración",
            .language:                    "Idioma",
            .getHelp:                     "Obtener ayuda",
            .signOut:                     "Cerrar sesión",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "Listo",
            .cancel:                      "Cancelar",
            .retry:                       "Reintentar",
            .close:                       "Cerrar",
            // Queue
            .queueInstallQueue:           "Cola de instalación",
            .queueClearWaiting:           "Limpiar en espera",
            .queueInstallAll:             "Instalar todo",
            .queueWaitingForSteps:        "Esperando pasos…",
            .queueStatusWaiting:          "En espera",
            .queueStatusScanning:         "Escaneando",
            .queueStatusInstalling:       "Instalando",
            .queueStatusInstalled:        "Instalado",
            .queueStatusDemoWarning:      "Aviso de demo",
            .queueStatusActivation:       "Activación",
            .queueStatusVerification:     "Verificación",
            // Tour
            .tourDontShowAgain:           "No mostrar de nuevo",
            .tourBack:                    "Atrás",
            .tourNext:                    "Siguiente",
            .tourStepOfFmt:               "%d de %d",
            .tourStep0Title:              "Instalar al soltar",
            .tourStep0Body:               "Arrastra cualquier instalador aquí — DMG, ZIP, PKG, VST3, AAX o RAR. ATLAS lo analiza, te muestra exactamente lo que encontró e instala con un toque. Nada toca tu sistema hasta que lo confirmes.",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "Todo lo que ATLAS sabe sobre tu sistema vive aquí. Productos instalados, formatos de plugins, almacenamiento, herramientas de limpieza y opciones de recuperación — todo en un lugar.",
            .tourStep2Title:              "Tus productos instalados",
            .tourStep2Body:               "Cada instalación queda registrada aquí. Toca para expandir y gestionar tus productos — activa o desactiva formatos individuales (AU, VST3, VST, AAX) y fírmelos directamente desde tu Library.",
            .tourStep3Title:              "Desinstalar y recuperar",
            .tourStep3Body:               "Toca cualquier producto para expandirlo. Los usuarios Pro pueden desinstalar con un toque — ATLAS mueve los archivos a la Papelera y guarda un snapshot de reversión para recuperarlos en cualquier momento.",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "Encuentra archivos sobrantes, componentes huérfanos y cachés temporales recuperables. ATLAS te muestra exactamente lo que encontró antes de eliminar nada.",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "Exporta un snapshot cifrado de toda tu library — cada producto, formato y ruta. Guárdalo de forma segura y reconstruye tu setup completo en cualquier Mac. Copia de seguridad en la nube disponible en Pro.",
            .tourStep6Title:              "Configuración",
            .tourStep6Body:               "Gestiona tu cuenta, suscripción, dispositivos e idioma. Cambia entre apariencia Clara, Oscura o del Sistema. Repite este tour en cualquier momento desde Configuración.",
            .tourStep7Title:              "Estás listo",
            .tourStep7Body:               "Suelta tu primer instalador para comenzar. Tu Library, herramientas de limpieza y opciones de recuperación siempre están a un toque.",
            .tourStep8Title:              "Estás listo",
            .tourStep8Body:               "Suelta tu primer instalador para comenzar. Tu Library, herramientas de limpieza y opciones de recuperación siempre están a un toque.",
            // Demo Alert
            .demoModeDetected:            "MODO DEMO DETECTADO",
            .demoSignalsFound:            "SEÑALES ENCONTRADAS",
            .demoWhatThisMeans:           "QUÉ SIGNIFICA ESTO",
            .demoTip1:                    "Abre el plugin en tu DAW y busca una marca de agua, banner o mensaje de activación.",
            .demoTip2:                    "Si aparece el modo demo, puede que necesites activar o volver a introducir tu licencia.",
            .demoTip3:                    "Contacta con el fabricante si crees que tu licencia es válida pero el plugin sigue en modo demo.",
            // Recovery Mode
            .filterAll:                   "Todos",
            .filterReady:                 "Listo",
            .filterInstalling:            "Instalando",
            .filterInstalled:             "Instalado",
            .filterFailed:                "Fallido",
            .filterPending:               "Pendiente",
            .installReadyProducts:        "INSTALAR PRODUCTOS LISTOS",
            .dropInstallersAbove:         "Suelta los instaladores arriba para empezar",
            .recoveryComplete:            "Recuperación completa",
            .viewInLibrary:               "Ver en Library",
            .exitRecoveryMode:            "Salir del modo de recuperación",
            .statDone:                    "Listo",
            .statSkipped:                 "Omitido",
            .statLimit:                   "Límite",
            .statReinstalled:             "Reinstalado",
            .statPending:                 "Pendiente",
            // Recovery Slot
            .stateLimitReached:           "Límite alcanzado",
            .dropInstallerHere:           "Suelta el instalador aquí",
            .orLabel:                     "o",
            .installAction:               "Instalar",
            // Subscription
            .backToSignIn:                "Volver al inicio de sesión",
            .reJoinAtlas:                 "Reincorporarse a ATLAS",
            .paymentFailed:               "Pago fallido",
            .subscriptionRequired:        "Suscripción requerida",
            .checkingEllipsis:            "Verificando…",
            .iveSubscribed:               "Me he suscrito — Actualizar",
            .subscribeNow:                "Suscribirse ahora",
            .updateBilling:               "Actualizar facturación",
            .subBodyReJoin:               "Tu suscripción ha caducado. Reincorpórate a ATLAS para continuar instalando.",
            .subBodyPayment:              "Tu último pago falló. Actualiza tus datos de facturación para continuar.",
            .subBodyNew:                  "Suscríbete a ATLAS para empezar a instalar plugins en segundos.",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "CONTRASEÑA REQUERIDA",
            .filePasswordProtected:       "Este archivo está protegido con contraseña",
            .archivePassword:             "CONTRASEÑA DEL ARCHIVO",
            .enterPassword:               "Introduce la contraseña",
            .rememberPassword:            "ATLAS recordará esta contraseña para futuras instalaciones de este producto.",
            .unlockAndInstall:            "Desbloquear e instalar",
            // Rosetta
            .appleSiliconDetected:        "Apple Silicon detectado",
            .enableRosettaQ:              "¿Activar Rosetta en tus DAWs para cargar plugins Intel?",
            .scanningDAWs:                "Buscando DAWs instalados...",
            .noDAWsFound:                 "No se encontraron DAWs en este Mac.",
            .selectDAWsRosetta:           "Selecciona los DAWs para activar Rosetta:",
            .rosettaEnabledMsg:           "Rosetta activado para los DAWs seleccionados. Reinicia tu DAW para cargar plugins Intel.",
            .noThanks:                    "No, gracias",
            .applying:                    "Aplicando...",
            .enableRosettaAction:         "Activar Rosetta",
            .alreadyEnabled:              "Ya activado",
            // Storage/Library
            .available:                   "Disponible",
            .total:                       "Total",
            .nothingToClean:              "Nada que limpiar",
            .scanUnavailable:             "Análisis no disponible",
            .quickScan:                   "Análisis rápido",
            .overview:                    "RESUMEN",
            .disabled:                    "Desactivado",
            .archived:                    "Archivado",
            .review:                      "Revisar",
            // Log View
            .fullLog:                     "Registro completo",
            .logSummary:                  "Resumen",
            .less:                        "Menos",
            .logDetails:                  "Detalles",
            .copied:                      "¡Copiado!",
            .copyLabel:                   "Copiar",
            // Recovery Kit
            .portableSnapshot:            "Instantánea portátil de instalación",
            .generating:                  "Generando…",
            .exportFailed:                "Error al exportar",
            .generate:                    "Generar",
            .cloudBackupLabel:            "Copia de seguridad en la nube",
            .checking:                    "Verificando…",
            .notBackedUp:                 "Sin copia de seguridad",
            .syncing:                     "Sincronizando…",
            .restoring:                   "Restaurando…",
            .loadRecoveryKit:             "Cargar Recovery Kit",
            .openKitFile:                 "Abrir un archivo .atlaskit",
            .loading:                     "Cargando…",
            .kitLoaded:                   "Kit cargado — listo para entrar en Modo de recuperación",
            .fileRejected:                "Archivo rechazado — manipulado o dañado",
            .couldNotLoad:                "No se pudo cargar el archivo",
            .replace:                     "Reemplazar",
            .open:                        "Abrir",
            .crossMacKitNote:             "Exportado desde otro Mac — todas las rutas se muestran solo como referencia.",
            .hashMismatchNote:            "Este archivo Recovery Kit ha sido modificado o dañado y no se puede cargar.",
            .beginRecovery:               "INICIAR ATLAS RECOVERY",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "Productos",
            .update:                      "Actualizar",
            .backUp:                      "Hacer copia",
            .retryCloudBackup:            "Reintentar copia en la nube",
            // TITAN VSCAN
            .detectedThreats:             "AMENAZAS DETECTADAS",
            .showLess:                    "Mostrar menos",
            .showAllFmt:                  "Mostrar todos (%d)",
            .foundIn:                     "Encontrado en",
            .continueInstall:             "Continuar instalación",
            .proceedWithInstall:          "Proceder con la instalación",
            .proceedAnyway:               "Proceder de todas formas",
            .moveToQuarantine:            "Mover a cuarentena",
            .deletePermanently:           "Eliminar permanentemente",
            .stripMalwareInstall:         "Eliminar malware e instalar limpio",
            .vscanLicenseTip:             "Esta es una herramienta de licencia (keygen/parche). TITAN VSCAN™ no detectó malware adicional. Procede bajo tu propia responsabilidad.",
            .vscanSuspiciousTip:          "Se detectaron patrones inusuales. Pueden ser falsos positivos de software legítimo. Revisa las amenazas antes de continuar.",
            .vscanMalwareTip:             "TITAN VSCAN™ ha bloqueado esta instalación. El archivo contiene malware y no puede instalarse de forma segura. Muévelo a cuarentena o elimínalo permanentemente.",
            .vscanQuarantineConfirmMsg:   "El archivo será aislado en una carpeta de cuarentena segura de ATLAS. Puedes revisarlo o eliminarlo permanentemente en Configuración de ATLAS.",
            .vscanDeleteConfirmMsg:       "Esto eliminará el archivo permanentemente de tu Mac. Esta acción no se puede deshacer.",
            // Install Overlay
            .stillWorkingFmt:             "Trabajando… %d s transcurridos",
            // Scan Result
            .keygenDetected:              "Keygen / Herramienta de activación detectada",
            .windowsExe:                  "Ejecutable de Windows",
            .keygenWarning:               "⚠ Advertencia: archivo keygen detectado",
            .readyDropInstaller:          "Listo — suelta tu instalador de Mac en ATLAS para continuar",
            .dropNewFile:                 "Soltar nuevo archivo",
            .imDoneReady:                 "He terminado — Listo para continuar",
            .confirmationRequired:        "Confirmación requerida",
            .contentsFound:               "Contenido encontrado",
            .alreadyInstalled:            "Ya instalado",
            .insufficientSpace:           "Espacio insuficiente",
            .cannotInstallAuto:           "No se puede instalar automáticamente",
            .share:                       "Compartir",
            .installAction2:              "Instalar",
            // Summary Card
            .userActionRequired:          "ACCIÓN DEL USUARIO REQUERIDA",
            .installerMovedToTrash:       "Instalador movido a la Papelera",
            .moveInstallerToTrash:        "Mover instalador a la Papelera",
            .backToHome:                  "Volver al inicio",
            .removed:                     "ELIMINADO",
            .supportFiles:                "ARCHIVOS DE SOPORTE",
            .couldNotRemove:              "NO SE PUDO ELIMINAR",
            .filesMovedToTrash:           "Archivos movidos a la Papelera — vacía la Papelera en Finder para liberar espacio.",
            .recover:                     "Recuperar",
            // Settings
            .appearance:                  "Apariencia",
            .account:                     "Cuenta",
            .supportLabel:                "Soporte",
            .tourAtlasTitle:              "Tour ATLAS",
            .replayWalkthrough:           "Repetir el recorrido de ATLAS",
            .tools:                       "Herramientas",
            .fixBlockedPlugins:           "Reparar plugins bloqueados",
            .removeSecurityBlocks:        "Eliminar bloqueos de seguridad de macOS en plugins instalados",
            .fix:                         "Reparar",
            .installLimits:               "Límites de instalación",
            .dailyInstallations:          "Instalaciones diarias",
            .monthlyInstallations:        "Instalaciones mensuales",
            .resetsAtMidnight:            "Se restablece a medianoche",
            .refillsOnBillingDate:        "Se recarga en la fecha de facturación",
            .remainingTodayFmt:           "%d restantes hoy",
            .remainingThisMonthFmt:       "%d restantes este mes",
            .notificationsLabel:          "Notificaciones",
            .installAlerts:               "Alertas de instalación y desinstalación",
            .notifOn:                     "Activadas — recibirás notificaciones al finalizar las operaciones",
            .notifOff:                    "Desactivadas",
            .vscanSettingTitle:           "Escáner de virus integrado",
            .vscanSettingSubtitle:        "Analiza los instaladores en busca de amenazas antes de instalar",
            .enableInSystemSettings:      "Activar en Configuración del Sistema → Notificaciones",
            .storageLabel:                "Almacenamiento",
            .noVolumesFound:              "No se encontraron volúmenes",
            .about:                       "Acerca de",
            .viewLogs:                    "Ver registros",
            .openLogFolder:               "Abrir carpeta de registros de instalación y desinstalación",
            .signOutConfirmMsg:           "Necesitarás iniciar sesión de nuevo para usar ATLAS.",
            .signOutTitle:                "¿Cerrar sesión de ATLAS?",
            // Support
            .getSupport:                  "OBTENER SOPORTE",
            .replyWithin24:               "Responderemos en 24 horas",
            .product:                     "PRODUCTO",
            .issueType:                   "TIPO DE PROBLEMA",
            .describeIssue:               "DESCRIBE TU PROBLEMA",
            .attachLog:                   "ADJUNTAR UN REGISTRO (OPCIONAL)",
            .sendRequest:                 "Enviar solicitud de soporte",
            .sending:                     "Enviando…",
            .thankYou:                    "¡Gracias!",
            .requestReceived:             "Tu solicitud de soporte ha sido recibida.",
            .supportTeamReplyFmt:         "Nuestro equipo de soporte estará contigo en breve.\nResponderemos a %@ en 24 horas.",
            .backToAtlas:                 "Volver a ATLAS",
            // Cleaner
            .quickClean:                  "Limpieza rápida",
            .scanSystemForClutter:        "Analiza tu sistema en busca de software de audio innecesario",
            .itemsMovedToTrashNote:       "Los elementos se mueven a la Papelera de macOS — nada se elimina permanentemente.",
            .startScan:                   "Iniciar análisis",
            .scanning:                    "Analizando",
            .selectAll:                   "Seleccionar todo",
            .deselectAll:                 "Deseleccionar todo",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "No se encontraron elementos para limpiar",
            .systemIsClean:               "Tu sistema está limpio",
            .noCleanerHistory:            "Sin historial de limpieza",
            .cleanerHistory:              "Historial de limpieza",
            .movingToTrash:               "Moviendo a la Papelera…",
            // Failure reasons
            .failReasonIncomplete:        "Instalación incompleta — es posible que los archivos no se hayan copiado correctamente.",
            .failReasonFilesNotLanded:    "Algunos archivos no llegaron al lugar correcto. Intenta reinstalar.",
            .failReasonAppNoLaunch:       "La app no pudo iniciarse tras la instalación. Es posible que deba abrirse manualmente.",
            .failReasonAUNotRecognized:   "El plugin de audio se instaló pero puede que tu DAW aún no lo reconozca. Intenta reescanear los plugins.",
            .failReasonDamaged:           "El archivo del plugin parece estar dañado. Intenta volver a descargar el original.",
            .failReasonVerifyFailed:      "ATLAS no pudo confirmar que la instalación se completó correctamente. Consulta el registro.",
            .failReasonConfidenceLow:     "ATLAS no estaba seguro de que este archivo fuera seguro para instalar. Prueba con una versión o fuente diferente.",
            .failReasonScriptError:       "Un script de instalación encontró un error. Consulta el registro de instalación para ver el resultado completo.",
            .failReasonPkgFailed:         "El instalador del paquete no se completó. Es posible que debas ejecutarlo manualmente.",
            .failReasonCancelled:         "Instalación cancelada.",
            .failReasonWaves:             "Este producto de Waves requiere un paso de instalación manual. Consulta el registro.",
            .failReasonGeneric:           "Algo salió mal durante la instalación. Consulta el registro de instalación.",
            // Demo warning
            .demoWarningLabel:            "Instalado — pero puede estar en modo Demo o Trial. Comprueba el producto.",
            // Progress steps
            .progressScanningFile:        "Analizando archivo…",
            .progressOpeningInstaller:    "Abriendo instalador…",
            .progressCopyingFiles:        "Copiando archivos…",
            .progressRunningInstaller:    "Ejecutando instalador…",
            .progressRunningScript:       "Ejecutando script de configuración…",
            .progressApplyingLicense:     "Aplicando configuración de licencia…",
            .progressVerifying:           "Verificando instalación…",
            .progressCheckingLicense:     "Comprobando estado de licencia…",
            .progressSavingProfile:       "Guardando perfil de instalación…",
            .progressCleaningUp:          "Limpiando…",
            .progressDone:                "Listo.",
            .notifyRestoreCompleteTitle:  "Restauración completa",
            .notifyRestoreFailedTitle:    "Error al restaurar",
            .notifyUninstallSuccessBody:  "%@ se eliminó correctamente.",
            .vscanQuarantineNotifBody:    "%@ movido a cuarentena de ATLAS.",
            .vscanDeletedNotifBody:       "%@ eliminado permanentemente.",
            .quitInstallAlertTitle:       "Instalación en curso",
            .quitInstallAlertBody:        "ATLAS está realizando una instalación. Salir ahora puede dejar archivos en un estado incompleto.\n\n¿Seguro que deseas salir?",
            .quitAnyway:                  "Salir de todos modos",
            .checkForUpdates:             "Buscar actualizaciones",
            .menuOpenAtlas:               "Abrir ATLAS",
            .menuQuitAtlas:               "Salir de ATLAS",
            .fileShareNotifTitle:         "📦 Nuevo archivo compartido",
            .fileShareNotifBodyFmt:       "%@ (%@) está listo para instalar.",
            .notifyBatchUninstallTitle:   "Desinstalación de sesión completada",
            .atlasLibrary:                "Biblioteca ATLAS",
            .noInstallsYet:               "Sin instalaciones aún",
            .clearAll:                    "Borrar todo",
            .deleteAll:                   "Eliminar todo",
            .formatsLabel:                "Formatos",
            .signingLabel:                "Firmando…",
            .signedLabel:                 "¡Firmado!",
            .permanentlyDeleted:          "Eliminado permanentemente",
            .feedbackReceived:            "Comentarios ✓",
            .filesPresent:                "Archivos presentes",
            .inTrash:                     "En la papelera",
            .filesGone:                   "Archivos eliminados",
            .unArchive:                   "Desarchivar",
            .installedOnFmt:              "Instalado el %@",
            .archivedOnFmt:               "Archivado el %@",
            .archiveLabelFmt:             "Archivo (%d)",
            .sessionFmt:                  "Sesión · %d · %@",
            .filesTrackedFmt:             "%d archivo(s) rastreado(s)",
            .receiptsAndFilesFmt:         "%d recibo(s) · %d archivos",
            .uninstall:                   "Desinstalar",
            .remove:                      "Eliminar",
            .feedback:                    "Comentarios",
            .support:                     "Soporte",
            .sign:                        "Firmar",
            .enable:                      "Activar",
            .disable:                     "Desactivar",
            .clearAtlasLibraryTitle:      "¿Borrar Biblioteca ATLAS?",
            .clearLibraryMsgFmt:          "Todos los %d registros de instalación se moverán al Archivo. Los archivos instalados no se verán afectados. Puede desarchivar cualquier registro en cualquier momento.",
            .removeFromLibraryTitle:      "¿Eliminar de la Biblioteca?",
            .removeRecordMsgFmt:          "'%@' se moverá al Archivo. Los archivos instalados no se verán afectados.",
            .uninstallConfirmTitle:       "¿Desinstalar?",
            .uninstallConfirmMsgFmt:      "ATLAS moverá %@ instalado por %@ a la papelera.%@\n\nPuede recuperarlos desde la papelera o usando el botón Recuperar.",
            .disabledFormatsNoteFmt:      "\n\nEsto también incluye %d formato(s) desactivado(s) en el almacenamiento ATLAS.",
            .recoverFilesTitle:           "¿Recuperar archivos?",
            .recoverFilesMsgFmt:          "ATLAS moverá los archivos enviados a la papelera cuando %@ fue desinstalado de vuelta a sus ubicaciones originales.",
            .recoveryNotAvailable:        "Recuperación no disponible",
            .uninstallSessionTitle:       "¿Desinstalar sesión?",
            .uninstallSessionMsgFmt:      "ATLAS desinstalará %d elemento(s) de esta sesión. Los archivos se moverán a la papelera.",
            .deleteArchivesTitle:         "¿Eliminar archivos permanentemente?",
            .deleteArchivesMsg:           "Esto eliminará permanentemente todo el historial de programas archivados de su Biblioteca ATLAS. Esta acción no se puede deshacer.\n\nSus registros existentes no se eliminarán.",
            .deleteAllArchivesBtn:        "Eliminar todos los archivos",
            .deleteArchiveTitle:          "¿Eliminar registro del Archivo?",
            .deleteArchiveMsgFmt:         "Esto elimina permanentemente '%@' de su historial de Archivo. No se ven afectados archivos en disco.",
            .disableFmtConfirmTitleFmt:   "¿Desactivar %@?",
            .disableFmtConfirmMsgFmt:     "ATLAS moverá %@ (%@) fuera de su carpeta de plugins. No aparecerá en su DAW hasta que sea reactivado.\n\nPuede reactivarlo en cualquier momento desde la Biblioteca ATLAS.",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .french: [
            // Existing
            .notifySuccessTitle:          "Installation terminée",
            .notifySuccessBody:           "%@ installé avec succès.",
            .notifyFailedTitle:           "Échec de l'installation",
            .notifyQueueCompleteTitle:    "ATLAS — File d'attente terminée",
            .notifyQueueCompleteBody:     "%d installé(s) avec succès",
            .notifyUninstallComplete:     "Désinstallation terminée",
            .notifyUninstallFailed:       "Échec de la désinstallation",
            .notifyRestoreComplete:       "%@ a été restauré.",
            .notifyRestoreFailed:         "%@ n'a pas pu être restauré.",
            .installMore:                 "Installer plus",
            .retrying:                    "Nouvelle tentative…",
            .cancelConfirmTitle:          "Arrêter l'installation ?",
            .cancelConfirmMessage:        "L'installation en cours sera annulée et les modifications partielles devront peut-être être annulées.",
            .cancelConfirmStop:           "Arrêter",
            .cancelConfirmContinue:       "Continuer",
            .titanMissionTitle:           "TITAN CORE™ — Plan de Mission",
            .titanMissionSubtitle:        "ATLAS a détecté une installation multi-étapes. Vérifiez le plan, puis commencez.",
            .titanBegin:                  "Démarrer l'installation",
            .titanCancel:                 "Annuler",
            .titanRunning:                "En cours…",
            .titanComplete:               "Installation terminée",
            .titanStepPending:            "En attente",
            .titanStepRunning:            "En cours…",
            .titanStepDone:               "Terminé",
            .titanStepFailed:             "Échoué",
            .titanStepSkipped:            "Ignoré",
            .titanStepXcodeTools:         "Installer Xcode Command Line Tools",
            .titanStepInstallPkg:         "Installer le paquet",
            .titanStepRunScript:          "Exécuter le script",
            .titanStepRunBinary:          "Exécuter l'outil",
            .titanStepEditHosts:          "Bloquer le serveur de licences",
            .titanStepRunCommand:         "Exécuter la commande",
            .titanNoInstrTitle:           "Aucun guide d'installation trouvé",
            .titanNoInstrBody:            "ATLAS a trouvé des fichiers suggérant une installation complexe, mais sans guide.",
            .titanNoInstrProvide:         "Fournir des instructions",
            .titanNoInstrAttempt:         "Essayer sans guide",
            .titanNoInstrWarning:         "⚠ Cette installation peut échouer sans guide.",
            .titanNoInstrHelp:            "Obtenir de l'aide d'InterLinked",
            .dropFilesHere:               "Déposer les fichiers ici",
            .releaseToAdd:                "Relâcher pour ajouter",
            .chooseFile:                  "Choisir un fichier ou dossier…",
            .settings:                    "Réglages",
            .language:                    "Langue",
            .getHelp:                     "Obtenir de l'aide",
            .signOut:                     "Déconnexion",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "Terminé",
            .cancel:                      "Annuler",
            .retry:                       "Réessayer",
            .close:                       "Fermer",
            // Queue
            .queueInstallQueue:           "File d'installation",
            .queueClearWaiting:           "Vider l'attente",
            .queueInstallAll:             "Tout installer",
            .queueWaitingForSteps:        "En attente des étapes…",
            .queueStatusWaiting:          "En attente",
            .queueStatusScanning:         "Analyse",
            .queueStatusInstalling:       "Installation",
            .queueStatusInstalled:        "Installé",
            .queueStatusDemoWarning:      "Avertissement démo",
            .queueStatusActivation:       "Activation",
            .queueStatusVerification:     "Vérification",
            // Tour
            .tourDontShowAgain:           "Ne plus afficher",
            .tourBack:                    "Retour",
            .tourNext:                    "Suivant",
            .tourStepOfFmt:               "%d sur %d",
            .tourStep0Title:              "Déposer et installer",
            .tourStep0Body:               "Faites glisser n'importe quel installeur ici — DMG, ZIP, PKG, VST3, AAX ou RAR. ATLAS l'analyse, vous montre exactement ce qu'il a trouvé et l'installe en un appui. Rien ne touche votre système tant que vous n'avez pas confirmé.",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "Tout ce qu'ATLAS sait de votre configuration se trouve ici. Vos produits installés, formats de plugins, stockage, outils de nettoyage et options de récupération — tout en un seul endroit.",
            .tourStep2Title:              "Vos produits installés",
            .tourStep2Body:               "Chaque installation est enregistrée ici. Appuyez pour développer et gérer vos produits — activez ou désactivez les formats individuels (AU, VST3, VST, AAX) et signez-les directement depuis votre Library.",
            .tourStep3Title:              "Désinstaller et récupérer",
            .tourStep3Body:               "Appuyez sur un produit pour le développer. Les utilisateurs Pro peuvent désinstaller en un appui — ATLAS déplace les fichiers dans la Corbeille et enregistre un instantané de restauration pour les récupérer à tout moment.",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "Trouvez les fichiers d'installation résiduels, les composants orphelins et les caches temporaires récupérables. ATLAS vous montre exactement ce qu'il a trouvé avant de supprimer quoi que ce soit.",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "Exportez un instantané chiffré de toute votre bibliothèque — chaque produit, format et chemin. Conservez-le en sécurité et reconstruisez votre setup complet sur n'importe quel Mac. Sauvegarde cloud disponible sur Pro.",
            .tourStep6Title:              "Réglages",
            .tourStep6Body:               "Gérez votre compte, abonnement, appareils et langue. Basculez entre l'apparence Claire, Sombre ou Système. Rejouez ce tour à tout moment depuis Réglages.",
            .tourStep7Title:              "Vous êtes prêt",
            .tourStep7Body:               "Déposez votre premier installeur pour commencer. Votre Library, vos outils de nettoyage et vos options de récupération sont toujours à portée de main.",
            .tourStep8Title:              "Vous êtes prêt",
            .tourStep8Body:               "Déposez votre premier installeur pour commencer. Votre Library, vos outils de nettoyage et vos options de récupération sont toujours à portée de main.",
            // Demo Alert
            .demoModeDetected:            "MODE DÉMO DÉTECTÉ",
            .demoSignalsFound:            "SIGNAUX TROUVÉS",
            .demoWhatThisMeans:           "CE QUE CELA SIGNIFIE",
            .demoTip1:                    "Ouvrez le plugin dans votre DAW et recherchez un filigrane, une bannière ou une invite d'activation.",
            .demoTip2:                    "Si le mode démo apparaît, vous devrez peut-être activer ou ressaisir votre licence.",
            .demoTip3:                    "Contactez le fournisseur si vous pensez que votre licence est valide mais que le plugin affiche toujours le mode démo.",
            // Recovery Mode
            .filterAll:                   "Tous",
            .filterReady:                 "Prêt",
            .filterInstalling:            "Installation",
            .filterInstalled:             "Installé",
            .filterFailed:                "Échoué",
            .filterPending:               "En attente",
            .installReadyProducts:        "INSTALLER LES PRODUITS PRÊTS",
            .dropInstallersAbove:         "Déposez les installeurs ci-dessus pour commencer",
            .recoveryComplete:            "Récupération terminée",
            .viewInLibrary:               "Voir dans la bibliothèque",
            .exitRecoveryMode:            "Quitter le mode récupération",
            .statDone:                    "Terminé",
            .statSkipped:                 "Ignoré",
            .statLimit:                   "Limite",
            .statReinstalled:             "Réinstallé",
            .statPending:                 "En attente",
            // Recovery Slot
            .stateLimitReached:           "Limite atteinte",
            .dropInstallerHere:           "Déposez l'installeur ici",
            .orLabel:                     "ou",
            .installAction:               "Installer",
            // Subscription
            .backToSignIn:                "Retour à la connexion",
            .reJoinAtlas:                 "Rejoindre ATLAS",
            .paymentFailed:               "Échec du paiement",
            .subscriptionRequired:        "Abonnement requis",
            .checkingEllipsis:            "Vérification…",
            .iveSubscribed:               "Je suis abonné — Actualiser",
            .subscribeNow:                "S'abonner maintenant",
            .updateBilling:               "Mettre à jour la facturation",
            .subBodyReJoin:               "Votre abonnement a expiré. Rejoignez ATLAS pour continuer à installer.",
            .subBodyPayment:              "Votre dernier paiement a échoué. Mettez à jour vos informations de facturation pour continuer.",
            .subBodyNew:                  "Abonnez-vous à ATLAS pour commencer à installer des plugins en quelques secondes.",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "MOT DE PASSE REQUIS",
            .filePasswordProtected:       "Ce fichier est protégé par un mot de passe",
            .archivePassword:             "MOT DE PASSE DE L'ARCHIVE",
            .enterPassword:               "Saisir le mot de passe",
            .rememberPassword:            "ATLAS mémorisera ce mot de passe pour les futures installations de ce produit.",
            .unlockAndInstall:            "Déverrouiller et installer",
            // Rosetta
            .appleSiliconDetected:        "Apple Silicon détecté",
            .enableRosettaQ:              "Activer Rosetta sur vos DAW pour charger des plugins Intel ?",
            .scanningDAWs:                "Recherche des DAW installés...",
            .noDAWsFound:                 "Aucun DAW trouvé sur ce Mac.",
            .selectDAWsRosetta:           "Sélectionnez les DAW pour activer Rosetta :",
            .rosettaEnabledMsg:           "Rosetta activé pour les DAW sélectionnés. Redémarrez votre DAW pour charger les plugins Intel.",
            .noThanks:                    "Non merci",
            .applying:                    "Application...",
            .enableRosettaAction:         "Activer Rosetta",
            .alreadyEnabled:              "Déjà activé",
            // Storage/Library
            .available:                   "Disponible",
            .total:                       "Total",
            .nothingToClean:              "Rien à nettoyer",
            .scanUnavailable:             "Analyse indisponible",
            .quickScan:                   "Analyse rapide",
            .overview:                    "APERÇU",
            .disabled:                    "Désactivé",
            .archived:                    "Archivé",
            .review:                      "Examiner",
            // Log View
            .fullLog:                     "Journal complet",
            .logSummary:                  "Résumé",
            .less:                        "Moins",
            .logDetails:                  "Détails",
            .copied:                      "Copié !",
            .copyLabel:                   "Copier",
            // Recovery Kit
            .portableSnapshot:            "Instantané d'installation portable",
            .generating:                  "Génération…",
            .exportFailed:                "Échec de l'export",
            .generate:                    "Générer",
            .cloudBackupLabel:            "Sauvegarde cloud",
            .checking:                    "Vérification…",
            .notBackedUp:                 "Non sauvegardé",
            .syncing:                     "Synchronisation…",
            .restoring:                   "Restauration…",
            .loadRecoveryKit:             "Charger Recovery Kit",
            .openKitFile:                 "Ouvrir un fichier .atlaskit",
            .loading:                     "Chargement…",
            .kitLoaded:                   "Kit chargé — prêt à entrer en mode récupération",
            .fileRejected:                "Fichier rejeté — modifié ou corrompu",
            .couldNotLoad:                "Impossible de charger le fichier",
            .replace:                     "Remplacer",
            .open:                        "Ouvrir",
            .crossMacKitNote:             "Exporté depuis un autre Mac — tous les chemins de fichiers sont affichés à titre de référence uniquement.",
            .hashMismatchNote:            "Ce fichier Recovery Kit a été modifié ou corrompu et ne peut pas être chargé.",
            .beginRecovery:               "DÉMARRER ATLAS RECOVERY",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "Produits",
            .update:                      "Mettre à jour",
            .backUp:                      "Sauvegarder",
            .retryCloudBackup:            "Réessayer la sauvegarde cloud",
            // TITAN VSCAN
            .detectedThreats:             "MENACES DÉTECTÉES",
            .showLess:                    "Afficher moins",
            .showAllFmt:                  "Tout afficher (%d)",
            .foundIn:                     "Trouvé dans",
            .continueInstall:             "Continuer l'installation",
            .proceedWithInstall:          "Procéder à l'installation",
            .proceedAnyway:               "Continuer quand même",
            .moveToQuarantine:            "Mettre en quarantaine",
            .deletePermanently:           "Supprimer définitivement",
            .stripMalwareInstall:         "Supprimer le malware et installer proprement",
            .vscanLicenseTip:             "Il s'agit d'un outil de licence (keygen/patch). TITAN VSCAN™ n'a détecté aucun malware supplémentaire. Procédez à votre discrétion.",
            .vscanSuspiciousTip:          "Des schémas inhabituels ont été détectés. Il peut s'agir de faux positifs de logiciels légitimes. Examinez les menaces ci-dessus avant de continuer.",
            .vscanMalwareTip:             "TITAN VSCAN™ a bloqué cette installation. Le fichier contient un malware et ne peut pas être installé en toute sécurité. Mettez-le en quarantaine ou supprimez-le définitivement.",
            .vscanQuarantineConfirmMsg:   "Le fichier sera isolé dans un dossier de quarantaine sécurisé ATLAS. Vous pourrez le réviser ou le supprimer définitivement dans Réglages ATLAS.",
            .vscanDeleteConfirmMsg:       "Cela supprimera définitivement le fichier de votre Mac. Cette action est irréversible.",
            // Install Overlay
            .stillWorkingFmt:             "Toujours en cours… %d s écoulées",
            // Scan Result
            .keygenDetected:              "Keygen / Outil d'activation détecté",
            .windowsExe:                  "Exécutable Windows",
            .keygenWarning:               "⚠ Avertissement : fichier keygen détecté",
            .readyDropInstaller:          "Prêt — déposez votre installeur Mac dans ATLAS pour continuer",
            .dropNewFile:                 "Déposer un nouveau fichier",
            .imDoneReady:                 "J'ai terminé — Prêt à continuer",
            .confirmationRequired:        "Confirmation requise",
            .contentsFound:               "Contenu trouvé",
            .alreadyInstalled:            "Déjà installé",
            .insufficientSpace:           "Espace insuffisant",
            .cannotInstallAuto:           "Impossible d'installer automatiquement",
            .share:                       "Partager",
            .installAction2:              "Installer",
            // Summary Card
            .userActionRequired:          "ACTION UTILISATEUR REQUISE",
            .installerMovedToTrash:       "Installeur déplacé vers la Corbeille",
            .moveInstallerToTrash:        "Déplacer l'installeur vers la Corbeille",
            .backToHome:                  "Retour à l'accueil",
            .removed:                     "SUPPRIMÉ",
            .supportFiles:                "FICHIERS SUPPORT",
            .couldNotRemove:              "IMPOSSIBLE DE SUPPRIMER",
            .filesMovedToTrash:           "Fichiers déplacés vers la Corbeille — videz la Corbeille dans le Finder pour libérer de l'espace.",
            .recover:                     "Récupérer",
            // Settings
            .appearance:                  "Apparence",
            .account:                     "Compte",
            .supportLabel:                "Support",
            .tourAtlasTitle:              "Tour ATLAS",
            .replayWalkthrough:           "Rejouer le tutoriel ATLAS",
            .tools:                       "Outils",
            .fixBlockedPlugins:           "Réparer les plugins bloqués",
            .removeSecurityBlocks:        "Supprimer les restrictions de sécurité macOS sur les plugins installés",
            .fix:                         "Réparer",
            .installLimits:               "Limites d'installation",
            .dailyInstallations:          "Installations quotidiennes",
            .monthlyInstallations:        "Installations mensuelles",
            .resetsAtMidnight:            "Réinitialisé à minuit",
            .refillsOnBillingDate:        "Rechargé à la date de facturation",
            .remainingTodayFmt:           "%d restants aujourd'hui",
            .remainingThisMonthFmt:       "%d restants ce mois",
            .notificationsLabel:          "Notifications",
            .installAlerts:               "Alertes d'installation et de désinstallation",
            .notifOn:                     "Activées — vous serez notifié lorsque les opérations se terminent",
            .notifOff:                    "Désactivées",
            .vscanSettingTitle:           "Antivirus intégré",
            .vscanSettingSubtitle:        "Analyse les installateurs à la recherche de menaces avant installation",
            .enableInSystemSettings:      "Activer dans Réglages Système → Notifications",
            .storageLabel:                "Stockage",
            .noVolumesFound:              "Aucun volume trouvé",
            .about:                       "À propos",
            .viewLogs:                    "Voir les journaux",
            .openLogFolder:               "Ouvrir le dossier des journaux d'installation",
            .signOutConfirmMsg:           "Vous devrez vous reconnecter pour utiliser ATLAS.",
            .signOutTitle:                "Se déconnecter d'ATLAS ?",
            // Support
            .getSupport:                  "OBTENIR DE L'AIDE",
            .replyWithin24:               "Nous répondrons dans les 24 heures",
            .product:                     "PRODUIT",
            .issueType:                   "TYPE DE PROBLÈME",
            .describeIssue:               "DÉCRIVEZ VOTRE PROBLÈME",
            .attachLog:                   "JOINDRE UN JOURNAL (OPTIONNEL)",
            .sendRequest:                 "Envoyer la demande d'assistance",
            .sending:                     "Envoi…",
            .thankYou:                    "Merci !",
            .requestReceived:             "Votre demande d'assistance a bien été reçue.",
            .supportTeamReplyFmt:         "Notre équipe d'assistance vous répondra sous peu.\nNous répondrons à %@ dans les 24 heures.",
            .backToAtlas:                 "Retour à ATLAS",
            // Cleaner
            .quickClean:                  "Nettoyage rapide",
            .scanSystemForClutter:        "Analyser votre système pour trouver les encombrants audio",
            .itemsMovedToTrashNote:       "Les éléments sont déplacés vers la Corbeille macOS — rien n'est définitivement supprimé.",
            .startScan:                   "Démarrer l'analyse",
            .scanning:                    "Analyse",
            .selectAll:                   "Tout sélectionner",
            .deselectAll:                 "Tout désélectionner",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "Aucun élément à nettoyer",
            .systemIsClean:               "Votre système est propre",
            .noCleanerHistory:            "Aucun historique de nettoyage",
            .cleanerHistory:              "Historique de nettoyage",
            .movingToTrash:               "Déplacement vers la Corbeille…",
            // Failure reasons
            .failReasonIncomplete:        "Installation incomplète — les fichiers n'ont peut-être pas été copiés correctement.",
            .failReasonFilesNotLanded:    "Certains fichiers ne sont pas arrivés au bon endroit. Essayez de réinstaller.",
            .failReasonAppNoLaunch:       "L'application n'a pas pu se lancer après l'installation. Elle devra peut-être être ouverte manuellement.",
            .failReasonAUNotRecognized:   "Le plugin audio est installé mais n'est peut-être pas encore reconnu par votre DAW. Essayez de relancer la recherche de plugins.",
            .failReasonDamaged:           "Le fichier plugin semble endommagé. Essayez de retélécharger l'original.",
            .failReasonVerifyFailed:      "ATLAS n'a pas pu confirmer la bonne fin de l'installation. Consultez le journal.",
            .failReasonConfidenceLow:     "ATLAS n'était pas sûr que ce fichier soit sûr à installer. Essayez une version ou une source différente.",
            .failReasonScriptError:       "Un script d'installation a rencontré une erreur. Consultez le journal pour la sortie complète.",
            .failReasonPkgFailed:         "L'installeur de paquet ne s'est pas terminé. Vous devrez peut-être l'exécuter manuellement.",
            .failReasonCancelled:         "Installation annulée.",
            .failReasonWaves:             "Ce produit Waves nécessite une étape d'installation manuelle. Consultez le journal.",
            .failReasonGeneric:           "Un problème est survenu lors de l'installation. Consultez le journal.",
            // Demo warning
            .demoWarningLabel:            "Installé — mais peut-être en mode Démo ou Essai. Vérifiez le produit.",
            // Progress steps
            .progressScanningFile:        "Analyse du fichier…",
            .progressOpeningInstaller:    "Ouverture de l'installeur…",
            .progressCopyingFiles:        "Copie des fichiers…",
            .progressRunningInstaller:    "Exécution de l'installeur…",
            .progressRunningScript:       "Exécution du script de configuration…",
            .progressApplyingLicense:     "Application des paramètres de licence…",
            .progressVerifying:           "Vérification de l'installation…",
            .progressCheckingLicense:     "Vérification du statut de licence…",
            .progressSavingProfile:       "Enregistrement du profil d'installation…",
            .progressCleaningUp:          "Nettoyage…",
            .progressDone:                "Terminé.",
            .notifyRestoreCompleteTitle:  "Restauration terminée",
            .notifyRestoreFailedTitle:    "Échec de la restauration",
            .notifyUninstallSuccessBody:  "%@ a été supprimé avec succès.",
            .vscanQuarantineNotifBody:    "%@ placé en quarantaine ATLAS.",
            .vscanDeletedNotifBody:       "%@ supprimé définitivement.",
            .quitInstallAlertTitle:       "Installation en cours",
            .quitInstallAlertBody:        "ATLAS effectue actuellement une installation. Quitter maintenant peut laisser des fichiers dans un état incomplet.\n\nÊtes-vous sûr de vouloir quitter ?",
            .quitAnyway:                  "Quitter quand même",
            .checkForUpdates:             "Rechercher des mises à jour",
            .menuOpenAtlas:               "Ouvrir ATLAS",
            .menuQuitAtlas:               "Quitter ATLAS",
            .fileShareNotifTitle:         "📦 Nouveau fichier partagé",
            .fileShareNotifBodyFmt:       "%@ (%@) est prêt à installer.",
            .notifyBatchUninstallTitle:   "Désinstallation de session terminée",
            .atlasLibrary:                "Bibliothèque ATLAS",
            .noInstallsYet:               "Aucune installation pour l'instant",
            .clearAll:                    "Tout effacer",
            .deleteAll:                   "Tout supprimer",
            .formatsLabel:                "Formats",
            .signingLabel:                "Signature…",
            .signedLabel:                 "Signé !",
            .permanentlyDeleted:          "Supprimé définitivement",
            .feedbackReceived:            "Retour ✓",
            .filesPresent:                "Fichiers présents",
            .inTrash:                     "Dans la corbeille",
            .filesGone:                   "Fichiers supprimés",
            .unArchive:                   "Désarchiver",
            .installedOnFmt:              "Installé le %@",
            .archivedOnFmt:               "Archivé le %@",
            .archiveLabelFmt:             "Archive (%d)",
            .sessionFmt:                  "Session · %d · %@",
            .filesTrackedFmt:             "%d fichier(s) suivi(s)",
            .receiptsAndFilesFmt:         "%d reçu(s) · %d fichiers",
            .uninstall:                   "Désinstaller",
            .remove:                      "Supprimer",
            .feedback:                    "Retour",
            .support:                     "Support",
            .sign:                        "Signer",
            .enable:                      "Activer",
            .disable:                     "Désactiver",
            .clearAtlasLibraryTitle:      "Vider la Bibliothèque ATLAS ?",
            .clearLibraryMsgFmt:          "Tous les %d enregistrements d'installation seront déplacés vers l'Archive. Les fichiers installés ne sont pas affectés. Vous pouvez désarchiver un enregistrement à tout moment.",
            .removeFromLibraryTitle:      "Retirer de la Bibliothèque ?",
            .removeRecordMsgFmt:          "'%@' sera déplacé vers l'Archive. Les fichiers installés ne sont pas affectés.",
            .uninstallConfirmTitle:       "Désinstaller ?",
            .uninstallConfirmMsgFmt:      "ATLAS déplacera %@ installé par %@ vers la corbeille.%@\n\nVous pouvez les récupérer depuis la corbeille ou en utilisant le bouton Récupérer.",
            .disabledFormatsNoteFmt:      "\n\nCela inclut également %d format(s) désactivé(s) dans le stockage ATLAS.",
            .recoverFilesTitle:           "Récupérer les fichiers ?",
            .recoverFilesMsgFmt:          "ATLAS déplacera les fichiers mis à la corbeille lors de la désinstallation de %@ vers leurs emplacements d'origine.",
            .recoveryNotAvailable:        "Récupération non disponible",
            .uninstallSessionTitle:       "Désinstaller la session ?",
            .uninstallSessionMsgFmt:      "ATLAS désinstallera %d élément(s) de cette session. Les fichiers seront déplacés vers la corbeille.",
            .deleteArchivesTitle:         "Supprimer les archives définitivement ?",
            .deleteArchivesMsg:           "Cela supprimera définitivement tout l'historique des programmes archivés de votre Bibliothèque ATLAS. Cette action est irréversible.\n\nVos journaux existants ne seront pas supprimés.",
            .deleteAllArchivesBtn:        "Tout supprimer des archives",
            .deleteArchiveTitle:          "Supprimer l'enregistrement d'archive ?",
            .deleteArchiveMsgFmt:         "Cela supprime définitivement '%@' de votre historique d'archive. Aucun fichier sur le disque n'est affecté.",
            .disableFmtConfirmTitleFmt:   "Désactiver %@ ?",
            .disableFmtConfirmMsgFmt:     "ATLAS déplacera %@ (%@) hors de son dossier de plugins. Il n'apparaîtra pas dans votre DAW tant qu'il ne sera pas réactivé.\n\nVous pouvez le réactiver à tout moment depuis la Bibliothèque ATLAS.",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .german: [
            // Existing
            .notifySuccessTitle:          "Installation abgeschlossen",
            .notifySuccessBody:           "%@ erfolgreich installiert.",
            .notifyFailedTitle:           "Installation fehlgeschlagen",
            .notifyQueueCompleteTitle:    "ATLAS — Warteschlange abgeschlossen",
            .notifyQueueCompleteBody:     "%d erfolgreich installiert",
            .notifyUninstallComplete:     "Deinstallation abgeschlossen",
            .notifyUninstallFailed:       "Deinstallation fehlgeschlagen",
            .notifyRestoreComplete:       "%@ wurde wiederhergestellt.",
            .notifyRestoreFailed:         "%@ konnte nicht wiederhergestellt werden.",
            .installMore:                 "Mehr installieren",
            .retrying:                    "Erneut versuchen…",
            .cancelConfirmTitle:          "Installation stoppen?",
            .cancelConfirmMessage:        "Die aktuelle Installation wird abgebrochen und teilweise Änderungen müssen möglicherweise rückgängig gemacht werden.",
            .cancelConfirmStop:           "Stoppen",
            .cancelConfirmContinue:       "Fortfahren",
            .titanMissionTitle:           "TITAN CORE™ — Missionsplan",
            .titanMissionSubtitle:        "ATLAS hat eine mehrstufige Installation erkannt. Plan prüfen und starten.",
            .titanBegin:                  "Installation starten",
            .titanCancel:                 "Abbrechen",
            .titanRunning:                "Läuft…",
            .titanComplete:               "Installation abgeschlossen",
            .titanStepPending:            "Ausstehend",
            .titanStepRunning:            "Läuft…",
            .titanStepDone:               "Fertig",
            .titanStepFailed:             "Fehlgeschlagen",
            .titanStepSkipped:            "Übersprungen",
            .titanStepXcodeTools:         "Xcode Command Line Tools installieren",
            .titanStepInstallPkg:         "Paket installieren",
            .titanStepRunScript:          "Skript ausführen",
            .titanStepRunBinary:          "Tool ausführen",
            .titanStepEditHosts:          "Lizenzserver blockieren",
            .titanStepRunCommand:         "Terminal-Befehl ausführen",
            .titanNoInstrTitle:           "Keine Installationsanleitung gefunden",
            .titanNoInstrBody:            "ATLAS fand Dateien, die auf eine komplexe Installation hinweisen, aber keine Anleitung.",
            .titanNoInstrProvide:         "Anleitung bereitstellen",
            .titanNoInstrAttempt:         "Ohne Anleitung versuchen",
            .titanNoInstrWarning:         "⚠ Diese Installation kann ohne Anleitung fehlschlagen.",
            .titanNoInstrHelp:            "Hilfe von InterLinked erhalten",
            .dropFilesHere:               "Dateien hierher ziehen",
            .releaseToAdd:                "Loslassen zum Hinzufügen",
            .chooseFile:                  "Datei oder Ordner wählen…",
            .settings:                    "Einstellungen",
            .language:                    "Sprache",
            .getHelp:                     "Hilfe holen",
            .signOut:                     "Abmelden",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "Fertig",
            .cancel:                      "Abbrechen",
            .retry:                       "Wiederholen",
            .close:                       "Schließen",
            // Queue
            .queueInstallQueue:           "Installationswarteschlange",
            .queueClearWaiting:           "Wartende löschen",
            .queueInstallAll:             "Alles installieren",
            .queueWaitingForSteps:        "Warte auf Schritte…",
            .queueStatusWaiting:          "Wartend",
            .queueStatusScanning:         "Scannen",
            .queueStatusInstalling:       "Installieren",
            .queueStatusInstalled:        "Installiert",
            .queueStatusDemoWarning:      "Demo-Warnung",
            .queueStatusActivation:       "Aktivierung",
            .queueStatusVerification:     "Überprüfung",
            // Tour
            .tourDontShowAgain:           "Nicht mehr anzeigen",
            .tourBack:                    "Zurück",
            .tourNext:                    "Weiter",
            .tourStepOfFmt:               "%d von %d",
            .tourStep0Title:              "Ablegen und installieren",
            .tourStep0Body:               "Ziehe beliebige Installationsdateien hierher — DMG, ZIP, PKG, VST3, AAX oder RAR. ATLAS analysiert die Datei, zeigt dir genau was gefunden wurde, und installiert mit einem Tippen. Dein System bleibt unberührt, bis du es bestätigst.",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "Alles, was ATLAS über dein System weiß, findest du hier. Installierte Produkte, Plugin-Formate, Speicher, Bereinigungswerkzeuge und Wiederherstellungsoptionen — alles an einem Ort.",
            .tourStep2Title:              "Deine installierten Produkte",
            .tourStep2Body:               "Jede Installation wird hier gespeichert. Tippe, um Produkte aufzuklappen und zu verwalten — aktiviere oder deaktiviere einzelne Plugin-Formate (AU, VST3, VST, AAX) und signiere sie direkt aus deiner Library.",
            .tourStep3Title:              "Deinstallieren und Wiederherstellen",
            .tourStep3Body:               "Tippe auf ein Produkt, um es aufzuklappen. Pro-Nutzer können mit einem Tippen deinstallieren — ATLAS verschiebt Dateien in den Papierkorb und speichert einen Rollback-Snapshot zur späteren Wiederherstellung.",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "Finde übrig gebliebene Installationsdateien, verwaiste Komponenten und wiederherstellbare temporäre Caches. ATLAS zeigt dir genau, was es gefunden hat, bevor etwas entfernt wird.",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "Exportiere einen verschlüsselten Snapshot deiner gesamten Library — jedes Produkt, Format und Pfad. Bewahre ihn sicher auf und baue dein komplettes Setup auf jedem Mac neu auf. Cloud-Backup verfügbar im Pro-Plan.",
            .tourStep6Title:              "Einstellungen",
            .tourStep6Body:               "Verwalte Konto, Abonnement, Geräte und Sprache. Wechsle zwischen Heller, Dunkler oder Systemdarstellung. Starte diese Tour jederzeit neu über Einstellungen.",
            .tourStep7Title:              "Du bist bereit",
            .tourStep7Body:               "Lege deinen ersten Installer ab, um loszulegen. Deine Library, Bereinigungswerkzeuge und Wiederherstellungsoptionen sind immer einen Tippen entfernt.",
            .tourStep8Title:              "Du bist bereit",
            .tourStep8Body:               "Lege deinen ersten Installer ab, um loszulegen. Deine Library, Bereinigungswerkzeuge und Wiederherstellungsoptionen sind immer einen Tippen entfernt.",
            // Demo Alert
            .demoModeDetected:            "DEMO-MODUS ERKANNT",
            .demoSignalsFound:            "SIGNALE GEFUNDEN",
            .demoWhatThisMeans:           "WAS DAS BEDEUTET",
            .demoTip1:                    "Öffne das Plugin in deiner DAW und suche nach einem Wasserzeichen, Banner oder Aktivierungshinweis.",
            .demoTip2:                    "Falls der Demo-Modus erscheint, musst du möglicherweise deine Lizenz aktivieren oder erneut eingeben.",
            .demoTip3:                    "Kontaktiere den Hersteller, wenn deine Lizenz gültig ist, das Plugin aber weiterhin den Demo-Modus anzeigt.",
            // Recovery Mode
            .filterAll:                   "Alle",
            .filterReady:                 "Bereit",
            .filterInstalling:            "Installieren",
            .filterInstalled:             "Installiert",
            .filterFailed:                "Fehlgeschlagen",
            .filterPending:               "Ausstehend",
            .installReadyProducts:        "BEREITE PRODUKTE INSTALLIEREN",
            .dropInstallersAbove:         "Installationsdateien oben ablegen",
            .recoveryComplete:            "Wiederherstellung abgeschlossen",
            .viewInLibrary:               "In Bibliothek anzeigen",
            .exitRecoveryMode:            "Wiederherstellungsmodus beenden",
            .statDone:                    "Fertig",
            .statSkipped:                 "Übersprungen",
            .statLimit:                   "Limit",
            .statReinstalled:             "Neu installiert",
            .statPending:                 "Ausstehend",
            // Recovery Slot
            .stateLimitReached:           "Limit erreicht",
            .dropInstallerHere:           "Installationsdatei hier ablegen",
            .orLabel:                     "oder",
            .installAction:               "Installieren",
            // Subscription
            .backToSignIn:                "Zurück zur Anmeldung",
            .reJoinAtlas:                 "ATLAS erneut beitreten",
            .paymentFailed:               "Zahlung fehlgeschlagen",
            .subscriptionRequired:        "Abonnement erforderlich",
            .checkingEllipsis:            "Prüfen…",
            .iveSubscribed:               "Ich habe abonniert — Aktualisieren",
            .subscribeNow:                "Jetzt abonnieren",
            .updateBilling:               "Zahlungsdaten aktualisieren",
            .subBodyReJoin:               "Dein Abonnement ist abgelaufen. Tritt ATLAS wieder bei, um weiter zu installieren.",
            .subBodyPayment:              "Deine letzte Zahlung ist fehlgeschlagen. Aktualisiere deine Zahlungsdaten, um fortzufahren.",
            .subBodyNew:                  "Abonniere ATLAS, um Plugins in Sekunden zu installieren.",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "PASSWORT ERFORDERLICH",
            .filePasswordProtected:       "Diese Datei ist passwortgeschützt",
            .archivePassword:             "ARCHIV-PASSWORT",
            .enterPassword:               "Passwort eingeben",
            .rememberPassword:            "ATLAS merkt sich dieses Passwort für zukünftige Installationen dieses Produkts.",
            .unlockAndInstall:            "Entsperren und installieren",
            // Rosetta
            .appleSiliconDetected:        "Apple Silicon erkannt",
            .enableRosettaQ:              "Rosetta für deine DAWs aktivieren, um Intel-Plugins zu laden?",
            .scanningDAWs:                "Suche nach installierten DAWs...",
            .noDAWsFound:                 "Keine DAWs auf diesem Mac gefunden.",
            .selectDAWsRosetta:           "DAWs für Rosetta auswählen:",
            .rosettaEnabledMsg:           "Rosetta für ausgewählte DAWs aktiviert. Starte deine DAW neu, um Intel-Plugins zu laden.",
            .noThanks:                    "Nein danke",
            .applying:                    "Anwenden...",
            .enableRosettaAction:         "Rosetta aktivieren",
            .alreadyEnabled:              "Bereits aktiviert",
            // Storage/Library
            .available:                   "Verfügbar",
            .total:                       "Gesamt",
            .nothingToClean:              "Nichts zu bereinigen",
            .scanUnavailable:             "Scan nicht verfügbar",
            .quickScan:                   "Schnell-Scan",
            .overview:                    "ÜBERSICHT",
            .disabled:                    "Deaktiviert",
            .archived:                    "Archiviert",
            .review:                      "Überprüfen",
            // Log View
            .fullLog:                     "Vollständiges Protokoll",
            .logSummary:                  "Zusammenfassung",
            .less:                        "Weniger",
            .logDetails:                  "Details",
            .copied:                      "Kopiert!",
            .copyLabel:                   "Kopieren",
            // Recovery Kit
            .portableSnapshot:            "Portabler Installations-Snapshot",
            .generating:                  "Erstellen…",
            .exportFailed:                "Export fehlgeschlagen",
            .generate:                    "Erstellen",
            .cloudBackupLabel:            "Cloud-Backup",
            .checking:                    "Prüfen…",
            .notBackedUp:                 "Kein Backup",
            .syncing:                     "Synchronisieren…",
            .restoring:                   "Wiederherstellen…",
            .loadRecoveryKit:             "Recovery Kit laden",
            .openKitFile:                 "Eine .atlaskit-Datei öffnen",
            .loading:                     "Laden…",
            .kitLoaded:                   "Kit geladen — bereit für den Wiederherstellungsmodus",
            .fileRejected:                "Datei abgelehnt — manipuliert oder beschädigt",
            .couldNotLoad:                "Datei konnte nicht geladen werden",
            .replace:                     "Ersetzen",
            .open:                        "Öffnen",
            .crossMacKitNote:             "Von einem anderen Mac exportiert — alle Dateipfade dienen nur als Referenz.",
            .hashMismatchNote:            "Diese Recovery Kit-Datei wurde verändert oder beschädigt und kann nicht geladen werden.",
            .beginRecovery:               "ATLAS RECOVERY STARTEN",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "Produkte",
            .update:                      "Aktualisieren",
            .backUp:                      "Sichern",
            .retryCloudBackup:            "Cloud-Backup wiederholen",
            // TITAN VSCAN
            .detectedThreats:             "ERKANNTE BEDROHUNGEN",
            .showLess:                    "Weniger anzeigen",
            .showAllFmt:                  "Alle anzeigen (%d)",
            .foundIn:                     "Gefunden in",
            .continueInstall:             "Installation fortsetzen",
            .proceedWithInstall:          "Mit Installation fortfahren",
            .proceedAnyway:               "Trotzdem fortfahren",
            .moveToQuarantine:            "In Quarantäne verschieben",
            .deletePermanently:           "Dauerhaft löschen",
            .stripMalwareInstall:         "Malware entfernen und sauber installieren",
            .vscanLicenseTip:             "Dies ist ein Lizenz-Tool (Keygen/Patch). TITAN VSCAN™ hat keine weitere Malware erkannt. Fahre nach eigenem Ermessen fort.",
            .vscanSuspiciousTip:          "Ungewöhnliche Muster erkannt. Dies könnten Falschmeldungen legitimer Software sein. Überprüfe die Bedrohungen oben, bevor du fortfährst.",
            .vscanMalwareTip:             "TITAN VSCAN™ hat diese Installation blockiert. Die Datei enthält Malware und kann nicht sicher installiert werden. Verschiebe sie in Quarantäne oder lösche sie dauerhaft.",
            .vscanQuarantineConfirmMsg:   "Die Datei wird in einem sicheren ATLAS-Quarantäneordner isoliert. Du kannst sie später in ATLAS-Einstellungen überprüfen oder dauerhaft löschen.",
            .vscanDeleteConfirmMsg:       "Dadurch wird die Datei dauerhaft von deinem Mac entfernt. Dies kann nicht rückgängig gemacht werden.",
            // Install Overlay
            .stillWorkingFmt:             "Noch in Bearbeitung… %d s vergangen",
            // Scan Result
            .keygenDetected:              "Keygen / Aktivierungs-Tool erkannt",
            .windowsExe:                  "Windows-Programm",
            .keygenWarning:               "⚠ Warnung: Keygen-Datei erkannt",
            .readyDropInstaller:          "Bereit — lege deinen Mac-Installer in ATLAS, um fortzufahren",
            .dropNewFile:                 "Neue Datei ablegen",
            .imDoneReady:                 "Fertig — Bereit fortzufahren",
            .confirmationRequired:        "Bestätigung erforderlich",
            .contentsFound:               "Inhalt gefunden",
            .alreadyInstalled:            "Bereits installiert",
            .insufficientSpace:           "Unzureichender Speicherplatz",
            .cannotInstallAuto:           "Automatische Installation nicht möglich",
            .share:                       "Teilen",
            .installAction2:              "Installieren",
            // Summary Card
            .userActionRequired:          "BENUTZERAKTION ERFORDERLICH",
            .installerMovedToTrash:       "Installer in den Papierkorb verschoben",
            .moveInstallerToTrash:        "Installer in den Papierkorb verschieben",
            .backToHome:                  "Zurück zur Startseite",
            .removed:                     "ENTFERNT",
            .supportFiles:                "HILFSDATEIEN",
            .couldNotRemove:              "KONNTE NICHT ENTFERNT WERDEN",
            .filesMovedToTrash:           "Dateien in den Papierkorb verschoben — Papierkorb im Finder leeren, um Speicher freizugeben.",
            .recover:                     "Wiederherstellen",
            // Settings
            .appearance:                  "Erscheinungsbild",
            .account:                     "Konto",
            .supportLabel:                "Support",
            .tourAtlasTitle:              "Tour ATLAS",
            .replayWalkthrough:           "ATLAS-Einführung erneut abspielen",
            .tools:                       "Werkzeuge",
            .fixBlockedPlugins:           "Blockierte Plugins reparieren",
            .removeSecurityBlocks:        "macOS-Sicherheitssperren von installierten Plugins entfernen",
            .fix:                         "Reparieren",
            .installLimits:               "Installationslimits",
            .dailyInstallations:          "Tägliche Installationen",
            .monthlyInstallations:        "Monatliche Installationen",
            .resetsAtMidnight:            "Wird um Mitternacht zurückgesetzt",
            .refillsOnBillingDate:        "Wird am Abrechnungsdatum aufgefüllt",
            .remainingTodayFmt:           "%d verbleibend heute",
            .remainingThisMonthFmt:       "%d verbleibend diesen Monat",
            .notificationsLabel:          "Benachrichtigungen",
            .installAlerts:               "Installations- und Deinstallationsbenachrichtigungen",
            .notifOn:                     "Ein — du wirst benachrichtigt, wenn Vorgänge abgeschlossen sind",
            .notifOff:                    "Aus",
            .vscanSettingTitle:           "Integrierter Virenscanner",
            .vscanSettingSubtitle:        "Installationsdateien vor der Installation auf Bedrohungen prüfen",
            .enableInSystemSettings:      "In Systemeinstellungen → Mitteilungen aktivieren",
            .storageLabel:                "Speicher",
            .noVolumesFound:              "Keine Volumes gefunden",
            .about:                       "Über",
            .viewLogs:                    "Protokolle anzeigen",
            .openLogFolder:               "Installations- und Deinstallations-Protokollordner öffnen",
            .signOutConfirmMsg:           "Du musst dich erneut anmelden, um ATLAS zu verwenden.",
            .signOutTitle:                "Von ATLAS abmelden?",
            // Support
            .getSupport:                  "SUPPORT ERHALTEN",
            .replyWithin24:               "Wir antworten innerhalb von 24 Stunden",
            .product:                     "PRODUKT",
            .issueType:                   "PROBLEMTYP",
            .describeIssue:               "BESCHREIBE DEIN PROBLEM",
            .attachLog:                   "PROTOKOLL ANHÄNGEN (OPTIONAL)",
            .sendRequest:                 "Support-Anfrage senden",
            .sending:                     "Senden…",
            .thankYou:                    "Danke!",
            .requestReceived:             "Deine Support-Anfrage wurde erhalten.",
            .supportTeamReplyFmt:         "Unser Support-Team wird sich in Kürze bei dir melden.\nWir antworten auf %@ innerhalb von 24 Stunden.",
            .backToAtlas:                 "Zurück zu ATLAS",
            // Cleaner
            .quickClean:                  "Schnellbereinigung",
            .scanSystemForClutter:        "System nach unnötiger Audio-Software durchsuchen",
            .itemsMovedToTrashNote:       "Elemente werden in den macOS-Papierkorb verschoben — nichts wird dauerhaft gelöscht.",
            .startScan:                   "Scan starten",
            .scanning:                    "Scannen",
            .selectAll:                   "Alle auswählen",
            .deselectAll:                 "Alle abwählen",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "Keine zu bereinigenden Elemente gefunden",
            .systemIsClean:               "Dein System ist sauber",
            .noCleanerHistory:            "Noch kein Bereinigungsverlauf",
            .cleanerHistory:              "Bereinigungsverlauf",
            .movingToTrash:               "In den Papierkorb verschieben…",
            // Failure reasons
            .failReasonIncomplete:        "Installation unvollständig — Dateien wurden möglicherweise nicht korrekt kopiert.",
            .failReasonFilesNotLanded:    "Einige Dateien sind nicht am richtigen Ort gelandet. Versuche die Neuinstallation.",
            .failReasonAppNoLaunch:       "Die App konnte nach der Installation nicht starten. Sie muss möglicherweise manuell geöffnet werden.",
            .failReasonAUNotRecognized:   "Das Audio-Plugin wurde installiert, wird von deiner DAW möglicherweise noch nicht erkannt. Versuche, Plugins neu zu scannen.",
            .failReasonDamaged:           "Die Plugin-Datei scheint beschädigt zu sein. Versuche, das Original erneut herunterzuladen.",
            .failReasonVerifyFailed:      "ATLAS konnte nicht bestätigen, dass die Installation erfolgreich abgeschlossen wurde. Überprüfe das Protokoll.",
            .failReasonConfidenceLow:     "ATLAS war nicht sicher, dass diese Datei sicher zu installieren ist. Versuche eine andere Version oder Quelle.",
            .failReasonScriptError:       "Ein Installations-Skript ist auf einen Fehler gestoßen. Überprüfe das Protokoll für die vollständige Ausgabe.",
            .failReasonPkgFailed:         "Der Paketinstaller wurde nicht abgeschlossen. Du musst ihn möglicherweise manuell ausführen.",
            .failReasonCancelled:         "Installation abgebrochen.",
            .failReasonWaves:             "Dieses Waves-Produkt erfordert einen manuellen Installationsschritt. Siehe Protokoll.",
            .failReasonGeneric:           "Während der Installation ist etwas schief gelaufen. Siehe Installationsprotokoll.",
            // Demo warning
            .demoWarningLabel:            "Installiert — läuft aber möglicherweise im Demo- oder Testmodus. Produkt überprüfen.",
            // Progress steps
            .progressScanningFile:        "Datei wird gescannt…",
            .progressOpeningInstaller:    "Installer wird geöffnet…",
            .progressCopyingFiles:        "Dateien werden kopiert…",
            .progressRunningInstaller:    "Installer wird ausgeführt…",
            .progressRunningScript:       "Setup-Skript wird ausgeführt…",
            .progressApplyingLicense:     "Lizenzeinstellungen werden angewendet…",
            .progressVerifying:           "Installation wird überprüft…",
            .progressCheckingLicense:     "Lizenzstatus wird geprüft…",
            .progressSavingProfile:       "Installationsprofil wird gespeichert…",
            .progressCleaningUp:          "Aufräumen…",
            .progressDone:                "Fertig.",
            .notifyRestoreCompleteTitle:  "Wiederherstellung abgeschlossen",
            .notifyRestoreFailedTitle:    "Wiederherstellung fehlgeschlagen",
            .notifyUninstallSuccessBody:  "%@ wurde erfolgreich entfernt.",
            .vscanQuarantineNotifBody:    "%@ in ATLAS-Quarantäne verschoben.",
            .vscanDeletedNotifBody:       "%@ dauerhaft gelöscht.",
            .quitInstallAlertTitle:       "Installation läuft",
            .quitInstallAlertBody:        "ATLAS führt gerade eine Installation durch. Beenden jetzt kann Dateien in einem unvollständigen Zustand hinterlassen.\n\nWirklich beenden?",
            .quitAnyway:                  "Trotzdem beenden",
            .checkForUpdates:             "Nach Updates suchen",
            .menuOpenAtlas:               "ATLAS öffnen",
            .menuQuitAtlas:               "ATLAS beenden",
            .fileShareNotifTitle:         "📦 Neue Datei geteilt",
            .fileShareNotifBodyFmt:       "%@ (%@) ist bereit zur Installation.",
            .notifyBatchUninstallTitle:   "Sitzungsdeinstallation abgeschlossen",
            .atlasLibrary:                "ATLAS Bibliothek",
            .noInstallsYet:               "Noch keine Installationen",
            .clearAll:                    "Alle löschen",
            .deleteAll:                   "Alle entfernen",
            .formatsLabel:                "Formate",
            .signingLabel:                "Signierung…",
            .signedLabel:                 "Signiert!",
            .permanentlyDeleted:          "Dauerhaft gelöscht",
            .feedbackReceived:            "Feedback ✓",
            .filesPresent:                "Dateien vorhanden",
            .inTrash:                     "Im Papierkorb",
            .filesGone:                   "Dateien weg",
            .unArchive:                   "Aus Archiv",
            .installedOnFmt:              "Installiert am %@",
            .archivedOnFmt:               "Archiviert am %@",
            .archiveLabelFmt:             "Archiv (%d)",
            .sessionFmt:                  "Sitzung · %d · %@",
            .filesTrackedFmt:             "%d Datei(en) verfolgt",
            .receiptsAndFilesFmt:         "%d Quittung(en) · %d Dateien",
            .uninstall:                   "Deinstallieren",
            .remove:                      "Entfernen",
            .feedback:                    "Feedback",
            .support:                     "Support",
            .sign:                        "Signieren",
            .enable:                      "Aktivieren",
            .disable:                     "Deaktivieren",
            .clearAtlasLibraryTitle:      "ATLAS Bibliothek leeren?",
            .clearLibraryMsgFmt:          "Alle %d Installationseinträge werden ins Archiv verschoben. Installierte Dateien sind nicht betroffen. Einträge können jederzeit wiederhergestellt werden.",
            .removeFromLibraryTitle:      "Aus Bibliothek entfernen?",
            .removeRecordMsgFmt:          "'%@' wird ins Archiv verschoben. Installierte Dateien sind nicht betroffen.",
            .uninstallConfirmTitle:       "Deinstallieren?",
            .uninstallConfirmMsgFmt:      "ATLAS verschiebt %@ installiert von %@ in den Papierkorb.%@\n\nSie können sie aus dem Papierkorb oder über die Wiederherstellen-Schaltfläche zurückholen.",
            .disabledFormatsNoteFmt:      "\n\nDies umfasst auch %d deaktiviertes Format(e) im ATLAS-Speicher.",
            .recoverFilesTitle:           "Dateien wiederherstellen?",
            .recoverFilesMsgFmt:          "ATLAS verschiebt die Dateien, die beim Deinstallieren von %@ in den Papierkorb wanderten, zurück an ihren ursprünglichen Ort.",
            .recoveryNotAvailable:        "Wiederherstellung nicht verfügbar",
            .uninstallSessionTitle:       "Sitzung deinstallieren?",
            .uninstallSessionMsgFmt:      "ATLAS deinstalliert %d Element(e) aus dieser Sitzung. Dateien werden in den Papierkorb verschoben.",
            .deleteArchivesTitle:         "Archive dauerhaft löschen?",
            .deleteArchivesMsg:           "Dadurch werden alle archivierten Programmverlaufsdaten aus Ihrer ATLAS-Bibliothek dauerhaft gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.\n\nIhre Protokolle werden nicht gelöscht.",
            .deleteAllArchivesBtn:        "Alle Archive löschen",
            .deleteArchiveTitle:          "Archiveintrag löschen?",
            .deleteArchiveMsgFmt:         "Dies entfernt '%@' dauerhaft aus Ihrem Archivverlauf. Keine Dateien auf der Festplatte sind betroffen.",
            .disableFmtConfirmTitleFmt:   "%@ deaktivieren?",
            .disableFmtConfirmMsgFmt:     "ATLAS verschiebt %@ (%@) aus seinem Plugin-Ordner. Es erscheint nicht in Ihrer DAW, bis es wieder aktiviert wird.\n\nSie können es jederzeit aus der ATLAS Bibliothek aktivieren.",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .portuguese: [
            // Existing
            .notifySuccessTitle:          "Instalação concluída",
            .notifySuccessBody:           "%@ instalado com sucesso.",
            .notifyFailedTitle:           "Falha na instalação",
            .notifyQueueCompleteTitle:    "ATLAS — Fila concluída",
            .notifyQueueCompleteBody:     "%d instalado(s) com sucesso",
            .notifyUninstallComplete:     "Desinstalação concluída",
            .notifyUninstallFailed:       "Falha na desinstalação",
            .notifyRestoreComplete:       "%@ foi restaurado.",
            .notifyRestoreFailed:         "%@ não pôde ser restaurado.",
            .installMore:                 "Instalar mais",
            .retrying:                    "Tentando novamente…",
            .cancelConfirmTitle:          "Parar instalação?",
            .cancelConfirmMessage:        "A instalação atual será cancelada e as alterações parciais podem precisar ser desfeitas.",
            .cancelConfirmStop:           "Parar",
            .cancelConfirmContinue:       "Continuar",
            .titanMissionTitle:           "TITAN CORE™ — Plano de Missão",
            .titanMissionSubtitle:        "ATLAS detectou uma instalação em várias etapas. Revise o plano e comece.",
            .titanBegin:                  "Iniciar Instalação",
            .titanCancel:                 "Cancelar",
            .titanRunning:                "Executando…",
            .titanComplete:               "Instalação concluída",
            .titanStepPending:            "Pendente",
            .titanStepRunning:            "Executando…",
            .titanStepDone:               "Concluído",
            .titanStepFailed:             "Falhou",
            .titanStepSkipped:            "Ignorado",
            .titanStepXcodeTools:         "Instalar Xcode Command Line Tools",
            .titanStepInstallPkg:         "Instalar pacote",
            .titanStepRunScript:          "Executar script",
            .titanStepRunBinary:          "Executar ferramenta",
            .titanStepEditHosts:          "Bloquear servidor de licença",
            .titanStepRunCommand:         "Executar comando",
            .titanNoInstrTitle:           "Nenhum guia de instalação encontrado",
            .titanNoInstrBody:            "ATLAS encontrou arquivos que sugerem uma instalação complexa, mas sem guia.",
            .titanNoInstrProvide:         "Fornecer instruções",
            .titanNoInstrAttempt:         "Tentar sem guia",
            .titanNoInstrWarning:         "⚠ Esta instalação pode falhar sem um guia.",
            .titanNoInstrHelp:            "Obter ajuda da InterLinked",
            .dropFilesHere:               "Solte os arquivos aqui",
            .releaseToAdd:                "Solte para adicionar",
            .chooseFile:                  "Escolher arquivo ou pasta…",
            .settings:                    "Configurações",
            .language:                    "Idioma",
            .getHelp:                     "Obter ajuda",
            .signOut:                     "Sair",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "Concluído",
            .cancel:                      "Cancelar",
            .retry:                       "Tentar novamente",
            .close:                       "Fechar",
            // Queue
            .queueInstallQueue:           "Fila de instalação",
            .queueClearWaiting:           "Limpar aguardando",
            .queueInstallAll:             "Instalar tudo",
            .queueWaitingForSteps:        "Aguardando etapas…",
            .queueStatusWaiting:          "Aguardando",
            .queueStatusScanning:         "Verificando",
            .queueStatusInstalling:       "Instalando",
            .queueStatusInstalled:        "Instalado",
            .queueStatusDemoWarning:      "Aviso de demo",
            .queueStatusActivation:       "Ativação",
            .queueStatusVerification:     "Verificação",
            // Tour
            .tourDontShowAgain:           "Não mostrar novamente",
            .tourBack:                    "Voltar",
            .tourNext:                    "Próximo",
            .tourStepOfFmt:               "%d de %d",
            .tourStep0Title:              "Soltar e instalar",
            .tourStep0Body:               "Arraste qualquer instalador aqui — DMG, ZIP, PKG, VST3, AAX ou RAR. O ATLAS analisa, mostra exatamente o que encontrou e instala com um toque. Nada toca seu sistema até você confirmar.",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "Tudo o que o ATLAS sabe sobre seu setup está aqui. Produtos instalados, formatos de plugins, armazenamento, ferramentas de limpeza e opções de recuperação — tudo em um lugar.",
            .tourStep2Title:              "Seus produtos instalados",
            .tourStep2Body:               "Cada instalação é registrada aqui. Toque para expandir e gerenciar seus produtos — ative ou desative formatos individuais (AU, VST3, VST, AAX) e assine-os diretamente da sua Library.",
            .tourStep3Title:              "Desinstalar e recuperar",
            .tourStep3Body:               "Toque em qualquer produto para expandi-lo. Usuários Pro podem desinstalar com um toque — o ATLAS move os arquivos para a Lixeira e salva um snapshot de reversão para recuperá-los a qualquer momento.",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "Encontre arquivos residuais de instalações, componentes órfãos e caches temporários recuperáveis. O ATLAS mostra exatamente o que encontrou antes de remover qualquer coisa.",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "Exporte um snapshot criptografado de toda sua library — cada produto, formato e caminho. Guarde com segurança e reconstrua seu setup completo em qualquer Mac. Backup em nuvem disponível no Pro.",
            .tourStep6Title:              "Configurações",
            .tourStep6Body:               "Gerencie conta, assinatura, dispositivos e idioma. Alterne entre aparência Clara, Escura ou do Sistema. Repita este tour a qualquer momento em Configurações.",
            .tourStep7Title:              "Você está pronto",
            .tourStep7Body:               "Solte seu primeiro instalador para começar. Sua Library, ferramentas de limpeza e opções de recuperação estão sempre a um toque.",
            .tourStep8Title:              "Você está pronto",
            .tourStep8Body:               "Solte seu primeiro instalador para começar. Sua Library, ferramentas de limpeza e opções de recuperação estão sempre a um toque.",
            // Demo Alert
            .demoModeDetected:            "MODO DEMO DETECTADO",
            .demoSignalsFound:            "SINAIS ENCONTRADOS",
            .demoWhatThisMeans:           "O QUE ISSO SIGNIFICA",
            .demoTip1:                    "Abra o plugin na sua DAW e procure uma marca d'água, banner ou prompt de ativação.",
            .demoTip2:                    "Se o modo demo aparecer, talvez seja necessário ativar ou reinserir sua licença.",
            .demoTip3:                    "Entre em contato com o fornecedor se acreditar que sua licença é válida, mas o plugin ainda mostra o modo demo.",
            // Recovery Mode
            .filterAll:                   "Todos",
            .filterReady:                 "Pronto",
            .filterInstalling:            "Instalando",
            .filterInstalled:             "Instalado",
            .filterFailed:                "Falhou",
            .filterPending:               "Pendente",
            .installReadyProducts:        "INSTALAR PRODUTOS PRONTOS",
            .dropInstallersAbove:         "Solte os instaladores acima para começar",
            .recoveryComplete:            "Recuperação concluída",
            .viewInLibrary:               "Ver na biblioteca",
            .exitRecoveryMode:            "Sair do modo de recuperação",
            .statDone:                    "Concluído",
            .statSkipped:                 "Ignorado",
            .statLimit:                   "Limite",
            .statReinstalled:             "Reinstalado",
            .statPending:                 "Pendente",
            // Recovery Slot
            .stateLimitReached:           "Limite atingido",
            .dropInstallerHere:           "Solte o instalador aqui",
            .orLabel:                     "ou",
            .installAction:               "Instalar",
            // Subscription
            .backToSignIn:                "Voltar ao login",
            .reJoinAtlas:                 "Voltar ao ATLAS",
            .paymentFailed:               "Pagamento falhou",
            .subscriptionRequired:        "Assinatura necessária",
            .checkingEllipsis:            "Verificando…",
            .iveSubscribed:               "Já assinei — Atualizar",
            .subscribeNow:                "Assinar agora",
            .updateBilling:               "Atualizar cobrança",
            .subBodyReJoin:               "Sua assinatura expirou. Volte ao ATLAS para continuar instalando.",
            .subBodyPayment:              "Seu último pagamento falhou. Atualize seus dados de cobrança para continuar.",
            .subBodyNew:                  "Assine o ATLAS para começar a instalar plugins em segundos.",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "SENHA NECESSÁRIA",
            .filePasswordProtected:       "Este arquivo está protegido por senha",
            .archivePassword:             "SENHA DO ARQUIVO",
            .enterPassword:               "Digite a senha",
            .rememberPassword:            "O ATLAS lembrará esta senha para futuras instalações deste produto.",
            .unlockAndInstall:            "Desbloquear e instalar",
            // Rosetta
            .appleSiliconDetected:        "Apple Silicon detectado",
            .enableRosettaQ:              "Ativar Rosetta nas suas DAWs para carregar plugins Intel?",
            .scanningDAWs:                "Procurando DAWs instaladas...",
            .noDAWsFound:                 "Nenhuma DAW encontrada neste Mac.",
            .selectDAWsRosetta:           "Selecione as DAWs para ativar o Rosetta:",
            .rosettaEnabledMsg:           "Rosetta ativado para as DAWs selecionadas. Reinicie sua DAW para carregar plugins Intel.",
            .noThanks:                    "Não, obrigado",
            .applying:                    "Aplicando...",
            .enableRosettaAction:         "Ativar Rosetta",
            .alreadyEnabled:              "Já ativado",
            // Storage/Library
            .available:                   "Disponível",
            .total:                       "Total",
            .nothingToClean:              "Nada para limpar",
            .scanUnavailable:             "Verificação indisponível",
            .quickScan:                   "Verificação rápida",
            .overview:                    "VISÃO GERAL",
            .disabled:                    "Desativado",
            .archived:                    "Arquivado",
            .review:                      "Revisar",
            // Log View
            .fullLog:                     "Log completo",
            .logSummary:                  "Resumo",
            .less:                        "Menos",
            .logDetails:                  "Detalhes",
            .copied:                      "Copiado!",
            .copyLabel:                   "Copiar",
            // Recovery Kit
            .portableSnapshot:            "Snapshot de instalação portátil",
            .generating:                  "Gerando…",
            .exportFailed:                "Falha ao exportar",
            .generate:                    "Gerar",
            .cloudBackupLabel:            "Backup na nuvem",
            .checking:                    "Verificando…",
            .notBackedUp:                 "Sem backup",
            .syncing:                     "Sincronizando…",
            .restoring:                   "Restaurando…",
            .loadRecoveryKit:             "Carregar Recovery Kit",
            .openKitFile:                 "Abrir um arquivo .atlaskit",
            .loading:                     "Carregando…",
            .kitLoaded:                   "Kit carregado — pronto para entrar no modo de recuperação",
            .fileRejected:                "Arquivo rejeitado — adulterado ou corrompido",
            .couldNotLoad:                "Não foi possível carregar o arquivo",
            .replace:                     "Substituir",
            .open:                        "Abrir",
            .crossMacKitNote:             "Exportado de outro Mac — todos os caminhos de arquivo são exibidos apenas como referência.",
            .hashMismatchNote:            "Este arquivo Recovery Kit foi modificado ou corrompido e não pode ser carregado.",
            .beginRecovery:               "INICIAR ATLAS RECOVERY",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "Produtos",
            .update:                      "Atualizar",
            .backUp:                      "Fazer backup",
            .retryCloudBackup:            "Tentar backup na nuvem novamente",
            // TITAN VSCAN
            .detectedThreats:             "AMEAÇAS DETECTADAS",
            .showLess:                    "Mostrar menos",
            .showAllFmt:                  "Mostrar todos (%d)",
            .foundIn:                     "Encontrado em",
            .continueInstall:             "Continuar instalação",
            .proceedWithInstall:          "Prosseguir com a instalação",
            .proceedAnyway:               "Prosseguir mesmo assim",
            .moveToQuarantine:            "Mover para quarentena",
            .deletePermanently:           "Excluir permanentemente",
            .stripMalwareInstall:         "Remover malware e instalar limpo",
            .vscanLicenseTip:             "Esta é uma ferramenta de licença (keygen/patch). O TITAN VSCAN™ não detectou malware adicional. Prossiga por sua conta e risco.",
            .vscanSuspiciousTip:          "Padrões incomuns detectados. Podem ser falsos positivos de software legítimo. Revise as ameaças acima antes de continuar.",
            .vscanMalwareTip:             "O TITAN VSCAN™ bloqueou esta instalação. O arquivo contém malware e não pode ser instalado com segurança. Mova-o para quarentena ou exclua permanentemente.",
            .vscanQuarantineConfirmMsg:   "O arquivo será isolado em uma pasta de quarentena segura do ATLAS. Você pode revisá-lo ou excluí-lo permanentemente nas Configurações do ATLAS.",
            .vscanDeleteConfirmMsg:       "Isso removerá permanentemente o arquivo do seu Mac. Esta ação não pode ser desfeita.",
            // Install Overlay
            .stillWorkingFmt:             "Ainda trabalhando… %d s decorridos",
            // Scan Result
            .keygenDetected:              "Keygen / Ferramenta de ativação detectada",
            .windowsExe:                  "Executável do Windows",
            .keygenWarning:               "⚠ Aviso: arquivo keygen detectado",
            .readyDropInstaller:          "Pronto — solte seu instalador Mac no ATLAS para continuar",
            .dropNewFile:                 "Soltar novo arquivo",
            .imDoneReady:                 "Terminei — Pronto para continuar",
            .confirmationRequired:        "Confirmação necessária",
            .contentsFound:               "Conteúdo encontrado",
            .alreadyInstalled:            "Já instalado",
            .insufficientSpace:           "Espaço insuficiente",
            .cannotInstallAuto:           "Não é possível instalar automaticamente",
            .share:                       "Compartilhar",
            .installAction2:              "Instalar",
            // Summary Card
            .userActionRequired:          "AÇÃO DO USUÁRIO NECESSÁRIA",
            .installerMovedToTrash:       "Instalador movido para a Lixeira",
            .moveInstallerToTrash:        "Mover instalador para a Lixeira",
            .backToHome:                  "Voltar ao início",
            .removed:                     "REMOVIDO",
            .supportFiles:                "ARQUIVOS DE SUPORTE",
            .couldNotRemove:              "NÃO FOI POSSÍVEL REMOVER",
            .filesMovedToTrash:           "Arquivos movidos para a Lixeira — esvazie a Lixeira no Finder para liberar espaço.",
            .recover:                     "Recuperar",
            // Settings
            .appearance:                  "Aparência",
            .account:                     "Conta",
            .supportLabel:                "Suporte",
            .tourAtlasTitle:              "Tour ATLAS",
            .replayWalkthrough:           "Repetir o tutorial do ATLAS",
            .tools:                       "Ferramentas",
            .fixBlockedPlugins:           "Corrigir plugins bloqueados",
            .removeSecurityBlocks:        "Remover bloqueios de segurança do macOS em plugins instalados",
            .fix:                         "Corrigir",
            .installLimits:               "Limites de instalação",
            .dailyInstallations:          "Instalações diárias",
            .monthlyInstallations:        "Instalações mensais",
            .resetsAtMidnight:            "Reinicia à meia-noite",
            .refillsOnBillingDate:        "Reabastece na data de cobrança",
            .remainingTodayFmt:           "%d restantes hoje",
            .remainingThisMonthFmt:       "%d restantes este mês",
            .notificationsLabel:          "Notificações",
            .installAlerts:               "Alertas de instalação e desinstalação",
            .notifOn:                     "Ativadas — você será notificado quando as operações terminarem",
            .notifOff:                    "Desativadas",
            .vscanSettingTitle:           "Antivírus integrado",
            .vscanSettingSubtitle:        "Verifica instaladores em busca de ameaças antes da instalação",
            .enableInSystemSettings:      "Ativar em Configurações do Sistema → Notificações",
            .storageLabel:                "Armazenamento",
            .noVolumesFound:              "Nenhum volume encontrado",
            .about:                       "Sobre",
            .viewLogs:                    "Ver logs",
            .openLogFolder:               "Abrir pasta de logs de instalação e desinstalação",
            .signOutConfirmMsg:           "Você precisará fazer login novamente para usar o ATLAS.",
            .signOutTitle:                "Sair do ATLAS?",
            // Support
            .getSupport:                  "OBTER SUPORTE",
            .replyWithin24:               "Responderemos em 24 horas",
            .product:                     "PRODUTO",
            .issueType:                   "TIPO DE PROBLEMA",
            .describeIssue:               "DESCREVA SEU PROBLEMA",
            .attachLog:                   "ANEXAR UM LOG (OPCIONAL)",
            .sendRequest:                 "Enviar solicitação de suporte",
            .sending:                     "Enviando…",
            .thankYou:                    "Obrigado!",
            .requestReceived:             "Sua solicitação de suporte foi recebida.",
            .supportTeamReplyFmt:         "Nossa equipe de suporte estará com você em breve.\nResponderemos a %@ em 24 horas.",
            .backToAtlas:                 "Voltar ao ATLAS",
            // Cleaner
            .quickClean:                  "Limpeza rápida",
            .scanSystemForClutter:        "Verificar seu sistema em busca de software de áudio desnecessário",
            .itemsMovedToTrashNote:       "Os itens são movidos para a Lixeira do macOS — nada é excluído permanentemente.",
            .startScan:                   "Iniciar verificação",
            .scanning:                    "Verificando",
            .selectAll:                   "Selecionar tudo",
            .deselectAll:                 "Desmarcar tudo",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "Nenhum item para limpar encontrado",
            .systemIsClean:               "Seu sistema está limpo",
            .noCleanerHistory:            "Sem histórico de limpeza",
            .cleanerHistory:              "Histórico de limpeza",
            .movingToTrash:               "Movendo para a Lixeira…",
            // Failure reasons
            .failReasonIncomplete:        "Instalação incompleta — os arquivos podem não ter sido copiados corretamente.",
            .failReasonFilesNotLanded:    "Alguns arquivos não chegaram ao lugar certo. Tente reinstalar.",
            .failReasonAppNoLaunch:       "O app não pôde ser iniciado após a instalação. Pode ser necessário abri-lo manualmente.",
            .failReasonAUNotRecognized:   "O plugin de áudio foi instalado, mas pode não ser reconhecido pela sua DAW ainda. Tente verificar plugins novamente.",
            .failReasonDamaged:           "O arquivo do plugin parece estar danificado. Tente baixar o original novamente.",
            .failReasonVerifyFailed:      "O ATLAS não conseguiu confirmar que a instalação foi concluída com êxito. Verifique o log.",
            .failReasonConfidenceLow:     "O ATLAS não tinha certeza de que este arquivo é seguro para instalar. Tente uma versão ou fonte diferente.",
            .failReasonScriptError:       "Um script de instalação encontrou um erro. Verifique o log para a saída completa.",
            .failReasonPkgFailed:         "O instalador do pacote não foi concluído. Pode ser necessário executá-lo manualmente.",
            .failReasonCancelled:         "Instalação cancelada.",
            .failReasonWaves:             "Este produto Waves requer uma etapa de instalação manual. Consulte o log.",
            .failReasonGeneric:           "Algo deu errado durante a instalação. Consulte o log de instalação.",
            // Demo warning
            .demoWarningLabel:            "Instalado — mas pode estar em modo Demo ou Trial. Verifique o produto.",
            // Progress steps
            .progressScanningFile:        "Verificando arquivo…",
            .progressOpeningInstaller:    "Abrindo instalador…",
            .progressCopyingFiles:        "Copiando arquivos…",
            .progressRunningInstaller:    "Executando instalador…",
            .progressRunningScript:       "Executando script de configuração…",
            .progressApplyingLicense:     "Aplicando configurações de licença…",
            .progressVerifying:           "Verificando instalação…",
            .progressCheckingLicense:     "Verificando status da licença…",
            .progressSavingProfile:       "Salvando perfil de instalação…",
            .progressCleaningUp:          "Limpando…",
            .progressDone:                "Concluído.",
            .notifyRestoreCompleteTitle:  "Restauração concluída",
            .notifyRestoreFailedTitle:    "Falha na restauração",
            .notifyUninstallSuccessBody:  "%@ foi removido com sucesso.",
            .vscanQuarantineNotifBody:    "%@ movido para a Quarentena ATLAS.",
            .vscanDeletedNotifBody:       "%@ excluído permanentemente.",
            .quitInstallAlertTitle:       "Instalação em andamento",
            .quitInstallAlertBody:        "O ATLAS está realizando uma instalação. Sair agora pode deixar arquivos em estado incompleto.\n\nDeseja mesmo sair?",
            .quitAnyway:                  "Sair mesmo assim",
            .checkForUpdates:             "Verificar atualizações",
            .menuOpenAtlas:               "Abrir ATLAS",
            .menuQuitAtlas:               "Sair do ATLAS",
            .fileShareNotifTitle:         "📦 Novo arquivo compartilhado",
            .fileShareNotifBodyFmt:       "%@ (%@) está pronto para instalar.",
            .notifyBatchUninstallTitle:   "Desinstalação de sessão concluída",
            .atlasLibrary:                "Biblioteca ATLAS",
            .noInstallsYet:               "Nenhuma instalação ainda",
            .clearAll:                    "Limpar tudo",
            .deleteAll:                   "Excluir tudo",
            .formatsLabel:                "Formatos",
            .signingLabel:                "Assinando…",
            .signedLabel:                 "Assinado!",
            .permanentlyDeleted:          "Excluído permanentemente",
            .feedbackReceived:            "Feedback ✓",
            .filesPresent:                "Arquivos presentes",
            .inTrash:                     "Na lixeira",
            .filesGone:                   "Arquivos ausentes",
            .unArchive:                   "Desarquivar",
            .installedOnFmt:              "Instalado em %@",
            .archivedOnFmt:               "Arquivado em %@",
            .archiveLabelFmt:             "Arquivo (%d)",
            .sessionFmt:                  "Sessão · %d · %@",
            .filesTrackedFmt:             "%d arquivo(s) rastreado(s)",
            .receiptsAndFilesFmt:         "%d recibo(s) · %d arquivos",
            .uninstall:                   "Desinstalar",
            .remove:                      "Remover",
            .feedback:                    "Feedback",
            .support:                     "Suporte",
            .sign:                        "Assinar",
            .enable:                      "Ativar",
            .disable:                     "Desativar",
            .clearAtlasLibraryTitle:      "Limpar Biblioteca ATLAS?",
            .clearLibraryMsgFmt:          "Todos os %d registros de instalação serão movidos para o Arquivo. Os arquivos instalados não são afetados. Você pode desarquivar qualquer registro a qualquer momento.",
            .removeFromLibraryTitle:      "Remover da Biblioteca?",
            .removeRecordMsgFmt:          "'%@' será movido para o Arquivo. Os arquivos instalados não são afetados.",
            .uninstallConfirmTitle:       "Desinstalar?",
            .uninstallConfirmMsgFmt:      "O ATLAS moverá %@ instalado por %@ para a lixeira.%@\n\nVocê pode recuperá-los da lixeira ou usando o botão Recuperar.",
            .disabledFormatsNoteFmt:      "\n\nIsso também inclui %d formato(s) desativado(s) no armazenamento ATLAS.",
            .recoverFilesTitle:           "Recuperar arquivos?",
            .recoverFilesMsgFmt:          "O ATLAS moverá os arquivos enviados para a lixeira durante a desinstalação de %@ de volta aos locais originais.",
            .recoveryNotAvailable:        "Recuperação não disponível",
            .uninstallSessionTitle:       "Desinstalar sessão?",
            .uninstallSessionMsgFmt:      "O ATLAS desinstalará %d item(ns) desta sessão. Os arquivos serão movidos para a lixeira.",
            .deleteArchivesTitle:         "Excluir arquivos permanentemente?",
            .deleteArchivesMsg:           "Isso excluirá permanentemente todo o histórico de programas arquivados da sua Biblioteca ATLAS. Esta ação não pode ser desfeita.\n\nSeus registros existentes não serão excluídos.",
            .deleteAllArchivesBtn:        "Excluir todos os arquivos",
            .deleteArchiveTitle:          "Excluir registro do arquivo?",
            .deleteArchiveMsgFmt:         "Isso remove permanentemente '%@' do histórico de arquivos. Nenhum arquivo no disco é afetado.",
            .disableFmtConfirmTitleFmt:   "Desativar %@?",
            .disableFmtConfirmMsgFmt:     "O ATLAS moverá %@ (%@) para fora da pasta de plugins. Não aparecerá no seu DAW até ser reativado.\n\nVocê pode reativá-lo a qualquer momento na Biblioteca ATLAS.",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .japanese: [
            // Existing
            .notifySuccessTitle:          "インストール完了",
            .notifySuccessBody:           "%@が正常にインストールされました。",
            .notifyFailedTitle:           "インストール失敗",
            .notifyQueueCompleteTitle:    "ATLAS — キュー完了",
            .notifyQueueCompleteBody:     "%d件が正常にインストールされました",
            .notifyUninstallComplete:     "アンインストール完了",
            .notifyUninstallFailed:       "アンインストール失敗",
            .notifyRestoreComplete:       "%@が復元されました。",
            .notifyRestoreFailed:         "%@を復元できませんでした。",
            .installMore:                 "さらにインストール",
            .retrying:                    "再試行中…",
            .cancelConfirmTitle:          "インストールを停止しますか？",
            .cancelConfirmMessage:        "現在のインストールがキャンセルされ、部分的な変更を元に戻す必要がある場合があります。",
            .cancelConfirmStop:           "停止",
            .cancelConfirmContinue:       "続行",
            .titanMissionTitle:           "TITAN CORE™ — ミッションプラン",
            .titanMissionSubtitle:        "ATLASが複数ステップのインストールを検出しました。プランを確認して開始してください。",
            .titanBegin:                  "インストール開始",
            .titanCancel:                 "キャンセル",
            .titanRunning:                "実行中…",
            .titanComplete:               "インストール完了",
            .titanStepPending:            "保留中",
            .titanStepRunning:            "実行中…",
            .titanStepDone:               "完了",
            .titanStepFailed:             "失敗",
            .titanStepSkipped:            "スキップ",
            .titanStepXcodeTools:         "Xcode コマンドラインツールをインストール",
            .titanStepInstallPkg:         "パッケージをインストール",
            .titanStepRunScript:          "スクリプトを実行",
            .titanStepRunBinary:          "ツールを実行",
            .titanStepEditHosts:          "ライセンスサーバーをブロック",
            .titanStepRunCommand:         "ターミナルコマンドを実行",
            .titanNoInstrTitle:           "インストールガイドが見つかりません",
            .titanNoInstrBody:            "ATLASは複雑なインストールを示すファイルを見つけましたが、ガイドがありません。",
            .titanNoInstrProvide:         "インストール手順を提供",
            .titanNoInstrAttempt:         "ガイドなしで試みる",
            .titanNoInstrWarning:         "⚠ ガイドなしではインストールが失敗する可能性があります。",
            .titanNoInstrHelp:            "InterLinkedサポートに連絡",
            .dropFilesHere:               "ファイルをここにドロップ",
            .releaseToAdd:                "離して追加",
            .chooseFile:                  "ファイルまたはフォルダを選択…",
            .settings:                    "設定",
            .language:                    "言語",
            .getHelp:                     "ヘルプを取得",
            .signOut:                     "サインアウト",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "完了",
            .cancel:                      "キャンセル",
            .retry:                       "再試行",
            .close:                       "閉じる",
            // Queue
            .queueInstallQueue:           "インストールキュー",
            .queueClearWaiting:           "待機中をクリア",
            .queueInstallAll:             "すべてインストール",
            .queueWaitingForSteps:        "ステップ待機中…",
            .queueStatusWaiting:          "待機中",
            .queueStatusScanning:         "スキャン中",
            .queueStatusInstalling:       "インストール中",
            .queueStatusInstalled:        "インストール済み",
            .queueStatusDemoWarning:      "デモ警告",
            .queueStatusActivation:       "アクティベーション",
            .queueStatusVerification:     "確認",
            // Tour
            .tourDontShowAgain:           "次回から表示しない",
            .tourBack:                    "戻る",
            .tourNext:                    "次へ",
            .tourStepOfFmt:               "%d / %d",
            .tourStep0Title:              "ドロップ＆インストール",
            .tourStep0Body:               "インストーラーをここにドラッグしてください — DMG、ZIP、PKG、VST3、AAX、またはRAR。ATLASがスキャンし、見つけた内容を正確に表示してワンタップでインストールします。確認するまでシステムは変更されません。",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "ATLASがあなたのセットアップについて知っているすべてがここにあります。インストール済み製品、プラグイン形式、ストレージ、クリーンアップツール、リカバリーオプション — すべて一か所に。",
            .tourStep2Title:              "インストール済み製品",
            .tourStep2Body:               "すべてのインストールがここに記録されています。タップして展開し製品を管理 — 個別のプラグイン形式（AU、VST3、VST、AAX）を有効/無効にしたり、Libraryから直接署名できます。",
            .tourStep3Title:              "アンインストールと復元",
            .tourStep3Body:               "製品をタップして展開します。Proユーザーはワンタップでアンインストール可能 — ATLASはファイルをゴミ箱に移動し、いつでも復元できるようロールバックスナップショットを保存します。",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "残留インストールファイル、孤立したコンポーネント、回収可能な一時キャッシュを検索します。ATLASは削除前に見つけた内容を正確に表示します。",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "ライブラリ全体の暗号化スナップショットをエクスポート — すべての製品、形式、パスを含みます。安全に保管して、任意のMacでフルセットアップを再構築できます。Proではクラウドバックアップが利用可能。",
            .tourStep6Title:              "設定",
            .tourStep6Body:               "アカウント、サブスクリプション、デバイス、言語を管理します。ライト、ダーク、またはシステム外観を切り替えます。設定からいつでもこのツアーを再生できます。",
            .tourStep7Title:              "準備完了です",
            .tourStep7Body:               "最初のインストーラーをドロップして始めましょう。Library、クリーンアップツール、リカバリーオプションはいつでもワンタップで利用できます。",
            .tourStep8Title:              "準備完了です",
            .tourStep8Body:               "最初のインストーラーをドロップして始めましょう。Library、クリーンアップツール、リカバリーオプションはいつでもワンタップで利用できます。",
            // Demo Alert
            .demoModeDetected:            "デモモード検出",
            .demoSignalsFound:            "シグナル検出",
            .demoWhatThisMeans:           "これが意味すること",
            .demoTip1:                    "DAWでプラグインを開き、透かし、バナー、またはアクティベーションプロンプトを探してください。",
            .demoTip2:                    "デモモードが表示された場合は、ライセンスをアクティベートまたは再入力する必要がある場合があります。",
            .demoTip3:                    "ライセンスが有効だと思われるのにプラグインがデモモードを表示する場合は、ベンダーに連絡してください。",
            // Recovery Mode
            .filterAll:                   "すべて",
            .filterReady:                 "準備完了",
            .filterInstalling:            "インストール中",
            .filterInstalled:             "インストール済み",
            .filterFailed:                "失敗",
            .filterPending:               "保留中",
            .installReadyProducts:        "準備完了製品をインストール",
            .dropInstallersAbove:         "上にインストーラーをドロップして開始",
            .recoveryComplete:            "リカバリー完了",
            .viewInLibrary:               "ライブラリで表示",
            .exitRecoveryMode:            "リカバリーモードを終了",
            .statDone:                    "完了",
            .statSkipped:                 "スキップ",
            .statLimit:                   "制限",
            .statReinstalled:             "再インストール済み",
            .statPending:                 "保留中",
            // Recovery Slot
            .stateLimitReached:           "制限に達しました",
            .dropInstallerHere:           "インストーラーをここにドロップ",
            .orLabel:                     "または",
            .installAction:               "インストール",
            // Subscription
            .backToSignIn:                "サインインに戻る",
            .reJoinAtlas:                 "ATLASに再加入",
            .paymentFailed:               "支払い失敗",
            .subscriptionRequired:        "サブスクリプションが必要",
            .checkingEllipsis:            "確認中…",
            .iveSubscribed:               "サブスクリプション済み — 更新",
            .subscribeNow:                "今すぐサブスクライブ",
            .updateBilling:               "請求情報を更新",
            .subBodyReJoin:               "サブスクリプションが期限切れです。インストールを続けるにはATLASに再加入してください。",
            .subBodyPayment:              "最後の支払いが失敗しました。続けるには請求情報を更新してください。",
            .subBodyNew:                  "ATLASにサブスクライブして、数秒でプラグインのインストールを始めましょう。",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "パスワードが必要",
            .filePasswordProtected:       "このファイルはパスワードで保護されています",
            .archivePassword:             "アーカイブパスワード",
            .enterPassword:               "パスワードを入力",
            .rememberPassword:            "ATLASはこの製品の将来のインストールのためにこのパスワードを記憶します。",
            .unlockAndInstall:            "ロック解除してインストール",
            // Rosetta
            .appleSiliconDetected:        "Apple Siliconを検出",
            .enableRosettaQ:              "IntelプラグインをロードするためにDAWでRosettaを有効にしますか？",
            .scanningDAWs:                "インストール済みDAWを検索中...",
            .noDAWsFound:                 "このMacにDAWが見つかりません。",
            .selectDAWsRosetta:           "Rosettaを有効にするDAWを選択：",
            .rosettaEnabledMsg:           "選択したDAWでRosettaが有効になりました。IntelプラグインをロードするにはDAWを再起動してください。",
            .noThanks:                    "いいえ、結構です",
            .applying:                    "適用中...",
            .enableRosettaAction:         "Rosettaを有効にする",
            .alreadyEnabled:              "すでに有効",
            // Storage/Library
            .available:                   "利用可能",
            .total:                       "合計",
            .nothingToClean:              "クリーニング不要",
            .scanUnavailable:             "スキャン利用不可",
            .quickScan:                   "クイックスキャン",
            .overview:                    "概要",
            .disabled:                    "無効",
            .archived:                    "アーカイブ済み",
            .review:                      "確認",
            // Log View
            .fullLog:                     "完全なログ",
            .logSummary:                  "サマリー",
            .less:                        "少なく表示",
            .logDetails:                  "詳細",
            .copied:                      "コピーしました！",
            .copyLabel:                   "コピー",
            // Recovery Kit
            .portableSnapshot:            "ポータブルインストールスナップショット",
            .generating:                  "生成中…",
            .exportFailed:                "エクスポート失敗",
            .generate:                    "生成",
            .cloudBackupLabel:            "クラウドバックアップ",
            .checking:                    "確認中…",
            .notBackedUp:                 "バックアップなし",
            .syncing:                     "同期中…",
            .restoring:                   "復元中…",
            .loadRecoveryKit:             "Recovery Kitを読み込む",
            .openKitFile:                 ".atlaskitファイルを開く",
            .loading:                     "読み込み中…",
            .kitLoaded:                   "キット読み込み完了 — リカバリーモードに入る準備ができました",
            .fileRejected:                "ファイル拒否 — 改ざんまたは破損",
            .couldNotLoad:                "ファイルを読み込めませんでした",
            .replace:                     "置き換える",
            .open:                        "開く",
            .crossMacKitNote:             "別のMacからエクスポートされました — すべてのファイルパスは参照用にのみ表示されます。",
            .hashMismatchNote:            "このRecovery Kitファイルは変更または破損しており、読み込めません。",
            .beginRecovery:               "ATLAS RECOVERYを開始",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "製品",
            .update:                      "更新",
            .backUp:                      "バックアップ",
            .retryCloudBackup:            "クラウドバックアップを再試行",
            // TITAN VSCAN
            .detectedThreats:             "検出された脅威",
            .showLess:                    "少なく表示",
            .showAllFmt:                  "すべて表示（%d）",
            .foundIn:                     "検出場所",
            .continueInstall:             "インストールを続行",
            .proceedWithInstall:          "インストールを進める",
            .proceedAnyway:               "それでも続行",
            .moveToQuarantine:            "隔離に移動",
            .deletePermanently:           "完全に削除",
            .stripMalwareInstall:         "マルウェアを除去してクリーンインストール",
            .vscanLicenseTip:             "これはライセンスツール（keygen/patch）です。TITAN VSCAN™は追加のマルウェアを検出しませんでした。ご自身の判断で進めてください。",
            .vscanSuspiciousTip:          "異常なパターンが検出されました。正規ソフトウェアの誤検知の可能性があります。続行する前に上記の脅威を確認してください。",
            .vscanMalwareTip:             "TITAN VSCAN™がこのインストールをブロックしました。ファイルにマルウェアが含まれており、安全にインストールできません。隔離に移動するか、完全に削除してください。",
            .vscanQuarantineConfirmMsg:   "ファイルは安全なATLAS隔離フォルダに隔離されます。後でATLAS設定で確認または完全に削除できます。",
            .vscanDeleteConfirmMsg:       "これによりMacからファイルが完全に削除されます。元に戻すことはできません。",
            // Install Overlay
            .stillWorkingFmt:             "処理中… %d秒経過",
            // Scan Result
            .keygenDetected:              "Keygen / アクティベーションツール検出",
            .windowsExe:                  "Windows実行ファイル",
            .keygenWarning:               "⚠ 警告：Keygenファイルが検出されました",
            .readyDropInstaller:          "準備完了 — MacインストーラーをATLASにドロップして続行",
            .dropNewFile:                 "新しいファイルをドロップ",
            .imDoneReady:                 "完了 — 続行する準備ができました",
            .confirmationRequired:        "確認が必要",
            .contentsFound:               "コンテンツが見つかりました",
            .alreadyInstalled:            "インストール済み",
            .insufficientSpace:           "ストレージ不足",
            .cannotInstallAuto:           "自動インストールできません",
            .share:                       "共有",
            .installAction2:              "インストール",
            // Summary Card
            .userActionRequired:          "ユーザーの操作が必要",
            .installerMovedToTrash:       "インストーラーをゴミ箱に移動しました",
            .moveInstallerToTrash:        "インストーラーをゴミ箱に移動",
            .backToHome:                  "ホームに戻る",
            .removed:                     "削除済み",
            .supportFiles:                "サポートファイル",
            .couldNotRemove:              "削除できませんでした",
            .filesMovedToTrash:           "ファイルをゴミ箱に移動しました — Finderでゴミ箱を空にしてスペースを解放してください。",
            .recover:                     "復元",
            // Settings
            .appearance:                  "外観",
            .account:                     "アカウント",
            .supportLabel:                "サポート",
            .tourAtlasTitle:              "Tour ATLAS",
            .replayWalkthrough:           "ATLASのウォークスルーを再生",
            .tools:                       "ツール",
            .fixBlockedPlugins:           "ブロックされたプラグインを修正",
            .removeSecurityBlocks:        "インストール済みプラグインのmacOSセキュリティブロックを削除",
            .fix:                         "修正",
            .installLimits:               "インストール制限",
            .dailyInstallations:          "1日のインストール数",
            .monthlyInstallations:        "月間インストール数",
            .resetsAtMidnight:            "深夜にリセット",
            .refillsOnBillingDate:        "請求日に補充",
            .remainingTodayFmt:           "今日残り%d件",
            .remainingThisMonthFmt:       "今月残り%d件",
            .notificationsLabel:          "通知",
            .installAlerts:               "インストール・アンインストール通知",
            .notifOn:                     "オン — 操作完了時に通知されます",
            .notifOff:                    "オフ",
            .vscanSettingTitle:           "内蔵ウイルススキャナー",
            .vscanSettingSubtitle:        "インストール前にインストーラーの脅威をスキャン",
            .enableInSystemSettings:      "システム設定 → 通知で有効にする",
            .storageLabel:                "ストレージ",
            .noVolumesFound:              "ボリュームが見つかりません",
            .about:                       "ATLASについて",
            .viewLogs:                    "ログを表示",
            .openLogFolder:               "インストール・アンインストールログフォルダを開く",
            .signOutConfirmMsg:           "ATLASを使用するには再度サインインする必要があります。",
            .signOutTitle:                "ATLASからサインアウトしますか？",
            // Support
            .getSupport:                  "サポートを取得",
            .replyWithin24:               "24時間以内に返信します",
            .product:                     "製品",
            .issueType:                   "問題の種類",
            .describeIssue:               "問題を説明してください",
            .attachLog:                   "ログを添付（任意）",
            .sendRequest:                 "サポートリクエストを送信",
            .sending:                     "送信中…",
            .thankYou:                    "ありがとうございます！",
            .requestReceived:             "サポートリクエストを受け付けました。",
            .supportTeamReplyFmt:         "サポートチームがまもなくご連絡します。\n%@に24時間以内に返信します。",
            .backToAtlas:                 "ATLASに戻る",
            // Cleaner
            .quickClean:                  "クイッククリーン",
            .scanSystemForClutter:        "オーディオソフトウェアの不要ファイルをスキャン",
            .itemsMovedToTrashNote:       "アイテムはmacOSのゴミ箱に移動されます — 完全には削除されません。",
            .startScan:                   "スキャン開始",
            .scanning:                    "スキャン中",
            .selectAll:                   "すべて選択",
            .deselectAll:                 "すべて選択解除",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "クリーニング項目が見つかりません",
            .systemIsClean:               "システムはクリーンです",
            .noCleanerHistory:            "クリーニング履歴がありません",
            .cleanerHistory:              "クリーニング履歴",
            .movingToTrash:               "ゴミ箱に移動中…",
            // Failure reasons
            .failReasonIncomplete:        "インストールが不完全です — ファイルが正しくコピーされていない可能性があります。",
            .failReasonFilesNotLanded:    "一部のファイルが正しい場所に到達しませんでした。再インストールをお試しください。",
            .failReasonAppNoLaunch:       "インストール後にアプリが起動できませんでした。手動で開く必要があるかもしれません。",
            .failReasonAUNotRecognized:   "オーディオプラグインはインストールされましたが、DAWにまだ認識されていない可能性があります。プラグインの再スキャンをお試しください。",
            .failReasonDamaged:           "プラグインファイルが破損しているようです。オリジナルを再ダウンロードしてください。",
            .failReasonVerifyFailed:      "ATLASはインストールが正常に完了したことを確認できませんでした。インストールログを確認してください。",
            .failReasonConfidenceLow:     "ATLASはこのファイルが安全にインストールできるか確信が持てませんでした。別のバージョンまたはソースをお試しください。",
            .failReasonScriptError:       "インストールスクリプトでエラーが発生しました。ログで完全な出力を確認してください。",
            .failReasonPkgFailed:         "パッケージインストーラーが完了しませんでした。手動で実行する必要があるかもしれません。",
            .failReasonCancelled:         "インストールがキャンセルされました。",
            .failReasonWaves:             "このWaves製品は手動インストール手順が必要です。ログを参照してください。",
            .failReasonGeneric:           "インストール中に問題が発生しました。インストールログを確認してください。",
            // Demo warning
            .demoWarningLabel:            "インストール済み — ただしデモまたはトライアルモードで動作している可能性があります。製品を確認してください。",
            // Progress steps
            .progressScanningFile:        "ファイルをスキャン中…",
            .progressOpeningInstaller:    "インストーラーを開いています…",
            .progressCopyingFiles:        "ファイルをコピー中…",
            .progressRunningInstaller:    "インストーラーを実行中…",
            .progressRunningScript:       "セットアップスクリプトを実行中…",
            .progressApplyingLicense:     "ライセンス設定を適用中…",
            .progressVerifying:           "インストールを確認中…",
            .progressCheckingLicense:     "ライセンス状態を確認中…",
            .progressSavingProfile:       "インストールプロファイルを保存中…",
            .progressCleaningUp:          "クリーンアップ中…",
            .progressDone:                "完了。",
            .notifyRestoreCompleteTitle:  "復元完了",
            .notifyRestoreFailedTitle:    "復元失敗",
            .notifyUninstallSuccessBody:  "%@が正常に削除されました。",
            .vscanQuarantineNotifBody:    "%@をATLAS検疫に移動しました。",
            .vscanDeletedNotifBody:       "%@を完全に削除しました。",
            .quitInstallAlertTitle:       "インストール中",
            .quitInstallAlertBody:        "ATLASは現在インストールを実行中です。今すぐ終了するとファイルが不完全な状態になる可能性があります。\n\n本当に終了しますか？",
            .quitAnyway:                  "強制終了",
            .checkForUpdates:             "アップデートを確認",
            .menuOpenAtlas:               "ATLASを開く",
            .menuQuitAtlas:               "ATLASを終了",
            .fileShareNotifTitle:         "📦 新しいファイルが共有されました",
            .fileShareNotifBodyFmt:       "%@ (%@) がインストール可能です。",
            .notifyBatchUninstallTitle:   "セッションのアンインストール完了",
            .atlasLibrary:                "ATLASライブラリ",
            .noInstallsYet:               "まだインストールなし",
            .clearAll:                    "すべてクリア",
            .deleteAll:                   "すべて削除",
            .formatsLabel:                "フォーマット",
            .signingLabel:                "署名中…",
            .signedLabel:                 "署名済み！",
            .permanentlyDeleted:          "完全に削除済み",
            .feedbackReceived:            "フィードバック ✓",
            .filesPresent:                "ファイルあり",
            .inTrash:                     "ゴミ箱に移動済み",
            .filesGone:                   "ファイルなし",
            .unArchive:                   "アーカイブ解除",
            .installedOnFmt:              "%@にインストール済み",
            .archivedOnFmt:               "%@にアーカイブ済み",
            .archiveLabelFmt:             "アーカイブ (%d)",
            .sessionFmt:                  "セッション · %d · %@",
            .filesTrackedFmt:             "%dファイル追跡中",
            .receiptsAndFilesFmt:         "%dレシート · %dファイル",
            .uninstall:                   "アンインストール",
            .remove:                      "削除",
            .feedback:                    "フィードバック",
            .support:                     "サポート",
            .sign:                        "署名",
            .enable:                      "有効化",
            .disable:                     "無効化",
            .clearAtlasLibraryTitle:      "ATLASライブラリをクリア？",
            .clearLibraryMsgFmt:          "%d件のインストール記録がアーカイブに移動されます。インストール済みファイルは影響を受けません。いつでもアーカイブ解除できます。",
            .removeFromLibraryTitle:      "ライブラリから削除？",
            .removeRecordMsgFmt:          "'%@'がアーカイブに移動されます。インストール済みファイルは影響を受けません。",
            .uninstallConfirmTitle:       "アンインストール？",
            .uninstallConfirmMsgFmt:      "ATLASは%@（%@によってインストール）をゴミ箱に移動します。%@\n\nゴミ箱から、または「回復」ボタンで回復できます。",
            .disabledFormatsNoteFmt:      "\n\nATLASストレージには%d個の無効化フォーマットも含まれます。",
            .recoverFilesTitle:           "ファイルを回復？",
            .recoverFilesMsgFmt:          "ATLASは%@のアンインストール時にゴミ箱に移動したファイルを元の場所に戻します。",
            .recoveryNotAvailable:        "回復不可",
            .uninstallSessionTitle:       "セッションをアンインストール？",
            .uninstallSessionMsgFmt:      "ATLASはこのセッションの%d個のアイテムをアンインストールします。ファイルはゴミ箱に移動されます。",
            .deleteArchivesTitle:         "アーカイブを完全に削除？",
            .deleteArchivesMsg:           "ATLASライブラリのすべてのアーカイブされたプログラム履歴が完全に削除されます。この操作は元に戻せません。\n\n既存のログは削除されません。",
            .deleteAllArchivesBtn:        "すべてのアーカイブを削除",
            .deleteArchiveTitle:          "アーカイブ記録を削除？",
            .deleteArchiveMsgFmt:         "'%@'をアーカイブ履歴から完全に削除します。ディスク上のファイルには影響しません。",
            .disableFmtConfirmTitleFmt:   "%@を無効化？",
            .disableFmtConfirmMsgFmt:     "ATLASは%@ (%@)をプラグインフォルダから移動します。再有効化するまでDAWに表示されません。\n\nATLASライブラリからいつでも再有効化できます。",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .chinese: [
            // Existing
            .notifySuccessTitle:          "安装完成",
            .notifySuccessBody:           "%@安装成功。",
            .notifyFailedTitle:           "安装失败",
            .notifyQueueCompleteTitle:    "ATLAS — 队列完成",
            .notifyQueueCompleteBody:     "%d个已成功安装",
            .notifyUninstallComplete:     "卸载完成",
            .notifyUninstallFailed:       "卸载失败",
            .notifyRestoreComplete:       "%@已恢复。",
            .notifyRestoreFailed:         "%@无法恢复。",
            .installMore:                 "继续安装",
            .retrying:                    "重试中…",
            .cancelConfirmTitle:          "停止安装？",
            .cancelConfirmMessage:        "当前安装将被取消，可能需要撤销部分更改。",
            .cancelConfirmStop:           "停止",
            .cancelConfirmContinue:       "继续",
            .titanMissionTitle:           "TITAN CORE™ — 任务计划",
            .titanMissionSubtitle:        "ATLAS检测到多步骤安装。请查看计划后开始。",
            .titanBegin:                  "开始安装",
            .titanCancel:                 "取消",
            .titanRunning:                "运行中…",
            .titanComplete:               "安装完成",
            .titanStepPending:            "等待中",
            .titanStepRunning:            "运行中…",
            .titanStepDone:               "完成",
            .titanStepFailed:             "失败",
            .titanStepSkipped:            "已跳过",
            .titanStepXcodeTools:         "安装Xcode命令行工具",
            .titanStepInstallPkg:         "安装软件包",
            .titanStepRunScript:          "运行脚本",
            .titanStepRunBinary:          "运行工具",
            .titanStepEditHosts:          "屏蔽授权服务器",
            .titanStepRunCommand:         "运行终端命令",
            .titanNoInstrTitle:           "未找到安装指南",
            .titanNoInstrBody:            "ATLAS发现了表明复杂安装的文件，但没有包含指南。",
            .titanNoInstrProvide:         "提供安装说明",
            .titanNoInstrAttempt:         "尝试无指南安装",
            .titanNoInstrWarning:         "⚠ 没有指南，安装可能会失败。",
            .titanNoInstrHelp:            "获取InterLinked支持",
            .dropFilesHere:               "将文件拖放到此处",
            .releaseToAdd:                "松开以添加",
            .chooseFile:                  "选择文件或文件夹…",
            .settings:                    "设置",
            .language:                    "语言",
            .getHelp:                     "获取帮助",
            .signOut:                     "退出登录",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "完成",
            .cancel:                      "取消",
            .retry:                       "重试",
            .close:                       "关闭",
            // Queue
            .queueInstallQueue:           "安装队列",
            .queueClearWaiting:           "清除等待",
            .queueInstallAll:             "全部安装",
            .queueWaitingForSteps:        "等待步骤…",
            .queueStatusWaiting:          "等待中",
            .queueStatusScanning:         "扫描中",
            .queueStatusInstalling:       "安装中",
            .queueStatusInstalled:        "已安装",
            .queueStatusDemoWarning:      "演示警告",
            .queueStatusActivation:       "激活",
            .queueStatusVerification:     "验证",
            // Tour
            .tourDontShowAgain:           "不再显示",
            .tourBack:                    "返回",
            .tourNext:                    "下一步",
            .tourStepOfFmt:               "%d / %d",
            .tourStep0Title:              "拖放安装",
            .tourStep0Body:               "将任何安装程序拖放到此处 — DMG、ZIP、PKG、VST3、AAX 或 RAR。ATLAS 扫描后向您展示发现的内容，一键安装。在您确认之前，不会对系统做任何更改。",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "ATLAS 对您系统的所有了解都在这里。已安装的产品、插件格式、存储空间、清理工具和恢复选项 — 尽在一处。",
            .tourStep2Title:              "您已安装的产品",
            .tourStep2Body:               "每次安装都记录在这里。点击展开并管理您的产品 — 启用或禁用单个插件格式（AU、VST3、VST、AAX），并直接从 Library 中签名。",
            .tourStep3Title:              "卸载与恢复",
            .tourStep3Body:               "点击任意产品以展开。Pro 用户可一键卸载 — ATLAS 将文件移至废纸篓并保存回滚快照，以便随时恢复。",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "查找残留安装文件、孤立组件和可回收的临时缓存。ATLAS 在移除任何内容之前会向您展示发现的具体内容。",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "导出整个资料库的加密快照 — 包含每个产品、格式和路径。妥善保存，随时在任意 Mac 上重建完整的设置。Pro 版支持云端备份。",
            .tourStep6Title:              "设置",
            .tourStep6Body:               "管理账户、订阅、设备和语言。在浅色、深色或系统外观之间切换。随时从设置中重新播放此导览。",
            .tourStep7Title:              "您已准备就绪",
            .tourStep7Body:               "拖入您的第一个安装程序即可开始。您的 Library、清理工具和恢复选项始终触手可及。",
            .tourStep8Title:              "您已准备就绪",
            .tourStep8Body:               "拖入您的第一个安装程序即可开始。您的 Library、清理工具和恢复选项始终触手可及。",
            // Demo Alert
            .demoModeDetected:            "检测到演示模式",
            .demoSignalsFound:            "发现信号",
            .demoWhatThisMeans:           "这意味着什么",
            .demoTip1:                    "在您的 DAW 中打开插件，查看是否有水印、横幅或激活提示。",
            .demoTip2:                    "如果出现演示模式，您可能需要激活或重新输入许可证。",
            .demoTip3:                    "如果您认为许可证有效但插件仍显示演示模式，请联系供应商。",
            // Recovery Mode
            .filterAll:                   "全部",
            .filterReady:                 "就绪",
            .filterInstalling:            "安装中",
            .filterInstalled:             "已安装",
            .filterFailed:                "失败",
            .filterPending:               "待处理",
            .installReadyProducts:        "安装就绪产品",
            .dropInstallersAbove:         "将安装程序拖放到上方以开始",
            .recoveryComplete:            "恢复完成",
            .viewInLibrary:               "在资料库中查看",
            .exitRecoveryMode:            "退出恢复模式",
            .statDone:                    "完成",
            .statSkipped:                 "已跳过",
            .statLimit:                   "限制",
            .statReinstalled:             "已重新安装",
            .statPending:                 "待处理",
            // Recovery Slot
            .stateLimitReached:           "已达到限制",
            .dropInstallerHere:           "将安装程序拖放到此处",
            .orLabel:                     "或",
            .installAction:               "安装",
            // Subscription
            .backToSignIn:                "返回登录",
            .reJoinAtlas:                 "重新加入 ATLAS",
            .paymentFailed:               "付款失败",
            .subscriptionRequired:        "需要订阅",
            .checkingEllipsis:            "检查中…",
            .iveSubscribed:               "我已订阅 — 刷新",
            .subscribeNow:                "立即订阅",
            .updateBilling:               "更新账单信息",
            .subBodyReJoin:               "您的订阅已过期。重新加入 ATLAS 以继续安装。",
            .subBodyPayment:              "您的最后一次付款失败。请更新账单信息以继续。",
            .subBodyNew:                  "订阅 ATLAS，在数秒内开始安装插件。",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "需要密码",
            .filePasswordProtected:       "此文件受密码保护",
            .archivePassword:             "压缩包密码",
            .enterPassword:               "输入密码",
            .rememberPassword:            "ATLAS 将为此产品的未来安装记住此密码。",
            .unlockAndInstall:            "解锁并安装",
            // Rosetta
            .appleSiliconDetected:        "检测到 Apple Silicon",
            .enableRosettaQ:              "为您的 DAW 启用 Rosetta 以加载 Intel 插件？",
            .scanningDAWs:                "正在扫描已安装的 DAW...",
            .noDAWsFound:                 "此 Mac 上未找到 DAW。",
            .selectDAWsRosetta:           "选择要启用 Rosetta 的 DAW：",
            .rosettaEnabledMsg:           "已为所选 DAW 启用 Rosetta。请重启 DAW 以加载 Intel 插件。",
            .noThanks:                    "不，谢谢",
            .applying:                    "应用中...",
            .enableRosettaAction:         "启用 Rosetta",
            .alreadyEnabled:              "已启用",
            // Storage/Library
            .available:                   "可用",
            .total:                       "总计",
            .nothingToClean:              "无需清理",
            .scanUnavailable:             "扫描不可用",
            .quickScan:                   "快速扫描",
            .overview:                    "概览",
            .disabled:                    "已禁用",
            .archived:                    "已归档",
            .review:                      "查看",
            // Log View
            .fullLog:                     "完整日志",
            .logSummary:                  "摘要",
            .less:                        "收起",
            .logDetails:                  "详情",
            .copied:                      "已复制！",
            .copyLabel:                   "复制",
            // Recovery Kit
            .portableSnapshot:            "便携式安装快照",
            .generating:                  "生成中…",
            .exportFailed:                "导出失败",
            .generate:                    "生成",
            .cloudBackupLabel:            "云备份",
            .checking:                    "检查中…",
            .notBackedUp:                 "未备份",
            .syncing:                     "同步中…",
            .restoring:                   "恢复中…",
            .loadRecoveryKit:             "加载 Recovery Kit",
            .openKitFile:                 "打开 .atlaskit 文件",
            .loading:                     "加载中…",
            .kitLoaded:                   "Kit 已加载 — 准备进入恢复模式",
            .fileRejected:                "文件被拒绝 — 已被篡改或损坏",
            .couldNotLoad:                "无法加载文件",
            .replace:                     "替换",
            .open:                        "打开",
            .crossMacKitNote:             "从其他 Mac 导出 — 所有文件路径仅供参考。",
            .hashMismatchNote:            "此 Recovery Kit 文件已被修改或损坏，无法加载。",
            .beginRecovery:               "开始 ATLAS 恢复",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "产品",
            .update:                      "更新",
            .backUp:                      "备份",
            .retryCloudBackup:            "重试云备份",
            // TITAN VSCAN
            .detectedThreats:             "检测到的威胁",
            .showLess:                    "显示更少",
            .showAllFmt:                  "显示全部（%d）",
            .foundIn:                     "发现于",
            .continueInstall:             "继续安装",
            .proceedWithInstall:          "进行安装",
            .proceedAnyway:               "仍然继续",
            .moveToQuarantine:            "移至隔离",
            .deletePermanently:           "永久删除",
            .stripMalwareInstall:         "清除恶意软件并干净安装",
            .vscanLicenseTip:             "这是许可证工具（keygen/patch）。TITAN VSCAN™ 未检测到额外恶意软件。请自行斟酌继续。",
            .vscanSuspiciousTip:          "检测到异常模式。这可能是合法软件的误报。继续前请查看上方的威胁信息。",
            .vscanMalwareTip:             "TITAN VSCAN™ 已阻止此安装。该文件包含恶意软件，无法安全安装。请将其移至隔离或永久删除。",
            .vscanQuarantineConfirmMsg:   "该文件将被隔离到安全的 ATLAS 隔离文件夹中。您可以稍后在 ATLAS 设置中查看或永久删除。",
            .vscanDeleteConfirmMsg:       "这将从您的 Mac 中永久删除该文件。此操作无法撤销。",
            // Install Overlay
            .stillWorkingFmt:             "仍在处理… 已过 %d 秒",
            // Scan Result
            .keygenDetected:              "检测到 Keygen / 激活工具",
            .windowsExe:                  "Windows 可执行文件",
            .keygenWarning:               "⚠ 警告：检测到 Keygen 文件",
            .readyDropInstaller:          "就绪 — 将您的 Mac 安装程序拖入 ATLAS 以继续",
            .dropNewFile:                 "拖放新文件",
            .imDoneReady:                 "完成 — 准备继续",
            .confirmationRequired:        "需要确认",
            .contentsFound:               "已找到内容",
            .alreadyInstalled:            "已安装",
            .insufficientSpace:           "空间不足",
            .cannotInstallAuto:           "无法自动安装",
            .share:                       "共享",
            .installAction2:              "安装",
            // Summary Card
            .userActionRequired:          "需要用户操作",
            .installerMovedToTrash:       "安装程序已移至废纸篓",
            .moveInstallerToTrash:        "将安装程序移至废纸篓",
            .backToHome:                  "返回主页",
            .removed:                     "已删除",
            .supportFiles:                "支持文件",
            .couldNotRemove:              "无法删除",
            .filesMovedToTrash:           "文件已移至废纸篓 — 在 Finder 中清空废纸篓以释放空间。",
            .recover:                     "恢复",
            // Settings
            .appearance:                  "外观",
            .account:                     "账户",
            .supportLabel:                "支持",
            .tourAtlasTitle:              "ATLAS 导览",
            .replayWalkthrough:           "重新播放 ATLAS 导览",
            .tools:                       "工具",
            .fixBlockedPlugins:           "修复被阻止的插件",
            .removeSecurityBlocks:        "删除已安装插件上的 macOS 安全限制",
            .fix:                         "修复",
            .installLimits:               "安装限制",
            .dailyInstallations:          "每日安装次数",
            .monthlyInstallations:        "每月安装次数",
            .resetsAtMidnight:            "午夜重置",
            .refillsOnBillingDate:        "在账单日补充",
            .remainingTodayFmt:           "今日剩余 %d 次",
            .remainingThisMonthFmt:       "本月剩余 %d 次",
            .notificationsLabel:          "通知",
            .installAlerts:               "安装和卸载提醒",
            .notifOn:                     "开启 — 操作完成时将收到通知",
            .notifOff:                    "关闭",
            .vscanSettingTitle:           "内置病毒扫描器",
            .vscanSettingSubtitle:        "在安装前扫描安装程序中的威胁",
            .enableInSystemSettings:      "在系统设置 → 通知中启用",
            .storageLabel:                "储存",
            .noVolumesFound:              "未找到宗卷",
            .about:                       "关于",
            .viewLogs:                    "查看日志",
            .openLogFolder:               "打开安装和卸载日志文件夹",
            .signOutConfirmMsg:           "您需要重新登录才能使用 ATLAS。",
            .signOutTitle:                "退出 ATLAS 账户？",
            // Support
            .getSupport:                  "获取支持",
            .replyWithin24:               "我们将在 24 小时内回复",
            .product:                     "产品",
            .issueType:                   "问题类型",
            .describeIssue:               "描述您的问题",
            .attachLog:                   "附上日志（可选）",
            .sendRequest:                 "发送支持请求",
            .sending:                     "发送中…",
            .thankYou:                    "感谢您！",
            .requestReceived:             "您的支持请求已收到。",
            .supportTeamReplyFmt:         "我们的支持团队将尽快与您联系。\n我们将在 24 小时内回复 %@。",
            .backToAtlas:                 "返回 ATLAS",
            // Cleaner
            .quickClean:                  "快速清理",
            .scanSystemForClutter:        "扫描系统中的音频软件杂乱文件",
            .itemsMovedToTrashNote:       "项目将移至 macOS 废纸篓 — 不会被永久删除。",
            .startScan:                   "开始扫描",
            .scanning:                    "扫描中",
            .selectAll:                   "全选",
            .deselectAll:                 "取消全选",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "未找到需要清理的项目",
            .systemIsClean:               "您的系统很干净",
            .noCleanerHistory:            "暂无清理历史",
            .cleanerHistory:              "清理历史",
            .movingToTrash:               "移至废纸篓…",
            // Failure reasons
            .failReasonIncomplete:        "安装不完整 — 文件可能未正确复制。",
            .failReasonFilesNotLanded:    "部分文件未落在正确位置。请尝试重新安装。",
            .failReasonAppNoLaunch:       "安装后应用程序无法启动。可能需要手动打开。",
            .failReasonAUNotRecognized:   "音频插件已安装，但您的 DAW 可能尚未识别。请尝试重新扫描插件。",
            .failReasonDamaged:           "插件文件似乎已损坏。请尝试重新下载原始文件。",
            .failReasonVerifyFailed:      "ATLAS 无法确认安装已成功完成。请查看安装日志。",
            .failReasonConfidenceLow:     "ATLAS 对此文件的安装安全性没有把握。请尝试不同的版本或来源。",
            .failReasonScriptError:       "安装脚本遇到错误。请查看安装日志以获取完整输出。",
            .failReasonPkgFailed:         "软件包安装程序未完成。您可能需要手动运行它。",
            .failReasonCancelled:         "安装已取消。",
            .failReasonWaves:             "此 Waves 产品需要手动安装步骤。请参阅日志。",
            .failReasonGeneric:           "安装过程中出现问题。请查看安装日志。",
            // Demo warning
            .demoWarningLabel:            "已安装 — 但可能在演示或试用模式下运行。请检查产品。",
            // Progress steps
            .progressScanningFile:        "扫描文件…",
            .progressOpeningInstaller:    "打开安装程序…",
            .progressCopyingFiles:        "复制文件…",
            .progressRunningInstaller:    "运行安装程序…",
            .progressRunningScript:       "运行设置脚本…",
            .progressApplyingLicense:     "应用许可证设置…",
            .progressVerifying:           "验证安装…",
            .progressCheckingLicense:     "检查许可证状态…",
            .progressSavingProfile:       "保存安装配置…",
            .progressCleaningUp:          "清理中…",
            .progressDone:                "完成。",
            .notifyRestoreCompleteTitle:  "恢复完成",
            .notifyRestoreFailedTitle:    "恢复失败",
            .notifyUninstallSuccessBody:  "%@已成功删除。",
            .vscanQuarantineNotifBody:    "%@已移至ATLAS隔离区。",
            .vscanDeletedNotifBody:       "%@已永久删除。",
            .quitInstallAlertTitle:       "正在安装",
            .quitInstallAlertBody:        "ATLAS正在执行安装操作。现在退出可能会使文件处于不完整状态。\n\n确定要退出吗？",
            .quitAnyway:                  "仍然退出",
            .checkForUpdates:             "检查更新",
            .menuOpenAtlas:               "打开ATLAS",
            .menuQuitAtlas:               "退出ATLAS",
            .fileShareNotifTitle:         "📦 有新文件分享",
            .fileShareNotifBodyFmt:       "%@（%@）已准备好安装。",
            .notifyBatchUninstallTitle:   "会话卸载完成",
            .atlasLibrary:                "ATLAS资料库",
            .noInstallsYet:               "暂无安装记录",
            .clearAll:                    "清除全部",
            .deleteAll:                   "全部删除",
            .formatsLabel:                "格式",
            .signingLabel:                "签名中…",
            .signedLabel:                 "已签名！",
            .permanentlyDeleted:          "已永久删除",
            .feedbackReceived:            "反馈 ✓",
            .filesPresent:                "文件存在",
            .inTrash:                     "在废纸篓",
            .filesGone:                   "文件已消失",
            .unArchive:                   "取消存档",
            .installedOnFmt:              "安装于 %@",
            .archivedOnFmt:               "存档于 %@",
            .archiveLabelFmt:             "存档 (%d)",
            .sessionFmt:                  "会话 · %d · %@",
            .filesTrackedFmt:             "已跟踪 %d 个文件",
            .receiptsAndFilesFmt:         "%d 张收据 · %d 个文件",
            .uninstall:                   "卸载",
            .remove:                      "删除",
            .feedback:                    "反馈",
            .support:                     "支持",
            .sign:                        "签名",
            .enable:                      "启用",
            .disable:                     "禁用",
            .clearAtlasLibraryTitle:      "清除ATLAS资料库？",
            .clearLibraryMsgFmt:          "所有%d条安装记录将移至存档。已安装的文件不受影响。您可以随时取消存档任意记录。",
            .removeFromLibraryTitle:      "从资料库中删除？",
            .removeRecordMsgFmt:          "'%@'将移至存档。已安装的文件不受影响。",
            .uninstallConfirmTitle:       "卸载？",
            .uninstallConfirmMsgFmt:      "ATLAS将把%@（由%@安装）移至废纸篓。%@\n\n您可以从废纸篓或使用恢复按钮进行恢复。",
            .disabledFormatsNoteFmt:      "\n\n这还包括ATLAS存储中%d个已禁用格式。",
            .recoverFilesTitle:           "恢复文件？",
            .recoverFilesMsgFmt:          "ATLAS将把卸载%@时移入废纸篓的文件恢复到原始位置。",
            .recoveryNotAvailable:        "无法恢复",
            .uninstallSessionTitle:       "卸载会话？",
            .uninstallSessionMsgFmt:      "ATLAS将卸载此会话中的%d个项目。文件将移至废纸篓。",
            .deleteArchivesTitle:         "永久删除存档？",
            .deleteArchivesMsg:           "这将永久删除ATLAS资料库中的所有存档程序历史记录。此操作无法撤销。\n\n您现有的日志不会被删除。",
            .deleteAllArchivesBtn:        "删除所有存档",
            .deleteArchiveTitle:          "删除存档记录？",
            .deleteArchiveMsgFmt:         "这将从存档历史记录中永久删除'%@'。磁盘上的文件不受影响。",
            .disableFmtConfirmTitleFmt:   "禁用 %@？",
            .disableFmtConfirmMsgFmt:     "ATLAS将把%@ (%@)移出插件文件夹。在重新启用之前，它不会出现在您的DAW中。\n\n您随时可以从ATLAS资料库重新启用它。",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],

        .korean: [
            // Existing
            .notifySuccessTitle:          "설치 완료",
            .notifySuccessBody:           "%@이(가) 성공적으로 설치되었습니다.",
            .notifyFailedTitle:           "설치 실패",
            .notifyQueueCompleteTitle:    "ATLAS — 큐 완료",
            .notifyQueueCompleteBody:     "%d개가 성공적으로 설치되었습니다",
            .notifyUninstallComplete:     "제거 완료",
            .notifyUninstallFailed:       "제거 실패",
            .notifyRestoreComplete:       "%@이(가) 복원되었습니다.",
            .notifyRestoreFailed:         "%@을(를) 복원할 수 없습니다.",
            .installMore:                 "더 설치하기",
            .retrying:                    "재시도 중…",
            .cancelConfirmTitle:          "설치를 중단하시겠습니까?",
            .cancelConfirmMessage:        "현재 설치가 취소되고 부분적인 변경 사항을 실행 취소해야 할 수 있습니다.",
            .cancelConfirmStop:           "중단",
            .cancelConfirmContinue:       "계속",
            .titanMissionTitle:           "TITAN CORE™ — 미션 계획",
            .titanMissionSubtitle:        "ATLAS가 다단계 설치를 감지했습니다. 계획을 검토하고 시작하세요.",
            .titanBegin:                  "설치 시작",
            .titanCancel:                 "취소",
            .titanRunning:                "실행 중…",
            .titanComplete:               "설치 완료",
            .titanStepPending:            "대기 중",
            .titanStepRunning:            "실행 중…",
            .titanStepDone:               "완료",
            .titanStepFailed:             "실패",
            .titanStepSkipped:            "건너뜀",
            .titanStepXcodeTools:         "Xcode 명령줄 도구 설치",
            .titanStepInstallPkg:         "패키지 설치",
            .titanStepRunScript:          "스크립트 실행",
            .titanStepRunBinary:          "도구 실행",
            .titanStepEditHosts:          "라이선스 서버 차단",
            .titanStepRunCommand:         "터미널 명령 실행",
            .titanNoInstrTitle:           "설치 가이드를 찾을 수 없음",
            .titanNoInstrBody:            "ATLAS가 복잡한 설치를 나타내는 파일을 발견했지만 가이드가 없습니다.",
            .titanNoInstrProvide:         "설치 지침 제공",
            .titanNoInstrAttempt:         "가이드 없이 시도",
            .titanNoInstrWarning:         "⚠ 가이드 없이는 설치가 실패할 수 있습니다.",
            .titanNoInstrHelp:            "InterLinked 지원 받기",
            .dropFilesHere:               "파일을 여기에 드롭",
            .releaseToAdd:                "놓아서 추가",
            .chooseFile:                  "파일 또는 폴더 선택…",
            .settings:                    "설정",
            .language:                    "언어",
            .getHelp:                     "도움 받기",
            .signOut:                     "로그아웃",
            .upgrade:                     "Subscribe to ATLAS",
            .done:                        "완료",
            .cancel:                      "취소",
            .retry:                       "재시도",
            .close:                       "닫기",
            // Queue
            .queueInstallQueue:           "설치 큐",
            .queueClearWaiting:           "대기 중 지우기",
            .queueInstallAll:             "모두 설치",
            .queueWaitingForSteps:        "단계 대기 중…",
            .queueStatusWaiting:          "대기 중",
            .queueStatusScanning:         "스캔 중",
            .queueStatusInstalling:       "설치 중",
            .queueStatusInstalled:        "설치됨",
            .queueStatusDemoWarning:      "데모 경고",
            .queueStatusActivation:       "활성화",
            .queueStatusVerification:     "검증",
            // Tour
            .tourDontShowAgain:           "다시 표시 안 함",
            .tourBack:                    "이전",
            .tourNext:                    "다음",
            .tourStepOfFmt:               "%d / %d",
            .tourStep0Title:              "드롭 & 설치",
            .tourStep0Body:               "인스톨러를 여기에 드래그하세요 — DMG, ZIP, PKG, VST3, AAX 또는 RAR. ATLAS가 스캔하여 발견한 내용을 정확히 보여주고 한 번의 탭으로 설치합니다. 확인하기 전까지 시스템을 변경하지 않습니다.",
            .tourStep1Title:              "ATLAS Library",
            .tourStep1Body:               "ATLAS가 당신의 설정에 대해 알고 있는 모든 것이 여기에 있습니다. 설치된 제품, 플러그인 형식, 저장 공간, 정리 도구, 복구 옵션 — 모두 한 곳에.",
            .tourStep2Title:              "설치된 제품",
            .tourStep2Body:               "모든 설치가 여기에 기록됩니다. 탭하여 제품을 펼치고 관리하세요 — 개별 플러그인 형식(AU, VST3, VST, AAX)을 활성화 또는 비활성화하고 Library에서 직접 서명할 수 있습니다.",
            .tourStep3Title:              "제거 및 복구",
            .tourStep3Body:               "제품을 탭하여 펼치세요. Pro 사용자는 한 번의 탭으로 제거 가능 — ATLAS가 파일을 휴지통으로 이동하고 언제든 복구할 수 있도록 롤백 스냅샷을 저장합니다.",
            .tourStep4Title:              "ATLAS CLEANER™",
            .tourStep4Body:               "잔류 설치 파일, 고립된 컴포넌트, 회수 가능한 임시 캐시를 찾아냅니다. ATLAS는 무엇이든 제거하기 전에 발견한 내용을 정확히 보여줍니다.",
            .tourStep5Title:              "ATLAS RECOVERY KIT™",
            .tourStep5Body:               "전체 라이브러리의 암호화된 스냅샷을 내보내세요 — 모든 제품, 형식, 경로가 포함됩니다. 안전하게 보관하여 어떤 Mac에서도 완전한 설정을 재구성할 수 있습니다. Pro에서 클라우드 백업 이용 가능.",
            .tourStep6Title:              "설정",
            .tourStep6Body:               "계정, 구독, 기기, 언어를 관리하세요. 라이트, 다크 또는 시스템 외관으로 전환하세요. 설정에서 언제든지 이 투어를 다시 볼 수 있습니다.",
            .tourStep7Title:              "준비 완료",
            .tourStep7Body:               "첫 번째 인스톨러를 드롭하여 시작하세요. Library, 정리 도구, 복구 옵션이 언제나 한 탭 거리에 있습니다.",
            .tourStep8Title:              "준비 완료",
            .tourStep8Body:               "첫 번째 인스톨러를 드롭하여 시작하세요. Library, 정리 도구, 복구 옵션이 언제나 한 탭 거리에 있습니다.",
            // Demo Alert
            .demoModeDetected:            "데모 모드 감지됨",
            .demoSignalsFound:            "신호 발견됨",
            .demoWhatThisMeans:           "이것이 의미하는 것",
            .demoTip1:                    "DAW에서 플러그인을 열고 워터마크, 배너 또는 활성화 메시지를 확인하세요.",
            .demoTip2:                    "데모 모드가 나타나면 라이선스를 활성화하거나 다시 입력해야 할 수 있습니다.",
            .demoTip3:                    "라이선스가 유효하다고 생각하지만 플러그인이 여전히 데모 모드를 표시하는 경우 공급업체에 문의하세요.",
            // Recovery Mode
            .filterAll:                   "전체",
            .filterReady:                 "준비됨",
            .filterInstalling:            "설치 중",
            .filterInstalled:             "설치됨",
            .filterFailed:                "실패",
            .filterPending:               "대기 중",
            .installReadyProducts:        "준비된 제품 설치",
            .dropInstallersAbove:         "위에 인스톨러를 드롭하여 시작하세요",
            .recoveryComplete:            "복구 완료",
            .viewInLibrary:               "라이브러리에서 보기",
            .exitRecoveryMode:            "복구 모드 종료",
            .statDone:                    "완료",
            .statSkipped:                 "건너뜀",
            .statLimit:                   "제한",
            .statReinstalled:             "재설치됨",
            .statPending:                 "대기 중",
            // Recovery Slot
            .stateLimitReached:           "제한에 도달했습니다",
            .dropInstallerHere:           "여기에 인스톨러 드롭",
            .orLabel:                     "또는",
            .installAction:               "설치",
            // Subscription
            .backToSignIn:                "로그인으로 돌아가기",
            .reJoinAtlas:                 "ATLAS 재가입",
            .paymentFailed:               "결제 실패",
            .subscriptionRequired:        "구독이 필요합니다",
            .checkingEllipsis:            "확인 중…",
            .iveSubscribed:               "구독했습니다 — 새로 고침",
            .subscribeNow:                "지금 구독",
            .updateBilling:               "청구 정보 업데이트",
            .subBodyReJoin:               "구독이 만료되었습니다. ATLAS에 재가입하여 설치를 계속하세요.",
            .subBodyPayment:              "마지막 결제가 실패했습니다. 청구 정보를 업데이트하여 계속하세요.",
            .subBodyNew:                  "ATLAS를 구독하여 몇 초 만에 플러그인 설치를 시작하세요.",
            // Pro Feature Lock
            .proFeature:                  "ATLAS Subscription Feature",
            .proFeatureAvailOnFmt:        "%@ is available with an ATLAS subscription.",
            // ZIP Password
            .passwordRequired:            "비밀번호 필요",
            .filePasswordProtected:       "이 파일은 비밀번호로 보호되어 있습니다",
            .archivePassword:             "압축 파일 비밀번호",
            .enterPassword:               "비밀번호 입력",
            .rememberPassword:            "ATLAS는 이 제품의 향후 설치를 위해 이 비밀번호를 기억합니다.",
            .unlockAndInstall:            "잠금 해제 및 설치",
            // Rosetta
            .appleSiliconDetected:        "Apple Silicon 감지됨",
            .enableRosettaQ:              "Intel 플러그인을 로드하도록 DAW에서 Rosetta를 활성화하시겠습니까?",
            .scanningDAWs:                "설치된 DAW 검색 중...",
            .noDAWsFound:                 "이 Mac에서 DAW를 찾을 수 없습니다.",
            .selectDAWsRosetta:           "Rosetta를 활성화할 DAW 선택:",
            .rosettaEnabledMsg:           "선택한 DAW에 Rosetta가 활성화되었습니다. Intel 플러그인을 로드하려면 DAW를 재시작하세요.",
            .noThanks:                    "아니오, 괜찮습니다",
            .applying:                    "적용 중...",
            .enableRosettaAction:         "Rosetta 활성화",
            .alreadyEnabled:              "이미 활성화됨",
            // Storage/Library
            .available:                   "사용 가능",
            .total:                       "전체",
            .nothingToClean:              "정리할 항목 없음",
            .scanUnavailable:             "스캔 불가",
            .quickScan:                   "빠른 스캔",
            .overview:                    "개요",
            .disabled:                    "비활성화됨",
            .archived:                    "보관됨",
            .review:                      "검토",
            // Log View
            .fullLog:                     "전체 로그",
            .logSummary:                  "요약",
            .less:                        "접기",
            .logDetails:                  "세부 정보",
            .copied:                      "복사됨!",
            .copyLabel:                   "복사",
            // Recovery Kit
            .portableSnapshot:            "휴대용 설치 스냅샷",
            .generating:                  "생성 중…",
            .exportFailed:                "내보내기 실패",
            .generate:                    "생성",
            .cloudBackupLabel:            "클라우드 백업",
            .checking:                    "확인 중…",
            .notBackedUp:                 "백업되지 않음",
            .syncing:                     "동기화 중…",
            .restoring:                   "복원 중…",
            .loadRecoveryKit:             "Recovery Kit 불러오기",
            .openKitFile:                 ".atlaskit 파일 열기",
            .loading:                     "로딩 중…",
            .kitLoaded:                   "Kit 로드됨 — 복구 모드 진입 준비 완료",
            .fileRejected:                "파일 거부됨 — 변조되었거나 손상됨",
            .couldNotLoad:                "파일을 불러올 수 없습니다",
            .replace:                     "교체",
            .open:                        "열기",
            .crossMacKitNote:             "다른 Mac에서 내보낸 파일 — 모든 파일 경로는 참조용으로만 표시됩니다.",
            .hashMismatchNote:            "이 Recovery Kit 파일이 수정되었거나 손상되어 불러올 수 없습니다.",
            .beginRecovery:               "ATLAS 복구 시작",
            .recoveryModeProNote:         "Recovery Mode is an ATLAS subscription feature — ",
            .products:                    "제품",
            .update:                      "업데이트",
            .backUp:                      "백업",
            .retryCloudBackup:            "클라우드 백업 재시도",
            // TITAN VSCAN
            .detectedThreats:             "감지된 위협",
            .showLess:                    "적게 표시",
            .showAllFmt:                  "모두 표시 (%d)",
            .foundIn:                     "발견 위치",
            .continueInstall:             "설치 계속",
            .proceedWithInstall:          "설치 진행",
            .proceedAnyway:               "그래도 진행",
            .moveToQuarantine:            "격리로 이동",
            .deletePermanently:           "영구 삭제",
            .stripMalwareInstall:         "악성 소프트웨어 제거 후 설치",
            .vscanLicenseTip:             "이것은 라이선스 도구(keygen/patch)입니다. TITAN VSCAN™은 추가 악성 소프트웨어를 감지하지 못했습니다. 본인의 판단으로 진행하세요.",
            .vscanSuspiciousTip:          "비정상적인 패턴이 감지되었습니다. 정상적인 소프트웨어에서 발생하는 오탐지일 수 있습니다. 계속 진행하기 전에 위의 위협을 검토하세요.",
            .vscanMalwareTip:             "TITAN VSCAN™이 이 설치를 차단했습니다. 파일에 악성 소프트웨어가 포함되어 있어 안전하게 설치할 수 없습니다. 격리로 이동하거나 영구적으로 삭제하세요.",
            .vscanQuarantineConfirmMsg:   "파일이 ATLAS 보안 격리 폴더에 격리됩니다. 나중에 ATLAS 설정에서 검토하거나 영구적으로 삭제할 수 있습니다.",
            .vscanDeleteConfirmMsg:       "Mac에서 파일이 영구적으로 제거됩니다. 이 작업은 취소할 수 없습니다.",
            // Install Overlay
            .stillWorkingFmt:             "처리 중… %d초 경과",
            // Scan Result
            .keygenDetected:              "Keygen / 활성화 도구 감지됨",
            .windowsExe:                  "Windows 실행 파일",
            .keygenWarning:               "⚠ 경고: Keygen 파일이 감지되었습니다",
            .readyDropInstaller:          "준비됨 — Mac 인스톨러를 ATLAS에 드롭하여 계속",
            .dropNewFile:                 "새 파일 드롭",
            .imDoneReady:                 "완료 — 계속할 준비됨",
            .confirmationRequired:        "확인 필요",
            .contentsFound:               "콘텐츠 발견됨",
            .alreadyInstalled:            "이미 설치됨",
            .insufficientSpace:           "공간 부족",
            .cannotInstallAuto:           "자동으로 설치할 수 없습니다",
            .share:                       "공유",
            .installAction2:              "설치",
            // Summary Card
            .userActionRequired:          "사용자 조치 필요",
            .installerMovedToTrash:       "인스톨러가 휴지통으로 이동됨",
            .moveInstallerToTrash:        "인스톨러를 휴지통으로 이동",
            .backToHome:                  "홈으로 돌아가기",
            .removed:                     "제거됨",
            .supportFiles:                "지원 파일",
            .couldNotRemove:              "제거할 수 없었습니다",
            .filesMovedToTrash:           "파일이 휴지통으로 이동됨 — Finder에서 휴지통을 비워 공간을 확보하세요.",
            .recover:                     "복구",
            // Settings
            .appearance:                  "모양",
            .account:                     "계정",
            .supportLabel:                "지원",
            .tourAtlasTitle:              "ATLAS 투어",
            .replayWalkthrough:           "ATLAS 둘러보기 다시 재생",
            .tools:                       "도구",
            .fixBlockedPlugins:           "차단된 플러그인 수정",
            .removeSecurityBlocks:        "설치된 플러그인의 macOS 보안 차단 제거",
            .fix:                         "수정",
            .installLimits:               "설치 제한",
            .dailyInstallations:          "일일 설치 횟수",
            .monthlyInstallations:        "월간 설치 횟수",
            .resetsAtMidnight:            "자정에 초기화됨",
            .refillsOnBillingDate:        "청구일에 충전됨",
            .remainingTodayFmt:           "오늘 %d개 남음",
            .remainingThisMonthFmt:       "이번 달 %d개 남음",
            .notificationsLabel:          "알림",
            .installAlerts:               "설치 및 제거 알림",
            .notifOn:                     "켜짐 — 작업이 완료되면 알림을 받습니다",
            .notifOff:                    "꺼짐",
            .vscanSettingTitle:           "내장 바이러스 스캐너",
            .vscanSettingSubtitle:        "설치 전 인스톨러의 위협 요소 검사",
            .enableInSystemSettings:      "시스템 설정 → 알림에서 활성화",
            .storageLabel:                "저장 공간",
            .noVolumesFound:              "볼륨을 찾을 수 없음",
            .about:                       "정보",
            .viewLogs:                    "로그 보기",
            .openLogFolder:               "설치 및 제거 로그 폴더 열기",
            .signOutConfirmMsg:           "ATLAS를 사용하려면 다시 로그인해야 합니다.",
            .signOutTitle:                "ATLAS에서 로그아웃하시겠습니까?",
            // Support
            .getSupport:                  "지원 받기",
            .replyWithin24:               "24시간 이내에 답변 드립니다",
            .product:                     "제품",
            .issueType:                   "문제 유형",
            .describeIssue:               "문제를 설명해 주세요",
            .attachLog:                   "로그 첨부 (선택 사항)",
            .sendRequest:                 "지원 요청 보내기",
            .sending:                     "전송 중…",
            .thankYou:                    "감사합니다!",
            .requestReceived:             "지원 요청이 접수되었습니다.",
            .supportTeamReplyFmt:         "지원팀이 곧 연락 드립니다.\n%@에 24시간 이내로 답변 드리겠습니다.",
            .backToAtlas:                 "ATLAS로 돌아가기",
            // Cleaner
            .quickClean:                  "빠른 정리",
            .scanSystemForClutter:        "오디오 소프트웨어 잡동사니 시스템 스캔",
            .itemsMovedToTrashNote:       "항목이 macOS 휴지통으로 이동됩니다 — 영구적으로 삭제되지 않습니다.",
            .startScan:                   "스캔 시작",
            .scanning:                    "스캔 중",
            .selectAll:                   "모두 선택",
            .deselectAll:                 "모두 선택 해제",
            .cleanerTitle:                "ATLAS CLEANER™",
            .noCleanupFound:              "정리할 항목이 없습니다",
            .systemIsClean:               "시스템이 깨끗합니다",
            .noCleanerHistory:            "정리 기록이 없습니다",
            .cleanerHistory:              "정리 기록",
            .movingToTrash:               "휴지통으로 이동 중…",
            // Failure reasons
            .failReasonIncomplete:        "설치가 완료되지 않았습니다 — 파일이 올바르게 복사되지 않았을 수 있습니다.",
            .failReasonFilesNotLanded:    "일부 파일이 올바른 위치에 도달하지 못했습니다. 재설치를 시도해 보세요.",
            .failReasonAppNoLaunch:       "설치 후 앱이 실행되지 않았습니다. 수동으로 열어야 할 수 있습니다.",
            .failReasonAUNotRecognized:   "오디오 플러그인이 설치되었지만 DAW에서 아직 인식되지 않을 수 있습니다. 플러그인을 다시 스캔해 보세요.",
            .failReasonDamaged:           "플러그인 파일이 손상된 것 같습니다. 원본을 다시 다운로드해 보세요.",
            .failReasonVerifyFailed:      "ATLAS가 설치가 성공적으로 완료되었음을 확인할 수 없었습니다. 설치 로그를 확인하세요.",
            .failReasonConfidenceLow:     "ATLAS는 이 파일이 설치하기에 안전한지 확신하지 못했습니다. 다른 버전이나 소스를 시도해 보세요.",
            .failReasonScriptError:       "설치 스크립트에서 오류가 발생했습니다. 전체 출력은 설치 로그를 확인하세요.",
            .failReasonPkgFailed:         "패키지 인스톨러가 완료되지 않았습니다. 수동으로 실행해야 할 수 있습니다.",
            .failReasonCancelled:         "설치가 취소되었습니다.",
            .failReasonWaves:             "이 Waves 제품은 수동 설치 단계가 필요합니다. 로그를 참조하세요.",
            .failReasonGeneric:           "설치 중 문제가 발생했습니다. 설치 로그를 확인하세요.",
            // Demo warning
            .demoWarningLabel:            "설치됨 — 하지만 데모 또는 체험 모드로 실행될 수 있습니다. 제품을 확인하세요.",
            // Progress steps
            .progressScanningFile:        "파일 스캔 중…",
            .progressOpeningInstaller:    "인스톨러 열기…",
            .progressCopyingFiles:        "파일 복사 중…",
            .progressRunningInstaller:    "인스톨러 실행 중…",
            .progressRunningScript:       "설정 스크립트 실행 중…",
            .progressApplyingLicense:     "라이선스 설정 적용 중…",
            .progressVerifying:           "설치 확인 중…",
            .progressCheckingLicense:     "라이선스 상태 확인 중…",
            .progressSavingProfile:       "설치 프로필 저장 중…",
            .progressCleaningUp:          "정리 중…",
            .progressDone:                "완료.",
            .notifyRestoreCompleteTitle:  "복원 완료",
            .notifyRestoreFailedTitle:    "복원 실패",
            .notifyUninstallSuccessBody:  "%@이(가) 성공적으로 제거되었습니다.",
            .vscanQuarantineNotifBody:    "%@이(가) ATLAS 격리소로 이동되었습니다.",
            .vscanDeletedNotifBody:       "%@이(가) 영구 삭제되었습니다.",
            .quitInstallAlertTitle:       "설치 진행 중",
            .quitInstallAlertBody:        "ATLAS가 현재 설치를 진행 중입니다. 지금 종료하면 파일이 불완전한 상태로 남을 수 있습니다.\n\n정말 종료하시겠습니까?",
            .quitAnyway:                  "그래도 종료",
            .checkForUpdates:             "업데이트 확인",
            .menuOpenAtlas:               "ATLAS 열기",
            .menuQuitAtlas:               "ATLAS 종료",
            .fileShareNotifTitle:         "📦 새 파일 공유됨",
            .fileShareNotifBodyFmt:       "%@ (%@)이(가) 설치 준비되었습니다.",
            .notifyBatchUninstallTitle:   "세션 제거 완료",
            .atlasLibrary:                "ATLAS 라이브러리",
            .noInstallsYet:               "아직 설치 없음",
            .clearAll:                    "전체 지우기",
            .deleteAll:                   "전체 삭제",
            .formatsLabel:                "포맷",
            .signingLabel:                "서명 중…",
            .signedLabel:                 "서명됨!",
            .permanentlyDeleted:          "영구 삭제됨",
            .feedbackReceived:            "피드백 ✓",
            .filesPresent:                "파일 존재",
            .inTrash:                     "휴지통에 있음",
            .filesGone:                   "파일 없음",
            .unArchive:                   "보관 해제",
            .installedOnFmt:              "%@에 설치됨",
            .archivedOnFmt:               "%@에 보관됨",
            .archiveLabelFmt:             "보관함 (%d)",
            .sessionFmt:                  "세션 · %d · %@",
            .filesTrackedFmt:             "%d개 파일 추적 중",
            .receiptsAndFilesFmt:         "%d개 영수증 · %d개 파일",
            .uninstall:                   "제거",
            .remove:                      "삭제",
            .feedback:                    "피드백",
            .support:                     "지원",
            .sign:                        "서명",
            .enable:                      "활성화",
            .disable:                     "비활성화",
            .clearAtlasLibraryTitle:      "ATLAS 라이브러리를 비우시겠습니까?",
            .clearLibraryMsgFmt:          "모든 %d개의 설치 기록이 보관함으로 이동됩니다. 설치된 파일에는 영향이 없습니다. 언제든지 보관 해제할 수 있습니다.",
            .removeFromLibraryTitle:      "라이브러리에서 제거?",
            .removeRecordMsgFmt:          "'%@'이(가) 보관함으로 이동됩니다. 설치된 파일에는 영향이 없습니다.",
            .uninstallConfirmTitle:       "제거하시겠습니까?",
            .uninstallConfirmMsgFmt:      "ATLAS가 %@(%@에 의해 설치됨)을(를) 휴지통으로 이동합니다.%@\n\n휴지통에서 복구하거나 복구 버튼을 사용할 수 있습니다.",
            .disabledFormatsNoteFmt:      "\n\nATLAS 저장소에 %d개의 비활성화된 포맷도 포함됩니다.",
            .recoverFilesTitle:           "파일을 복구하시겠습니까?",
            .recoverFilesMsgFmt:          "ATLAS가 %@을(를) 제거할 때 휴지통으로 이동된 파일을 원래 위치로 되돌립니다.",
            .recoveryNotAvailable:        "복구 불가",
            .uninstallSessionTitle:       "세션을 제거하시겠습니까?",
            .uninstallSessionMsgFmt:      "ATLAS가 이 세션에서 %d개 항목을 제거합니다. 파일은 휴지통으로 이동됩니다.",
            .deleteArchivesTitle:         "보관함을 영구 삭제하시겠습니까?",
            .deleteArchivesMsg:           "ATLAS 라이브러리에서 보관된 모든 프로그램 기록이 영구 삭제됩니다. 이 작업은 취소할 수 없습니다.\n\n기존 로그는 삭제되지 않습니다.",
            .deleteAllArchivesBtn:        "모든 보관함 삭제",
            .deleteArchiveTitle:          "보관 기록을 삭제하시겠습니까?",
            .deleteArchiveMsgFmt:         "이렇게 하면 보관 기록에서 '%@'이(가) 영구 삭제됩니다. 디스크의 파일에는 영향이 없습니다.",
            .disableFmtConfirmTitleFmt:   "%@ 비활성화?",
            .disableFmtConfirmMsgFmt:     "ATLAS가 %@ (%@)을(를) 플러그인 폴더에서 이동합니다. 다시 활성화할 때까지 DAW에 표시되지 않습니다.\n\nATLAS 라이브러리에서 언제든지 다시 활성화할 수 있습니다.",
            .proFeatureAlertTitleFmt:     "%@ — ATLAS Feature",
            .proFeatureAlertMsgFmt:       "%@ is available with an ATLAS subscription.\n\nVisit interlinked.digital/account and sign in with the same email you use in the ATLAS app.",
        ],
    ]
}
