import Foundation
import Observation

/// How a provider plugs into the core: its usage query, and the translation
/// of its answer into quotas.
protocol ProviderAdapter {
    static var provider: Provider { get }
    static func request(for session: Session) -> URLRequest
    /// Returns a specific failure when the response cannot be translated.
    static func quotas(from body: Data, readAt moment: Date) -> Result<[QuotaReading], Failure>
    /// The banked resets in a response whose quotas were read, if it holds
    /// a positive count. Never fails the reading.
    static func bankedResets(from body: Data) -> Int?
    /// The name of the account's plan, from the session a query used or the
    /// response whose quotas were read. `nil` when they report no plan the
    /// adapter knows. Never fails the reading.
    static func plan(of session: Session, response body: Data) -> String?
}

extension ProviderAdapter {
    static func bankedResets(from body: Data) -> Int? {
        nil
    }
}

/// The refresh of a single provider: its session, its queries, its retry
/// wait and what its card shows. Providers share no credentials or failure
/// state, so one failing never affects another.
@MainActor
@Observable
final class ProviderRefresh {
    let provider: Provider
    private(set) var isEnabled: Bool

    var isQuerying: Bool {
        query != nil
    }

    private var reading = ProviderReading.loading
    private var query: Task<Void, Never>?
    @ObservationIgnored private var queryID: UUID?
    /// A cancelled query may still be unwinding after a provider is enabled
    /// again. Keeping it here also lets the test seam await its completion.
    @ObservationIgnored private var retiredQueries: [UUID: Task<Void, Never>] = [:]
    /// The last session read on a user action, reused by the queries no user
    /// action asked for. `nil` when that read gave no usable session.
    @ObservationIgnored private var session: Session?
    /// Retries are only scheduled while the panel is open.
    @ObservationIgnored private var isPanelOpen = false
    @ObservationIgnored private var wait = RetryWait()
    /// The only scheduled retry. `nil` while the panel is closed or no wait
    /// is pending; replacing it cancels the one before.
    @ObservationIgnored private var scheduledRetry: ScheduledWork? {
        didSet { oldValue?.cancel() }
    }

    private let adapter: any ProviderAdapter.Type
    private let sessionReader: any SessionReader
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private let log: any EventLog

    init(
        _ adapter: any ProviderAdapter.Type,
        sessionReader: any SessionReader,
        transport: any HTTPTransport,
        clock: any WallClock,
        log: any EventLog,
        isEnabled: Bool = true
    ) {
        provider = adapter.provider
        self.isEnabled = isEnabled
        self.adapter = adapter
        self.sessionReader = sessionReader
        self.transport = transport
        self.clock = clock
        self.log = log
    }

    func content(in magnitude: QuotaMagnitude, at now: Date) -> CardContent {
        reading.content(in: magnitude, at: now)
    }

    /// Only with fresh quotas: a failed query hides them even while the
    /// same account's quotas are shown stale.
    var bankedResets: Int? {
        guard case .quotas(let reading) = reading else { return nil }
        return reading.bankedResets
    }

    /// With any quotas the card shows, fresh or stale: the plan tells whose
    /// they are. Without quotas the card has no account to name.
    var plan: String? {
        reading.lastValidReadingOfAnyAccount?.plan
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if enabled {
            reading = wait.rateLimitUntil(at: clock.now()).map { .failed(.rateLimited(until: $0), keeping: nil) } ?? .loading
            if isPanelOpen { panelOpened() }
        } else {
            if let query, let queryID {
                retiredQueries[queryID] = query
                query.cancel()
            }
            query = nil
            queryID = nil
            scheduledRetry = nil
            reading = .loading
            session = nil
            wait.keepOnlyActiveRateLimit(at: clock.now())
        }
    }

    /// Reads the session again, which may show the Keychain prompt: opening
    /// the panel is a user action.
    func panelOpened() {
        isPanelOpen = true
        guard isEnabled else { return }
        switch reading {
        case .failed(.sessionAccessDenied, _):
            // The user said no; only Actualizar asks again.
            break
        case .failed(let failure, _) where failure.isRejection:
            // Only a session that changed since the rejection is worth a
            // query. After a reused session was rejected there is none to
            // skip: the current session was never checked.
            startQuery(.read(skipping: session))
        default:
            // A fresh reading needs no query, but may belong to an account
            // the session no longer has.
            startQuery(reading.isFresh(at: clock.now()) ? .recheck : .read(skipping: nil))
        }
        scheduleRetry()
    }

