import Foundation
import Synchronization

// Fakes of the usage core's dependencies, shared by the tests and the debug
// scenarios. They never touch a real session or the network, and they are
// never in a Release build.
#if DEBUG

public struct SampleSessionReader: SessionReader {
    public init() {}

    public func read() async -> SessionReading {
        .session(Samples.session)
    }
}

/// Always answers each provider with the same response, and records the
/// requests it receives.
public actor SampleTransport: HTTPTransport {
    public private(set) var requests: [URLRequest] = []
    private let claudeResponse: Data
    private let codexResponse: Data
    private let cursorResponse: Data

    public init(
        claudeResponse: Data = Samples.claudeUsageResponse,
        codexResponse: Data = Samples.codexUsageResponse,
        cursorResponse: Data = Samples.cursorUsageResponse
    ) {
        self.claudeResponse = claudeResponse
        self.codexResponse = codexResponse
        self.cursorResponse = cursorResponse
    }

    public func send(_ request: URLRequest) async -> HTTPResult {
        requests.append(request)
        let body = switch request.url?.host {
        case "chatgpt.com": codexResponse
        case "api2.cursor.sh": cursorResponse
        default: claudeResponse
        }
        return .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: body))
    }
}

public struct FixedClock: WallClock {
    private let moment: Date

    public init(_ moment: Date) {
        self.moment = moment
    }

    public func now() -> Date {
        moment
    }

    /// The clock never moves, so scheduled work never runs.
    public func schedule(at deadline: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> ScheduledWork {
        ScheduledWork(onCancel: {})
    }
}

/// A clock the test moves by hand. Moving it runs, in order, the work
/// scheduled up to the new moment.
public final class ManualClock: WallClock {
    private struct Scheduled {
        let id = UUID()
        let deadline: Date
        let action: @MainActor @Sendable () -> Void
    }

    private let state: Mutex<(moment: Date, scheduled: [Scheduled])>

    public init(_ moment: Date) {
        state = Mutex((moment, []))
    }

    public func now() -> Date {
        state.withLock { $0.moment }
    }

    /// The deadlines of the work neither run nor cancelled, earliest first.
    public var scheduledDeadlines: [Date] {
        state.withLock { $0.scheduled.map(\.deadline).sorted() }
    }

    public func schedule(at deadline: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> ScheduledWork {
        let work = Scheduled(deadline: deadline, action: action)
        state.withLock { $0.scheduled.append(work) }
        return ScheduledWork(onCancel: { [self] in
            state.withLock { $0.scheduled.removeAll { $0.id == work.id } }
        })
    }

    @MainActor
    public func move(to moment: Date) {
        while let next = nextDue(by: moment) {
            next.action()
        }
        state.withLock { $0.moment = moment }
    }

    @MainActor
    public func advance(by interval: TimeInterval) {
        move(to: now().addingTimeInterval(interval))
    }

    /// Takes the earliest work due by `moment` and moves the clock to its deadline.
    private func nextDue(by moment: Date) -> Scheduled? {
        state.withLock { state in
            guard let index = state.scheduled.indices
                .filter({ state.scheduled[$0].deadline <= moment })
                .min(by: { state.scheduled[$0].deadline < state.scheduled[$1].deadline })
            else { return nil }
            let next = state.scheduled.remove(at: index)
            state.moment = max(state.moment, next.deadline)
            return next
        }
    }
}

/// Returns `session`, the sample one by default, or `reading` when set, and
/// counts the reads. Reading a real session can show the Keychain prompt.
public actor ControlledSessionReader: SessionReader {
    public private(set) var reads = 0
    private var reading: SessionReading
    private var held = false
    private var heldReads: [CheckedContinuation<Void, Never>] = []
    private var readWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init(session: Session = Samples.session) {
        reading = .session(session)
    }

    public func read() async -> SessionReading {
        reads += 1
        let arrived = readWaiters.filter { $0.count <= reads }
        readWaiters.removeAll { $0.count <= reads }
        arrived.forEach { $0.continuation.resume() }
        if held {
            await withCheckedContinuation { heldReads.append($0) }
        }
        return reading
    }

    public func answer(with reading: SessionReading) {
        self.reading = reading
    }

    public func hold() {
        held = true
    }

    public func release() {
        held = false
        heldReads.forEach { $0.resume() }
        heldReads.removeAll()
    }

    public func waitForReads(_ count: Int) async {
        guard reads < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }
}

/// A provider signed out of its official app: the panel never queries it.
public struct NoSessionReader: SessionReader {
    public init() {}

