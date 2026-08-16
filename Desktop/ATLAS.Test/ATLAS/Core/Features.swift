import Foundation

enum Features {
    static var isPro: Bool { AuthManager.shared.isPro }

    static var bulkInstall:    Bool { isPro }
    static var rollback:       Bool { isPro }
    static var restore:        Bool { isPro }
    static var titanCore:      Bool { true }   // both plans
    static var smartStorage:   Bool { true }   // both plans
    static var fullHistory:    Bool { isPro }
    static var pluginScanner:  Bool { isPro }
    static var trashInstaller: Bool { isPro }
    static var titanVScan:     Bool { isPro }
    static var fileShare:      Bool { false }  // Coming Soon — Pro only when released
    static var enableDisable:  Bool { isPro }  // ATLAS Library: Enable/Disable plugin formats
    static var codeSign:       Bool { isPro }  // ATLAS Library: Code-Sign plugin formats

    // New pipeline: PackageManifest → WorkflowRecognizer → RecipeComposer → InstallPlan.
    // Off by default — existing analyze() path runs unchanged when false.
    // Toggle to true to validate new pipeline output against known packages.
    static var titanPipeline: Bool { false }

    static var atlasCleanerEnabled:    Bool { isPro }
    static var recoveryKitEnabled:      Bool { isPro }   // generation only
    static var recoveryKitImportEnabled: Bool { true }  // all plans
    static var recoveryModeEnabled:     Bool { isPro }  // reinstallation via Recovery Mode
    static var cloudRecoveryKit:        Bool { isPro }  // cloud backup/restore

    static let standardHistoryLimit = 5

    static var monthlyInstallLimit: Int {
        isPro ? MonthlyLimitManager.proLimit : MonthlyLimitManager.standardMonthlyLimit
    }
}