    /// The Actualizar button: reads the session and queries even when the
    /// reading is fresh or the session was rejected.
    func refresh() {
        startQuery(.read(skipping: nil))
    }

    /// Stops scheduling retries. A query in flight still finishes.
    func panelClosed() {
        isPanelOpen = false
        scheduledRetry = nil
    }

    /// Returns once no query is in flight.
    func queryFinished() async {
        let tasks = Array(retiredQueries.values) + (query.map { [$0] } ?? [])
        for task in tasks { await task.value }
    }

    /// A query no user action asked for. It never reads the session, so it
    /// never shows the Keychain prompt: it reuses the last one read. After the
    /// provider rejects a session, or the user denies access to it, only the
    /// user asks again.
    func queryOnItsOwn() {
        guard isEnabled, !reading.waitsForTheUser, let session, wait.allowsAutomaticQuery(at: clock.now())
        else { return }
        startQuery(.reuse(session))
    }

    /// Never two queries of the same provider at once: a repeated request
    /// joins the one in flight. A user action reads the session even while
    /// the provider asks to wait, since the wait may be another account's.
    private func startQuery(_ source: SessionSource) {
        guard isEnabled, query == nil else { return }
        if case .reuse = source, !wait.allowsAnyQuery(at: clock.now()) { return }
        let id = UUID()
        queryID = id
        query = Task {
            let result = await read(source, queryID: id)
            retiredQueries[id] = nil
            guard queryID == id else { return }
            queryID = nil
            query = nil
            guard isEnabled, !Task.isCancelled else { return }
            if let result {
                reading = result
                planRetry(after: result)
            }
        }
    }

    /// Failures that may pass shortly are retried on their own, after a
    /// wait. Anything else ends the wait.
    private func planRetry(after reading: ProviderReading) {
        guard case .failed(let failure, _) = reading, failure.isWorthRetrying else {
            forgetWait()
            return
        }
        wait.record(failure, at: clock.now(), of: session?.accountID)
        scheduleRetry()
    }

    /// Forgets the failures counted so far and retires their retry.
    private func forgetWait() {
        wait = RetryWait()
        scheduledRetry = nil
    }

    /// Only while the panel is open. Replaces any retry scheduled before.
    private func scheduleRetry() {
        guard isEnabled, isPanelOpen, let retryAt = wait.retryAt else { return }
        scheduledRetry = clock.schedule(at: retryAt) { [weak self] in
            guard let self else { return }
            // The wait is over even if a real clock wakes a moment early.
            wait.end()
            queryOnItsOwn()
        }
    }

    /// `nil` when the card keeps what it shows: the session read is the one
    /// to skip, or no query is allowed yet.
    private func read(_ source: SessionSource, queryID: UUID) async -> ProviderReading? {
        guard isCurrent(queryID) else { return nil }
        let session: Session
        switch source {
        case .reuse(let reused):
            session = reused
        case .read, .recheck:
            let sessionReading = await sessionReader.read()
            guard isCurrent(queryID) else { return nil }
            if let failure = Failure(sessionReading) {
                self.session = nil
                return .failed(failure, keeping: nil)
            }
            guard case .session(let read) = sessionReading else { return nil }
            let lastRead = self.session
            // The queries no user action asks for reuse the session read
            // last, even when this read makes no query.
            self.session = read
            if source.skips(read, shown: reading, lastRead: lastRead) { return nil }
            session = read
            if wait.belongs(toAnotherAccountThan: read.accountID) {
                forgetWait()
            }
            let queries = wait.allowsAnyQuery(at: clock.now())
            forgetReading(unlessItBelongsTo: read, whileQuerying: queries)
            guard queries else {
                scheduleRetry()
                return nil
            }
        }
        guard isCurrent(queryID) else { return nil }
        let result = await transport.send(adapter.request(for: session))
        guard isCurrent(queryID) else { return nil }
        let failure: Failure
        switch answer(to: result, of: session, at: clock.now()) {
        case .quotas(let quotas, let bankedResets, let plan):
            return .quotas(LastValidReading(quotas: quotas, accountID: session.accountID, bankedResets: bankedResets, plan: plan))
        case .failed(let why): failure = why
        }
        log.record(.queryFailed(provider, failure))
        let kept = reading.lastValidReading(of: session.accountID)
        if failure.isRejection, case .reuse = source {
            // The official app may have renewed the token since it was
            // read, so the session is not called expired: the figures go
            // stale. Automatic queries stop; the next user action reads it
            // again.
            self.session = nil
            return .failed(.reusedSessionRejected, keeping: kept)
        }
        return .failed(failure, keeping: kept)
    }

