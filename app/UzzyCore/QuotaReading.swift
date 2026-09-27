import Foundation

/// A quota as the provider reported it, before the presentation rules apply.
///
/// A provider may report the same quota more than once. Every copy is kept so
/// that copies that disagree can be told apart from a single figure.
struct QuotaReading: Sendable, Equatable {
    let period: QuotaPeriod
    private let figures: Figures
    let readAt: Date

    /// What the provider reported for the quota.
    private enum Figures: Sendable, Equatable {
        /// Every used percentage and every reset date reported, unchecked.
        /// No percentage when the quota was not reported; text that is not a
        /// date is left out of the resets.
        case usedPercents([Double], resets: [Date])
        /// Money spent and its limit, already checked. It has no reset.
        case spend(Money, limit: Money?)
    }

    init(period: QuotaPeriod, usedPercents: [Double], resets: [Date], readAt: Date) {
        self.period = period
        figures = .usedPercents(usedPercents, resets: resets)
        self.readAt = readAt
    }

    /// Claude's usage credits spent this month, and their monthly limit.
    init(usageCreditsSpent spent: Money, limit: Money?, readAt: Date) {
        period = .usageCredits
        figures = .spend(spent, limit: limit)
        self.readAt = readAt
    }

    /// Copies of a figure that differ by more than this contradict each other.
    /// It matches the precision the figures are checked against.
    static let percentAgreement = 1.0
    static let resetAgreement: TimeInterval = 60
    /// A reset further than this from the reading, in either direction, is
    /// not a date the quota can have. A year, leap years included.
    static let maxResetDistance: TimeInterval = 366 * 86_400

    /// `stale` when a later query failed. A reset that passed without a new
    /// reading makes the figure stale too.
    func quota(in magnitude: QuotaMagnitude, at now: Date, stale: Bool = false) -> Quota {
        let reset = reset(at: now)
        return Quota(
            period: period,
            value: value(in: magnitude),
            reset: reset,
            readAt: readAt,
            isStale: stale || reset == .pendingConfirmation
        )
    }

    /// Nil for money spent, which has no reset at all.
    private func reset(at now: Date) -> Reset? {
        guard case .usedPercents(_, let resets) = figures else { return nil }
        guard let reset = resets.first,
              resets.allSatisfy({ abs($0.timeIntervalSince(readAt)) <= Self.maxResetDistance }),
              resets.allSatisfy({ abs($0.timeIntervalSince(reset)) <= Self.resetAgreement })
        else { return .unknown }
        return reset > now ? .at(reset) : .pendingConfirmation
    }

    private func value(in magnitude: QuotaMagnitude) -> QuotaValue {
        let usedPercents: [Double]
        switch figures {
        case .spend(let spent, let limit): return .spend(spent, limit: limit)
        case .usedPercents(let percents, _): usedPercents = percents
        }
        guard let usedPercent = usedPercents.first else { return .unavailable }
        guard usedPercents.allSatisfy({ $0.isFinite && (0...100).contains($0) }),
              usedPercents.allSatisfy({ abs($0 - usedPercent) <= Self.percentAgreement })
        else { return .uninterpretable }
        return switch magnitude {
        case .used: .percent(usedPercent, calculated: false)
        case .remaining: .percent(100 - usedPercent, calculated: true)
        }
    }
}
