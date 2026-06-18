import Foundation

// MARK: - Feature Gates

enum Features {
    static var isPro: Bool      { AuthManager.shared.isPro }
    static var isAdvanced: Bool { AuthManager.shared.isAdvanced }

    static var bulkInstall:   Bool { isPro }
    static var rollback:      Bool { isPro }
    static var restore:       Bool { isPro }
    static var titanCore:     Bool { true }
    static var smartStorage:  Bool { isPro }
    static var fullHistory:   Bool { isPro }
    static var pluginScanner: Bool { isPro }

    static let standardHistoryLimit = 5

    static var monthlyInstallLimit: Int {
        if isAdvanced { return MonthlyLimitManager.advancedLimit }
        if isPro      { return MonthlyLimitManager.proLimit }
        return MonthlyLimitManager.standardLimit
    }
}
