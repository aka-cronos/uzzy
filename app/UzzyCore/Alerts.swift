import Foundation

/// Whether providers are also queried while the panel is closed, and how
/// often. Off by default: with it off, closing the panel stops every query.
public struct BackgroundRefresh: Sendable, Equatable {
    public var isOn: Bool
    /// Between two queries while the panel is closed. Never under
    /// `shortestInterval`, to spare the providers' endpoints and the battery.
    public var interval: TimeInterval {
        didSet { interval = max(interval, Self.shortestInterval) }
    }

    /// The intervals Settings offers: 5, 10, 15 and 30 minutes.
    public static let intervals: [TimeInterval] = [5, 10, 15, 30].map { $0 * 60 }
    public static let defaultInterval: TimeInterval = 15 * 60
    public static let shortestInterval: TimeInterval = 5 * 60
    public static let off = BackgroundRefresh(isOn: false)

    public init(isOn: Bool, interval: TimeInterval = BackgroundRefresh.defaultInterval) {
        self.isOn = isOn
        self.interval = max(interval, Self.shortestInterval)
    }
}

/// Which alerts the person turned on. All off by default; they only fire
/// while background refresh is on and the panel is closed.
public struct AlertSettings: Sendable, Equatable {
    /// A subscription quota crosses `threshold` without reaching 100%.
    public var nearLimit: Bool
    /// The used percentage, of every turned-on provider, that counts as
    /// near the limit.
    public var threshold: Double
    /// A subscription quota reaches 100% used.
    public var limitReached: Bool
    /// A subscription quota that reached 100% is confirmed reset.
    public var limitReset: Bool

    /// The thresholds Settings offers, as used percentages.
    public static let thresholds: [Double] = [80, 85, 90, 95]
    public static let defaultThreshold: Double = 80
    public static let off = AlertSettings()

    public init(
        nearLimit: Bool = false,
        threshold: Double = AlertSettings.defaultThreshold,
        limitReached: Bool = false,
        limitReset: Bool = false
    ) {
        self.nearLimit = nearLimit
        self.threshold = threshold
        self.limitReached = limitReached
        self.limitReset = limitReset
    }

    public var isAnyOn: Bool {
        nearLimit || limitReached || limitReset
    }

    func allows(_ alert: UsageAlert) -> Bool {
        switch alert {
        case .nearLimit: nearLimit
        case .limitReached: limitReached
        case .limitReset: limitReset
        }
    }
}

/// Something worth telling the person about a subscription quota while the
/// panel is closed. Only for quotas with a percentage: never usage credits,
/// credit balances or cloud-session credits.
public enum UsageAlert: Sendable, Equatable {
    /// `usedPercent` is the reading's own figure, not the threshold. `reset`
    /// is `nil` when the quota has no known reset ahead.
    case nearLimit(Provider, period: QuotaPeriod, usedPercent: Double, reset: Date?)
    /// The quota reached 100% used.
    case limitReached(Provider, period: QuotaPeriod, reset: Date?)
    /// A fresh reading of the same account confirmed that a quota at 100%
    /// reset.
    case limitReset(Provider, period: QuotaPeriod)

    public var provider: Provider {
        switch self {
        case .nearLimit(let provider, _, _, _), .limitReached(let provider, _, _), .limitReset(let provider, _): provider
        }
    }
}

/// A subscription quota of a fresh reading, as the alerts see it.
struct AlertQuota: Sendable, Equatable {
    let period: QuotaPeriod
    let usedPercent: Double
    let reset: Reset?

    /// The reset still ahead, if the provider gave a valid one.
    var resetDate: Date? {
        if case .at(let date) = reset { date } else { nil }
    }

    var isLimited: Bool {
        usedPercent >= 100
    }

    /// The name of the model, group or bag a named limit covers, or `nil`
    /// for a limit on the whole account, such as the 5-hour or weekly one.
    var scope: String? {
        if case .limit(let name, _) = period { name } else { nil }
    }

    /// Whether `other`, another quota of the same reading, still stops this
    /// one from being used: it is at 100% and covers this quota's scope.
    /// A limit on the whole account covers every scope; a named limit only
    /// its own name.
    func isBlocked(by other: AlertQuota) -> Bool {
        other.period != period && other.isLimited && (other.scope == nil || other.scope == scope)
    }

    /// The earliest reset, among the limited `quotas`, after which a quota
    /// can be used again: a limited quota whose reset comes before another
    /// limited quota blocking it would still be blocked then. `nil` when no
    /// such reset is known.
    static func earliestUsableReset(of quotas: [AlertQuota]) -> Date? {
        let limited = quotas.filter(\.isLimited)
        return limited.compactMap { quota -> Date? in
            guard let reset = quota.resetDate else { return nil }
            let outlasted = limited.contains { other in
                guard quota.isBlocked(by: other) else { return false }
                guard let otherReset = other.resetDate else { return true }
                return otherReset.timeIntervalSince(reset) > QuotaReading.resetAgreement
            }
            return outlasted ? nil : reset
        }.min()
    }
}

