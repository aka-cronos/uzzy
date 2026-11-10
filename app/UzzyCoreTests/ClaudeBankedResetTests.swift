import Foundation
import Testing
import UzzyCore

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClaudeBankedResetTests {
    let clock = ManualClock(Samples.readingMoment)
    let session = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore

    init() {
        core = UsageCore(
            claudeSessionReader: session, codexSessionReader: NoSessionReader(), cursorSessionReader: NoSessionReader(),
            transport: transport, clock: clock, log: RecordingLog()
        )
    }

    var card: Card? { core.state.cards.first { $0.provider == .claude } }

    static func grant(_ id: String = "first", count: String = "3", expiry: String = #""2026-10-01T12:00:00Z""#,
                      paused: String = "false", usable: String = "true") -> String {
        #"{"id":"\#(id)","resets_left":\#(count),"ends_at":\#(expiry),"paused":\#(paused),"usable_now":\#(usable)}"#
    }

    static func program(_ grants: [String], next: String = #""first""#) -> String {
        #"{"eligible":true,"grants":[\#(grants.joined(separator: ","))],"next_grant_id":\#(next)}"#
    }

    func answer(_ program: String?) async {
        let response = #"{"five_hour":{"utilization":35},"seven_day":{"utilization":62},"extra_usage":{"is_enabled":true,"used_credits":1234.5,"currency":"USD"}\#(program.map { ",\"cedar_ember\":\($0)" } ?? "")}"#
        await transport.answer(with: .json(response), for: .claude)
    }

    func open(_ program: String? = Self.program([Self.grant()])) async {
        await answer(program)
        core.panelOpened()
        await core.queriesFinished()
    }

    func assertQuotasAndSpending() {
        guard case .quotas(let quotas) = card?.content else {
            Issue.record("Expected quotas, independent of reset parsing")
            return
        }
        #expect(quotas.map(\.period) == [.fiveHours, .weekly, .usageCredits])
        #expect(quotas.first?.value == .percent(35, calculated: false))
        #expect(quotas.last?.value == .spend(Money(amount: Decimal(string: "12.345")!, currency: "USD"), limit: nil))
    }

    @Test func readsResetsWithQuotasAndFractionalSpendingInOneRequest() async {
        await open()
        #expect(card?.bankedResets == 3)
        assertQuotasAndSpending()
        let requests = await transport.quotaRequests(to: .claude)
        #expect(requests.count == 1)
        #expect(requests.first?.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage?cedar_ember=1")
        #expect(requests.first?.httpMethod == "GET")
        #expect(requests.first?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(requests.first?.value(forHTTPHeaderField: "User-Agent") == "claude-cli/2.1.322 (external, cli)")
    }

    @Test func sumsOnlyUsableUnpausedUnexpiredValidGrants() async {
        await open(Self.program([
            Self.grant(), Self.grant("second", count: "2", expiry: "null"),
            Self.grant("paused", count: "40", paused: "true"),
            Self.grant("unusable", count: "40", usable: "false"),
            Self.grant("expired", count: "40", expiry: #""2026-09-01T00:00:00Z""#),
            "null", "[]", #"{"id":"broken","resets_left":"7"}"#,
        ]))
        #expect(card?.bankedResets == 5)
        assertQuotasAndSpending()
    }

    @Test(arguments: [nil, "null", "[]", "true", "{}", #"{"eligible":false}"#,
                      #"{"eligible":"true"}"#, #"{"eligible":true,"grants":{}}"#] as [String?])
    func absentOrMalformedProgramDoesNotHideQuotasOrSpending(program: String?) async {
        await open(program)
        #expect(card?.bankedResets == nil)
        assertQuotasAndSpending()
    }

    @Test(arguments: ["null", #""missing""#, "true"])
    func noMatchingNextGrantHidesTheCount(next: String) async {
        await open(Self.program([Self.grant()], next: next))
        #expect(card?.bankedResets == nil)
        assertQuotasAndSpending()
    }

    @Test(arguments: ["0", "-1", "1.5", "9223372036854775808", #""3""#, "true", "null", "[]"])
    func invalidOrZeroNextGrantCountIsHidden(count: String) async {
        await open(Self.program([Self.grant(count: count)]))
        #expect(card?.bankedResets == nil)
        assertQuotasAndSpending()
    }

    @Test(arguments: [
        "", "2030-01-01", "2030-02-30T00:00:00Z", "2030-13-01T00:00:00Z",
        "2030-01-01T25:00:00Z", "2030-01-01T00:00:00", "not-a-date",
        "2026-09-23T14:20:00Z",
    ])
    func invalidOrExpiredNextGrantHidesTheCount(expiry: String) async {
        await open(Self.program([Self.grant(expiry: "\"\(expiry)\"")]))
        #expect(card?.bankedResets == nil)
        assertQuotasAndSpending()
    }

    @Test(arguments: ["null", #""2030-01-01T12:00:00.123456Z""#, #""2030-01-01T12:00:00+05:30""#])
    func supportedExpiryShapesKeepTheCount(expiry: String) async {
        await open(Self.program([Self.grant(expiry: expiry)]))
        #expect(card?.bankedResets == 3)
    }

    @Test func summationOverflowHidesTheCountWithoutFailingQuotas() async {
        await open(Self.program([Self.grant(count: String(Int.max)), Self.grant("second", count: "1")]))
        #expect(card?.bankedResets == nil)
        assertQuotasAndSpending()
    }

    @Test func expirationReducesTheCountWithoutANetworkRequest() async {
        let expiry = clock.now().addingTimeInterval(60).ISO8601Format()
        await open(Self.program([Self.grant(), Self.grant("second", count: "2", expiry: "\"\(expiry)\"")]))
        #expect(card?.bankedResets == 5)
        clock.advance(by: 60)
        #expect(card?.bankedResets == 3)
        #expect(await transport.quotaRequests(to: .claude).count == 1)
    }

    @Test func expirationOfTheNextGrantHidesTheCountUntilRefreshed() async {
        let expiry = clock.now().addingTimeInterval(60).ISO8601Format()
        await open(Self.program([Self.grant(expiry: "\"\(expiry)\""), Self.grant("second", count: "2")]))
        #expect(card?.bankedResets == 5)
        clock.advance(by: 60)
        #expect(card?.bankedResets == nil)
    }

    @Test func successfulReadReplacesAndThenClearsTheCount() async {
        await open()
        await answer(Self.program([Self.grant(count: "1")]))
        core.refresh()
        await core.queriesFinished()
        #expect(card?.bankedResets == 1)
        await answer(nil)
        core.refresh()
        await core.queriesFinished()
        #expect(card?.bankedResets == nil)
        assertQuotasAndSpending()
    }

    @Test(arguments: [HTTPResult.networkError, .timeout, .status(403), .status(429), .status(503), .json("{}")])
    func failedReadHidesResetsWhileKeepingQuotasStale(failure: HTTPResult) async {
        await open()
        await transport.answer(with: failure, for: .claude)
        core.refresh()
        await core.queriesFinished()
        #expect(card?.bankedResets == nil)
        guard case .stale = card?.content else { Issue.record("Expected stale quotas"); return }
    }

    @Test(arguments: ["other-account", nil] as [String?])
    func changedIdentityDoesNotCarryTheCount(account: String?) async {
        await open()
        await session.answer(with: .session(Session(accessToken: "different-token", accountID: account)))
        await answer(nil)
        await transport.hold()
        core.refresh()
        await transport.waitForQuotaRequests(2)
        #expect(card?.bankedResets == nil)
        await transport.release()
        await core.queriesFinished()
        #expect(card?.bankedResets == nil)
    }

    @Test func disablingAndInvalidSessionsClearTheCount() async {
        await open()
        core.setEnabled(false, for: .claude)
        #expect(card == nil)
        await answer(nil)
        core.setEnabled(true, for: .claude)
        await core.queriesFinished()
        #expect(card?.bankedResets == nil)
        await answer(Self.program([Self.grant()]))
        core.refresh()
        await core.queriesFinished()
        #expect(card?.bankedResets == 3)
        await session.answer(with: .noSession)
        core.refresh()
        await core.queriesFinished()
        #expect(card?.bankedResets == nil)
    }
}
