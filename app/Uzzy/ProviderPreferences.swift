import Foundation
import UzzyCore

/// Which providers have a card, and the cards' order. Only provider
/// identifiers are stored: never quotas, tokens or account data.
enum ProviderPreferences {
    static let claudeKey = "showClaude"
    static let codexKey = "showCodex"
    static let cursorKey = "showCursor"
    static let orderKey = "providerOrder"

    static func enabledProviders(in defaults: UserDefaults) -> Set<Provider> {
        Set(Provider.allCases.filter { provider in
            let key = switch provider {
            case .claude: claudeKey
            case .codex: codexKey
            case .cursor: cursorKey
            }
            return defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
        })
    }

    static func order(in defaults: UserDefaults) -> [Provider] {
        Provider.order(restoring: defaults.object(forKey: orderKey))
    }

    static func save(_ order: [Provider], in defaults: UserDefaults) {
        defaults.set(order.map(\.identifier), forKey: orderKey)
    }
}
