import Foundation

public enum Provider: Sendable, Hashable, CaseIterable {
    case claude
    case codex
    case cursor
}

public struct PanelState: Sendable, Equatable {
    /// The magnitude every quota value in the panel is expressed in.
    public var magnitude: QuotaMagnitude
    public var cards: [Card]
    /// A query is in flight. Each card still changes as soon as its own
    /// result arrives.
    public var isQuerying: Bool

    public init(magnitude: QuotaMagnitude, cards: [Card], isQuerying: Bool = false) {
        self.magnitude = magnitude
        self.cards = cards
        self.isQuerying = isQuerying
    }
}

public enum QuotaMagnitude: String, Sendable, Equatable {
    case used
    case remaining
}

public struct Card: Sendable, Equatable {
    public let provider: Provider
    public var content: CardContent
    /// The banked resets the account holds, from the same query as the
    /// card's fresh quotas. `nil` when there are none to show: the provider
    /// sent no positive count, or the card has no fresh quotas.
    public var bankedResets: Int?
    /// The name of the account's plan, as the provider names it, e.g.
    /// "Max". From the same query as the card's quotas, fresh or stale.
    /// `nil` when the card shows no quotas, or the provider reported no plan
    /// Uzzy knows: it is never guessed.
    public var plan: String?

    public init(provider: Provider, content: CardContent, bankedResets: Int? = nil, plan: String? = nil) {
        self.provider = provider
        self.content = content
        self.bankedResets = bankedResets
        self.plan = plan
    }
}

public enum CardContent: Sendable, Equatable {
    /// No valid reading yet.
    case loading
    /// The session now belongs to another account. The previous account's
    /// reading is gone, and the new account's quotas are being queried.
    case loadingNewAccount
    case quotas([Quota])
    /// The last valid reading of the same account, kept after a failed query.
    /// Its quotas are stale and keep the time of their query.
    case stale([Quota], failure: Failure)
    /// The card has no quotas to show, and this is why.
    case failed(Failure)
}

/// Why a card has no quotas to show, or only stale ones.
public enum Failure: Error, Sendable, Equatable {
    /// The official app has no session on this Mac.
    case noSession
    /// The official app's session is of a kind that has no subscription
    /// quotas, e.g. signed in with an API key.
    case sessionWithoutSubscriptionQuotas
    /// The user denied access to the session (the Keychain prompt).
    case sessionAccessDenied
    /// The Keychain or another provider session store could not be read.
    case sessionStoreUnavailable
    /// The provider's session store is currently locked.
    case sessionStoreBusy
    /// The session is stored in a format the app does not know. The
    /// credential is never shown.
    case incompatibleSession
    /// The provider rejected the session (401): it has to be renewed in the
    /// official app.
    case sessionExpired
    /// The provider refused the query (403). It may be a restriction other
    /// than the session, so it is not taken as an expired session.
    case accessRefused
    /// The provider rejected (401 or 403) the session reused by a query no
    /// user action asked for. The official app may have renewed it since it
    /// was read, so it is not called expired; the next user action checks it.
    case reusedSessionRejected
    /// The provider could not be reached: the network is down.
    case offline
    /// The provider did not answer within the time limit.
    case timedOut
    /// The provider failed to answer the query (5xx).
    case serverError(status: Int)
    /// The provider received too many queries (429). No query is made
    /// before `until`, the time it asked to wait for, if it said.
    case rateLimited(until: Date?)
    /// The provider answered with something the app does not understand, e.g.
    /// because it changed its format. No alternative route is tried.
    case incompatibleResponse
    /// The provider's response was larger than any valid answer can be, so
    /// it was dropped without being decoded. The card explains it as an incompatible
    /// response; the log keeps it apart.
    case responseTooLarge
    /// Cursor sent a billing-cycle reset in an unsupported format.
    case incompatibleResetFormat
}

/// A subscription quota, independent of the provider's other quotas.
public struct Quota: Sendable, Equatable {
    public let period: QuotaPeriod
    public let value: QuotaValue
    /// Nil when the quota has no reset at all, so none is shown.
    public let reset: Reset?
    /// When the query that produced this value was made.
    public let readAt: Date
    /// The value no longer confirms the current quota: a later query failed,
    /// or the reset passed without a new reading.
    public let isStale: Bool

    public init(period: QuotaPeriod, value: QuotaValue, reset: Reset?, readAt: Date, isStale: Bool = false) {
        self.period = period
        self.value = value
        self.reset = reset
        self.readAt = readAt
        self.isStale = isStale
    }
}

public enum QuotaPeriod: Sendable, Hashable {
    case fiveHours
    case weekly
    /// A period of another length, named by that length.
    case lasting(seconds: Int)
    /// The subscription's billing cycle, as long as the provider says.
    case billingCycle
    /// A limit the provider sends separately and names, e.g. of a single
    /// model ("Sonnet") or a quota bag ("Cursor Models"), over `period`.
    indirect case limit(String, QuotaPeriod)
    /// Claude's usage credits spent this month. Not a subscription quota but
    /// a deliberate exception shown among them, named on its own. The
    /// provider sends no period boundary or reset for it, so it has none.
    case usageCredits
}

/// A quota's value in the panel's magnitude.
public enum QuotaValue: Sendable, Equatable {
    /// A 0–100 percentage. `calculated` when derived rather than reported by
    /// the provider.
    case percent(Double, calculated: Bool)
    /// The provider reported a negative, over-100 or contradictory figure.
    /// It is not clamped or corrected, and nothing is calculated from it.
    case uninterpretable
    /// The provider did not report this quota. Never taken as zero.
    case unavailable
    /// Money spent this month and the monthly spend limit, if there is one.
    /// Not a percentage: it is the same in either magnitude, and spending
    /// past the limit is shown as it is.
    case spend(Money, limit: Money?)
}

/// An exact amount of money, e.g. 53.06 US dollars.
public struct Money: Sendable, Equatable {
    /// In the currency's major units.
    public let amount: Decimal
    /// The currency's ISO 4217 code, e.g. "USD".
    public let currency: String

    public init(amount: Decimal, currency: String) {
        self.amount = amount
        self.currency = currency
    }
}

extension Money {
    /// `minorUnits` of `currency`, e.g. 5306 cents of "USD", using the
    /// currency's own number of minor-unit digits. Nil for a negative amount
    /// or a code that is not a current ISO 4217 currency, so no currency is
    /// ever guessed.
    init?(minorUnits: Int, currency: String) {
        guard minorUnits >= 0, Locale.commonISOCurrencyCodes.contains(currency) else { return nil }
        let format = NumberFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.numberStyle = .currency
        format.currencyCode = currency
        self.init(
            amount: Decimal(sign: .plus, exponent: -format.maximumFractionDigits, significand: Decimal(minorUnits)),
            currency: currency
        )
    }
}

public enum Reset: Sendable, Equatable {
    /// Still ahead.
    case at(Date)
    /// The provider gave no valid date. Never inferred from the period.
    case unknown
    /// The reset passed without a new reading, so the quota's figure no longer
    /// confirms the current quota.
    case pendingConfirmation
}
