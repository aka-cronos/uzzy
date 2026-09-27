import Foundation
import Testing
import UzzyCore

/// The Cursor card, end to end: Cursor's session, its usage query and its
/// two bags of the billing cycle, Cursor Models and Other Models.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CursorPanelTests {
    let clock = ManualClock(Samples.readingMoment)
    let cursorSessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore
    // 2026-10-10T00:00:00Z, from the sample response.
    let cycleEnd = Date(timeIntervalSince1970: 1_791_590_400)

    init() {
        core = UsageCore(
            claudeSessionReader: ControlledSessionReader(),
            codexSessionReader: ControlledSessionReader(),
            cursorSessionReader: cursorSessionReader,
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    func cursorContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .cursor })?.content
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test func thePanelShowsTheCardsOfClaudeCodexAndCursorInThatOrder() {
        #expect(core.state.cards == [
            Card(provider: .claude, content: .loading),
            Card(provider: .codex, content: .loading),
            Card(provider: .cursor, content: .loading),
        ])
    }

    @Test func openingThePanelShowsCursorModelsAndOtherModelsSeparately() async {
        await openPanel()

        #expect(cursorContent() == .quotas([
            Quota(period: .limit("Cursor Models", .billingCycle), value: .percent(18.5, calculated: false), reset: .at(cycleEnd), readAt: Samples.readingMoment),
            Quota(period: .limit("Other Models", .billingCycle), value: .percent(42.75, calculated: false), reset: .at(cycleEnd), readAt: Samples.readingMoment),
        ]))
    }

    @Test func queriesCursorUsageWithAConnectCallAndTheAccessToken() async {
        await openPanel()

        let requests = await transport.requests(to: .cursor)
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.url == URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage"))
        #expect(requests.first?.allHTTPHeaderFields == [
            "Authorization": "Bearer sample-token",
            "Content-Type": "application/json",
            "Connect-Protocol-Version": "1",
        ])
        #expect(requests.first?.httpBody == Data("{}".utf8))
    }

    @Test func remainingQuotaIsCalculatedForEachBagSeparately() async {
        core.show(.remaining)

        await openPanel()

        #expect(cursorContent() == .quotas([
            Quota(period: .limit("Cursor Models", .billingCycle), value: .percent(81.5, calculated: true), reset: .at(cycleEnd), readAt: Samples.readingMoment),
            Quota(period: .limit("Other Models", .billingCycle), value: .percent(57.25, calculated: true), reset: .at(cycleEnd), readAt: Samples.readingMoment),
        ]))
    }

    /// A missing bag is never taken as zero, and the other one still shows.
    @Test func aBagWithoutUsageIsUnavailable() async {
        await transport.answer(with: .json("""
            {"billingCycleEnd": "1791590400000", "planUsage": {"apiPercentUsed": 42.75, "totalPercentUsed": 3.1}}
            """), for: .cursor)

        await openPanel()

        #expect(cursorContent() == .quotas([
            Quota(period: .limit("Cursor Models", .billingCycle), value: .unavailable, reset: .at(cycleEnd), readAt: Samples.readingMoment),
            Quota(period: .limit("Other Models", .billingCycle), value: .percent(42.75, calculated: false), reset: .at(cycleEnd), readAt: Samples.readingMoment),
        ]))
    }

    @Test(arguments: [
        #""billingCycleEnd": null,"#,
        "",
        #""billingCycleEnd": "soon","#,
        #""billingCycleEnd": "0","#,
        #""billingCycleEnd": "9223372036854775807","#,
    ])
    func withoutAValidEndOfTheBillingCycleTheResetIsUnknown(billingCycleEnd: String) async {
        await transport.answer(with: .json("""
            {\(billingCycleEnd) "planUsage": {"autoPercentUsed": 18.5, "apiPercentUsed": 42.75}}
            """), for: .cursor)

        await openPanel()

        #expect(cursorContent() == .quotas([
            Quota(period: .limit("Cursor Models", .billingCycle), value: .percent(18.5, calculated: false), reset: .unknown, readAt: Samples.readingMoment),
            Quota(period: .limit("Other Models", .billingCycle), value: .percent(42.75, calculated: false), reset: .unknown, readAt: Samples.readingMoment),
        ]))
    }

    @Test func aNumericBillingCycleEndExplainsTheIncompatibleResetFormat() async {
        await transport.answer(with: .json("""
            {"billingCycleEnd": 1791590400000, "planUsage": {"autoPercentUsed": 18.5, "apiPercentUsed": 42.75}}
            """), for: .cursor)

        await openPanel()

        #expect(cursorContent() == .failed(.incompatibleResetFormat))
    }

    @Test func aPercentOutOfRangeIsUninterpretable() async {
        await transport.answer(with: .json("""
            {"billingCycleEnd": "1791590400000", "planUsage": {"autoPercentUsed": -2, "apiPercentUsed": 100.5}}
            """), for: .cursor)

        await openPanel()

        #expect(cursorContent() == .quotas([
            Quota(period: .limit("Cursor Models", .billingCycle), value: .uninterpretable, reset: .at(cycleEnd), readAt: Samples.readingMoment),
            Quota(period: .limit("Other Models", .billingCycle), value: .uninterpretable, reset: .at(cycleEnd), readAt: Samples.readingMoment),
        ]))
    }

    /// Nothing in these says the plan has no quotas, so they are not understood.
    @Test(arguments: [
        #"{"billingCycleEnd": "1791590400000"}"#,
        #"{"billingCycleEnd": "1791590400000", "planUsage": {"autoPercentUsed": "a lot"}}"#,
        "Sample text",
    ])
    func aResponseWithoutPlanUsageIsIncompatible(body: String) async {
        await transport.answer(with: .json(body), for: .cursor)

        await openPanel()

        #expect(cursorContent() == .failed(.incompatibleResponse))
    }

    @Test func aCursorFailureLeavesTheOtherCardsShowingTheirQuotas() async {
        await transport.answer(with: .status(401), for: .cursor)

        await openPanel()

        #expect(cursorContent() == .failed(.sessionExpired))
        for provider in [Provider.claude, .codex] {
            let content = core.state.cards.first(where: { $0.provider == provider })?.content
            #expect(content.map { if case .quotas = $0 { true } else { false } } == true)
        }
    }
}
