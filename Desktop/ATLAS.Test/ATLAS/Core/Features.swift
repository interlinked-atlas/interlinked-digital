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
    static var widget:         Bool { isPro }
    static var trashInstaller: Bool { isPro }
    static var fileShare:      Bool { false }  // Coming Soon — Pro only when released

    static let standardHistoryLimit = 5

    static var monthlyInstallLimit: Int {
        isPro ? MonthlyLimitManager.proLimit : MonthlyLimitManager.standardLimit
    }
}