    private func isCurrent(_ id: UUID) -> Bool {
        isEnabled && queryID == id && !Task.isCancelled
    }

    /// A reading of another account, or one with an uncertain identity on
    /// either side, goes at once: its figures are never shown as the
    /// session's. While querying, the card says whose quotas are coming.
    private func forgetReading(unlessItBelongsTo session: Session, whileQuerying querying: Bool) {
        guard let last = reading.lastValidReadingOfAnyAccount, reading.lastValidReading(of: session.accountID) == nil
        else { return }
        if !querying, case .failed(let failure, _) = reading {
            reading = .failed(failure, keeping: nil)
        } else {
            reading = last.accountID != nil && session.accountID != nil ? .newAccount : .loading
        }
    }

    /// The quotas in the provider's answer to a query made with `session`,
    /// or why there are none.
    private func answer(to result: HTTPResult, of session: Session, at moment: Date) -> Answer {
        let response: HTTPResponse
        switch result {
        case .response(let received): response = received
        case .networkError: return .failed(.offline)
        case .timeout: return .failed(.timedOut)
        case .responseTooLarge: return .failed(.responseTooLarge)
        }
        switch response.status {
        case 200:
            switch adapter.quotas(from: response.body, readAt: moment) {
            case .success(let quotas):
                return .quotas(
                    quotas,
                    bankedResets: adapter.bankedResets(from: response.body),
                    plan: adapter.plan(of: session, response: response.body)
                )
            case .failure(let failure): return .failed(failure)
            }
        case 401: return .failed(.sessionExpired)
        case 403: return .failed(.accessRefused)
        case 429: return .failed(.rateLimited(until: retryAfter(response.headers, from: moment)))
        case 500...599: return .failed(.serverError(status: response.status))
        // Anything else means the route or its format changed.
        default: return .failed(.incompatibleResponse)
        }
    }
}

/// How long a provider's queries wait after failures that may pass shortly:
/// the network, the server, or the provider asking to wait.
private struct RetryWait {
    /// The first wait doubles with each consecutive failure, up to the longest.
    static let first: TimeInterval = 30
    static let longest: TimeInterval = 15 * 60
    /// The longest a provider's `Retry-After` may hold back its queries; a
    /// longer one is cut to this.
    static let longestRequested: TimeInterval = 60 * 60

    private var failures = 0
    /// The account whose failures are counted; `nil` when uncertain.
    private var accountID: String?
    /// Queries no user action asked for wait until then.
    private(set) var retryAt: Date?
    /// No query at all is made before then, not even on Actualizar: the
    /// provider asked to wait (429 with `Retry-After`).
    private var blockedUntil: Date?

    mutating func record(_ failure: Failure, at now: Date, of accountID: String?) {
        failures += 1
        self.accountID = accountID
        if case .rateLimited(let until?) = failure {
            blockedUntil = until
            retryAt = until
        } else {
            blockedUntil = nil
            retryAt = now.addingTimeInterval(min(Self.first * pow(2, Double(failures - 1)), Self.longest))
        }
    }

    /// Keeps counting failures, so the next wait is still longer.
    mutating func end() {
        retryAt = nil
        blockedUntil = nil
    }

    func allowsAutomaticQuery(at now: Date) -> Bool {
        retryAt.map { now >= $0 } ?? true
    }

    func allowsAnyQuery(at now: Date) -> Bool {
        blockedUntil.map { now >= $0 } ?? true
    }

    func rateLimitUntil(at now: Date) -> Date? {
        blockedUntil.flatMap { $0 > now ? $0 : nil }
    }

    /// Disabling discards the old account and ordinary retry history, while
    /// keeping a provider's explicit request to wait.
    mutating func keepOnlyActiveRateLimit(at now: Date) {
        let until = rateLimitUntil(at: now)
        self = RetryWait()
        blockedUntil = until
        retryAt = until
    }

    /// Only a verified account that differs is another's: with an uncertain
    /// identity the wait still holds, so the provider is not queried early.
    func belongs(toAnotherAccountThan accountID: String?) -> Bool {
        guard let accountID, let mine = self.accountID else { return false }
        return mine != accountID
    }
}

/// What a provider's answer to a query says.
private enum Answer {
    case quotas([QuotaReading], bankedResets: Int?, plan: String?)
    case failed(Failure)
}

