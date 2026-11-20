import Foundation

/// A quota as the provider reported it, before the presentation rules apply.
///
/// A provider may report the same quota more than once. Every copy is kept so
/// that copies that disagree can be told apart from a single figure.
struct QuotaReading: Sendable, Equatable {
    let period: QuotaPeriod
    private let figures: Figures
    let readAt: Date
    /// The window starts on its first use, as the provider runs it, rather
    /// than on a schedule. Only then can an unused window have no reset.
    private let startsOnFirstUse: Bool
    /// How far an unused window's moving reset may be from the reading moment
    /// plus the period's length.
    private let unstartedWindowAgreement: TimeInterval

    /// What the provider reported for the quota.
    private enum Figures: Sendable, Equatable {
        /// Every used percentage and every reset date reported, unchecked.
        /// No percentage when the quota was not reported; text that is not a
        /// date is left out of the resets.
        case usedPercents([Double], resets: [Date])
        /// Money spent and its limit, already checked. It has no reset.
        case spend(Money, limit: Money?)
    }

    init(
        period: QuotaPeriod,
        usedPercents: [Double],
        resets: [Date],
        readAt: Date,
        startsOnFirstUse: Bool = false,
        unstartedWindowAgreement: TimeInterval = QuotaReading.unstartedWindowAgreement
    ) {
        self.period = period
        figures = .usedPercents(usedPercents, resets: resets)
        self.readAt = readAt
        self.startsOnFirstUse = startsOnFirstUse
        self.unstartedWindowAgreement = unstartedWindowAgreement
    }

    /// Claude's usage credits spent this month, and their monthly limit.
    init(usageCreditsSpent spent: Money, limit: Money?, readAt: Date) {
        period = .usageCredits
        figures = .spend(spent, limit: limit)
        self.readAt = readAt
        startsOnFirstUse = false
        unstartedWindowAgreement = Self.unstartedWindowAgreement
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

    /// How far a reported reset may be from the reading moment plus the
    /// period's length and still be that moving date. It covers the query's
    /// latency, a summary the provider cached and a clock slightly out of
    /// step with the provider's.
    static let unstartedWindowAgreement: TimeInterval = 5 * 60

    /// Nil for money spent, which has no reset at all, and for a window that
    /// has not started.
    private func reset(at now: Date) -> Reset? {
        guard case .usedPercents(let usedPercents, let resets) = figures else { return nil }
        if hasNotStarted(usedPercents: usedPercents, resets: resets) { return nil }
        guard let reset = resets.first,
              resets.allSatisfy({ abs($0.timeIntervalSince(readAt)) <= Self.maxResetDistance }),
              resets.allSatisfy({ abs($0.timeIntervalSince(reset)) <= Self.resetAgreement })
        else { return .unknown }
        return reset > now ? .at(reset) : .pendingConfirmation
    }

    /// A window that starts on its first use is unused until then, and the
    /// provider reports the reading moment plus the window's length as its
    /// reset: a date that moves with every query, so it is not a reset.
    /// Only periods of a fixed length can tell. A scheduled window, such as
    /// a billing cycle or Cursor's included week, always has a real reset.
    private func hasNotStarted(usedPercents: [Double], resets: [Date]) -> Bool {
        guard startsOnFirstUse, let length = period.length, !usedPercents.isEmpty, usedPercents.allSatisfy({ $0 == 0 }), !resets.isEmpty
        else { return false }
        let movingReset = readAt.addingTimeInterval(length)
        return resets.allSatisfy { abs($0.timeIntervalSince(movingReset)) <= unstartedWindowAgreement }
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

extension QuotaPeriod {
    /// The period's fixed length. Nil for a billing cycle, whose length the
    /// provider decides, and for usage credits, which have no period.
    var length: TimeInterval? {
        switch self {
        case .fiveHours: 5 * 3_600
        case .weekly: 7 * 86_400
        case .lasting(let seconds): TimeInterval(seconds)
        case .limit(_, let period): period.length
        case .billingCycle, .usageCredits: nil
        }
    }
}