    public func read() async -> SessionReading {
        .noSession
    }
}

/// Answers each provider's requests with its sample response, or with the
/// result set for it. While a provider is held, its requests wait until the
/// test releases them.
public actor ControlledTransport: HTTPTransport {
    public private(set) var requests: [URLRequest] = []
    private var results: [Provider: HTTPResult] = [.claude: .claudeSample, .codex: .codexSample, .cursor: .cursorSample]
    private var held: Set<Provider> = []
    private var heldRequests: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    public init() {}

    public func send(_ request: URLRequest) async -> HTTPResult {
        requests.append(request)
        let arrived = requestWaiters.filter { $0.count <= requests.count }
        requestWaiters.removeAll { $0.count <= requests.count }
        arrived.forEach { $0.continuation.resume() }
        guard let provider = Provider(of: request) else { return .networkError }
        if held.contains(provider) {
            await withCheckedContinuation { heldRequests.append($0) }
        }
        return results[provider] ?? .networkError
    }

    /// Answers the requests of `provider`, or of every provider, with `result`.
    public func answer(with result: HTTPResult, for provider: Provider? = nil) {
        for each in provider.map({ [$0] }) ?? Provider.allCases {
            results[each] = result
        }
    }

    /// Holds the requests of `provider`, or of every provider.
    public func hold(_ provider: Provider? = nil) {
        held.formUnion(provider.map { [$0] } ?? Provider.allCases)
    }

    public func release() {
        held.removeAll()
        heldRequests.forEach { $0.resume() }
        heldRequests.removeAll()
    }

    /// The requests sent to `provider`.
    public func requests(to provider: Provider) -> [URLRequest] {
        requests.filter { Provider(of: $0) == provider }
    }

    /// Returns once `count` requests have arrived.
    public func waitForRequests(_ count: Int) async {
        guard requests.count < count else { return }
        await withCheckedContinuation { requestWaiters.append((count, $0)) }
    }
}

extension Provider {
    /// The provider a request is sent to, by its host.
    public init?(of request: URLRequest) {
        switch request.url?.host {
        case "api.anthropic.com": self = .claude
        case "chatgpt.com": self = .codex
        case "api2.cursor.sh": self = .cursor
        default: return nil
        }
    }
}

extension HTTPResult {
    /// The sample Claude response, answered with a 200.
    public static let claudeSample = HTTPResult.response(
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Samples.claudeUsageResponse)
    )

    /// The sample Codex response, answered with a 200.
    public static let codexSample = HTTPResult.response(
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Samples.codexUsageResponse)
    )

    /// The sample Cursor response, answered with a 200.
    public static let cursorSample = HTTPResult.response(
        HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Samples.cursorUsageResponse)
    )

    /// A response of any provider, answered with a 200, with the given body.
    public static func json(_ body: String) -> HTTPResult {
        .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8)))
    }

    /// A Codex response, answered with a 200, with the given `rate_limit`
    /// and `additional_rate_limits` JSON, and `rate_limit_reset_credits` when
    /// `resetCredits` is not `nil`.
    public static func codex(rateLimit: String, additional: String = "null", resetCredits: String? = nil) -> HTTPResult {
        let credits = resetCredits.map { #", "rate_limit_reset_credits": \#($0)"# } ?? ""
        let body = #"{"plan_type": "plus", "rate_limit": \#(rateLimit), "additional_rate_limits": \#(additional)\#(credits)}"#
        return .response(HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data(body.utf8)))
    }

    /// An empty response with `status`.
    public static func status(_ status: Int) -> HTTPResult {
        .response(HTTPResponse(status: status, headers: [:], body: Data()))
    }
}

/// Keeps the events the core logs.
public final class RecordingLog: EventLog {
    private let recorded = Mutex<[LogEvent]>([])

    public init() {}

    public var events: [LogEvent] {
        recorded.withLock { $0 }
    }

    public func record(_ event: LogEvent) {
        recorded.withLock { $0.append(event) }
    }
}

#endif