/// Where a query takes the provider's session from.
private enum SessionSource {
    /// Reads it, which may show the Keychain prompt. Skips the query when the
    /// session read is `skipping`, e.g. the one the provider rejected.
    case read(skipping: Session?)
    /// Reads it to check that the fresh reading shown is still the session's.
    /// Queries only when it is not: the account changed or its identity is
    /// uncertain.
    case recheck
    /// Reuses a session read before, without reading it again.
    case reuse(Session)

    /// Whether the query is not worth making with the session just read.
    /// `lastRead` is the session read before, `shown` what the card shows.
    func skips(_ read: Session, shown: ProviderReading, lastRead: Session?) -> Bool {
        switch self {
        case .read(let skipped): read == skipped
        case .recheck: read == lastRead || shown.lastValidReading(of: read.accountID) != nil
        // Never read, so never skipped.
        case .reuse: false
        }
    }
}

private extension Failure {
    /// Why a session reading gave no session; `nil` when it gave one.
    init?(_ reading: SessionReading) {
        switch reading {
        case .session: return nil
        case .noSession: self = .noSession
        case .withoutSubscriptionQuotas: self = .sessionWithoutSubscriptionQuotas
        case .accessDenied: self = .sessionAccessDenied
        case .storeUnavailable: self = .sessionStoreUnavailable
        case .storeBusy: self = .sessionStoreBusy
        case .unknownFormat: self = .incompatibleSession
        }
    }

    /// The network or the provider's server failed, or the provider asked to
    /// wait (429): it may work shortly.
    var isWorthRetrying: Bool {
        switch self {
        case .offline, .timedOut, .serverError, .rateLimited: true
        default: false
        }
    }

    /// The provider rejected the session, whether read or reused.
    var isRejection: Bool {
        self == .sessionExpired || self == .accessRefused || self == .reusedSessionRejected
    }
}

/// What the core last learned from a provider.
private enum ProviderReading {
    case loading
    /// The session changed to another account; its first query is pending.
    case newAccount
    case quotas(LastValidReading)
    /// `keeping` the last valid reading of the same account, now stale.
    case failed(Failure, keeping: LastValidReading?)

    func isFresh(at now: Date) -> Bool {
        guard case .quotas(let reading) = self, let readAt = reading.quotas.map(\.readAt).min() else { return false }
        return now.timeIntervalSince(readAt) < UsageCore.refreshInterval
    }

    /// The provider rejected the session, or the user denied access to it.
    var waitsForTheUser: Bool {
        guard case .failed(let failure, _) = self else { return false }
        return failure.isRejection || failure == .sessionAccessDenied
    }

    /// The last valid reading, if it belongs to `accountID`. A reading whose
    /// account cannot be verified belongs to no one.
    func lastValidReading(of accountID: String?) -> LastValidReading? {
        guard let last = lastValidReadingOfAnyAccount, let accountID, last.accountID == accountID else { return nil }
        return last
    }

    var lastValidReadingOfAnyAccount: LastValidReading? {
        switch self {
        case .loading, .newAccount: nil
        case .quotas(let reading): reading
        case .failed(_, let kept): kept
        }
    }

    func content(in magnitude: QuotaMagnitude, at now: Date) -> CardContent {
        switch self {
        case .loading:
            .loading
        case .newAccount:
            .loadingNewAccount
        case .quotas(let reading):
            .quotas(reading.quotas.map { $0.quota(in: magnitude, at: now) })
        case .failed(let failure, let kept?):
            .stale(kept.quotas.map { $0.quota(in: magnitude, at: now, stale: true) }, failure: failure)
        case .failed(let failure, nil):
            .failed(failure)
        }
    }
}

/// The quotas, banked resets and plan of a provider's last valid query, and
/// the account they belong to; `nil` when it could not be verified.
private struct LastValidReading {
    let quotas: [QuotaReading]
    let accountID: String?
    let bankedResets: Int?
    let plan: String?
}

/// When a `Retry-After` header, in seconds or as an HTTP date, says to query
/// again, at most `RetryWait.longestRequested` away; `nil` without one that
/// points into the future, so the wait is the progressive one instead.
private func retryAfter(_ headers: [String: String], from moment: Date) -> Date? {
    guard let value = headers.first(where: { $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame })?.value
        .trimmingCharacters(in: .whitespaces)
    else { return nil }
    let until: Date?
    if let seconds = Int(value) {
        until = moment.addingTimeInterval(TimeInterval(seconds))
    } else {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "GMT")
        format.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        until = format.date(from: value)
    }
    guard let until, until > moment else { return nil }
    return min(until, moment.addingTimeInterval(RetryWait.longestRequested))
}