/// Decides which alerts a fresh reading fires, and remembers which ones
/// fired so each fires once per reset window. Pure: it never notifies or
/// schedules anything itself.
struct AlertTracker {
    /// What the tracker remembers about one quota.
    private struct Window {
        var usedPercent: Double
        /// The last reset ahead the provider gave; it tells windows apart.
        var resetAt: Date?
        var nearLimitFired: Bool
        var limitReachedFired: Bool
        /// The quota was at 100%, and no fresh reading has confirmed its
        /// reset yet.
        var awaitsReset: Bool
    }

    private struct Account {
        let accountID: String
        var windows: [QuotaPeriod: Window]
    }

    private var accounts: [Provider: Account] = [:]
    private(set) var threshold: Double

    init(threshold: Double) {
        self.threshold = threshold
    }

    /// The alerts that `quotas`, a fresh reading of `accountID`, fires. The
    /// first reading of a provider, of another account or of a quota not
    /// seen before only sets the baseline: what is already over the
    /// threshold or at 100% fires nothing. A reading whose account cannot be
    /// verified belongs to no one, so it fires nothing and forgets the
    /// provider.
    mutating func observe(_ provider: Provider, accountID: String?, quotas: [AlertQuota]) -> [UsageAlert] {
        guard let accountID, !accountID.isEmpty else {
            accounts[provider] = nil
            return []
        }
        guard let account = accounts[provider], account.accountID == accountID else {
            accounts[provider] = Account(accountID: accountID, windows: baseline(of: quotas))
            return []
        }
        var alerts: [UsageAlert] = []
        var windows: [QuotaPeriod: Window] = [:]
        for quota in quotas {
            guard var window = account.windows[quota.period] else {
                windows[quota.period] = baseline(of: quota)
                continue
            }
            let advanced = window.resetAt.flatMap { last in
                quota.resetDate.map { $0.timeIntervalSince(last) > QuotaReading.resetAgreement }
            } ?? false
            // A reset that passed without a new reading confirms nothing.
            if window.awaitsReset, quota.reset != .pendingConfirmation, !quota.isLimited || advanced {
                // Another limit at 100% still stops the provider from being
                // used, so its reset is the one that fires.
                if !quotas.contains(where: quota.isBlocked(by:)) {
                    alerts.append(.limitReset(provider, period: quota.period))
                }
                window.awaitsReset = false
            }
            if advanced {
                window.nearLimitFired = false
                window.limitReachedFired = false
            }
            if quota.usedPercent < threshold { window.nearLimitFired = false }
            if !quota.isLimited { window.limitReachedFired = false }
            if quota.isLimited {
                if !window.limitReachedFired {
                    alerts.append(.limitReached(provider, period: quota.period, reset: quota.resetDate))
                    window.limitReachedFired = true
                }
                // Jumping straight to 100% fires only the limit reached.
                window.nearLimitFired = true
                window.awaitsReset = true
            } else if quota.usedPercent >= threshold, !window.nearLimitFired {
                alerts.append(.nearLimit(provider, period: quota.period, usedPercent: quota.usedPercent, reset: quota.resetDate))
                window.nearLimitFired = true
            }
            window.usedPercent = quota.usedPercent
            if let resetAt = quota.resetDate { window.resetAt = resetAt }
            windows[quota.period] = window
        }
        accounts[provider] = Account(accountID: accountID, windows: windows)
        return alerts
    }

    /// A turned-off provider starts over when it is turned on again.
    mutating func forget(_ provider: Provider) {
        accounts[provider] = nil
    }

    mutating func forgetAll() {
        accounts = [:]
    }

    /// The near-limit alerts start over against the new threshold, and what
    /// is already over it fires nothing.
    mutating func setThreshold(_ threshold: Double) {
        guard threshold != self.threshold else { return }
        self.threshold = threshold
        for (provider, var account) in accounts {
            for (period, var window) in account.windows {
                window.nearLimitFired = window.usedPercent >= threshold
                account.windows[period] = window
            }
            accounts[provider] = account
        }
    }

    private func baseline(of quotas: [AlertQuota]) -> [QuotaPeriod: Window] {
        var windows: [QuotaPeriod: Window] = [:]
        for quota in quotas {
            windows[quota.period] = baseline(of: quota)
        }
        return windows
    }

    private func baseline(of quota: AlertQuota) -> Window {
        Window(
            usedPercent: quota.usedPercent,
            resetAt: quota.resetDate,
            nearLimitFired: quota.usedPercent >= threshold,
            limitReachedFired: quota.isLimited,
            awaitsReset: quota.isLimited
        )
    }
}
