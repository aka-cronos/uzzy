import Foundation

/// Whether Uzzy asks GitHub for a newer version. On until the person turns
/// it off in Settings.
enum UpdatePreferences {
    static let checkKey = "checkForUpdates"

    static func checksForUpdates(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: checkKey) == nil || defaults.bool(forKey: checkKey)
    }
}
