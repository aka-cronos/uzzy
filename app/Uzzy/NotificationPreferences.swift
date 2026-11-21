import Foundation
import UzzyCore

/// Background refresh and the alerts it can fire. Everything is off until
/// the person turns it on in Settings. Only choices are stored: never
/// quotas, tokens or account data.
enum NotificationPreferences {
    static let backgroundRefreshKey = "backgroundRefresh"
    /// In minutes.
    static let intervalKey = "backgroundRefreshInterval"
    static let nearLimitKey = "alertNearLimit"
    /// A used percentage.
    static let thresholdKey = "alertThreshold"
    static let limitReachedKey = "alertLimitReached"
    static let limitResetKey = "alertLimitReset"

    static let defaultIntervalMinutes = Int(BackgroundRefresh.defaultInterval / 60)
    static let defaultThreshold = Int(AlertSettings.defaultThreshold)

    static func backgroundRefresh(in defaults: UserDefaults) -> BackgroundRefresh {
        BackgroundRefresh(isOn: defaults.bool(forKey: backgroundRefreshKey), interval: interval(in: defaults))
    }

    /// The saved interval, if Settings offers it; the default otherwise.
    static func interval(in defaults: UserDefaults) -> TimeInterval {
        let minutes = defaults.object(forKey: intervalKey) as? Int ?? defaultIntervalMinutes
        let interval = TimeInterval(minutes * 60)
        return BackgroundRefresh.intervals.contains(interval) ? interval : BackgroundRefresh.defaultInterval
    }

    static func alerts(in defaults: UserDefaults) -> AlertSettings {
        AlertSettings(
            nearLimit: defaults.bool(forKey: nearLimitKey),
            threshold: threshold(in: defaults),
            limitReached: defaults.bool(forKey: limitReachedKey),
            limitReset: defaults.bool(forKey: limitResetKey)
        )
    }

    /// The saved threshold, if Settings offers it; the default otherwise.
    static func threshold(in defaults: UserDefaults) -> Double {
        let threshold = Double(defaults.object(forKey: thresholdKey) as? Int ?? defaultThreshold)
        return AlertSettings.thresholds.contains(threshold) ? threshold : AlertSettings.defaultThreshold
    }
}
