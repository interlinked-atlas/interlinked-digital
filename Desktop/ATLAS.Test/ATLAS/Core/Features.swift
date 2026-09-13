import Foundation

enum Features {
    static var isSubscribed: Bool { AuthManager.shared.isSubscribed }
    static var isPro: Bool { isSubscribed }  // backward compat alias

    static var bulkInstall:    Bool { isSubscribed }
    static var rollback:       Bool { isSubscribed }
    static var restore:        Bool { isSubscribed }
    static var titanCore:      Bool { true }
    static var smartStorage:   Bool { true }
    static var fullHistory:    Bool { isSubscribed }
    static var pluginScanner:  Bool { isSubscribed }
    static var trashInstaller: Bool { isSubscribed }
    static var titanVScan:     Bool { isSubscribed }
    static var fileShare:      Bool { false }  // Coming Soon
    static var enableDisable:  Bool { isSubscribed }
    static var codeSign:       Bool { isSubscribed }

    static var titanPipeline: Bool { false }

    static var atlasCleanerEnabled:     Bool { isSubscribed }
    static var recoveryKitEnabled:      Bool { isSubscribed }
    static var recoveryKitImportEnabled: Bool { true }
    static var recoveryModeEnabled:     Bool { isSubscribed }
    static var cloudRecoveryKit:        Bool { isSubscribed }

    static var monthlyInstallLimit: Int { MonthlyLimitManager.atlasMonthlyLimit }
}
