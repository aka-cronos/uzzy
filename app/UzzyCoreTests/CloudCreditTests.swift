import Foundation
import Testing
import UzzyCore

@MainActor
struct CloudCreditTests {
    @Test(arguments: [
        #"{"remaining_dollars":90,"limit_dollars":"broken","resets_at":"2030-01-02T12:00:00Z"}"#,
        #"{"remaining_dollars":90,"limit_dollars":50,"resets_at":"2030-01-02T12:00:00Z"}"#,
        #"{"remaining_dollars":90,"resets_at":"2030-01-02T12:00:00Z"}"#,
    ])
    func invalidOrMissingAllowanceDoesNotHideValidRemainingCredit(_ grant: String) async {
        let core = await panel(grant)
        let card = core.state.cards.first
        #expect(card?.cloudCredit?.value == .money(Money(amount: 90, currency: "USD")))
        #expect(card?.cloudCredit?.total == nil)
        guard case .quotas = card?.content else { Issue.record("Quota reading lost"); return }
    }

    @Test(arguments: ["null", "{}", "42",
        #"{"remaining_dollars":0,"resets_at":"2030-01-02T12:00:00Z"}"#,
        #"{"remaining_dollars":-1,"resets_at":"2030-01-02T12:00:00Z"}"#,
        #"{"remaining_dollars":90,"resets_at":"2020-01-02T12:00:00Z"}"#,
        #"{"remaining_dollars":90,"resets_at":"bad-date"}"#,
        #"{"remaining_dollars":"broken","resets_at":"2030-01-02T12:00:00Z"}"#,
    ])
    func exhaustedExpiredAbsentOrMalformedCloudGrantsNeverBreakQuotas(_ grant: String) async {
        let core = await panel(grant)
        let card = core.state.cards.first
        #expect(card?.cloudCredit == nil)
        guard case .quotas = card?.content else { Issue.record("Quota reading lost"); return }
    }

    @Test func expiryHidesACreditRetainedAfterAQuotaFailure() async {
        let transport = ControlledTransport()
        let clock = ManualClock(Samples.readingMoment)
        let expiry = Samples.readingMoment.addingTimeInterval(60)
        await transport.answer(with: .json("""
            {"five_hour":{"utilization":35},"iguana_necktie":{"remaining_dollars":90,"resets_at":"\(expiry.ISO8601Format())"}}
            """), for: .claude)
        let core = UsageCore(claudeSessionReader: SampleSessionReader(), codexSessionReader: NoSessionReader(), cursorSessionReader: NoSessionReader(), transport: transport, clock: clock)
        core.panelOpened()
        await core.queriesFinished()
        await transport.answer(with: .timeout, for: .claude)
        core.refresh()
        await core.queriesFinished()
        #expect(core.state.cards.first?.cloudCredit?.isStale == true)
        core.panelClosed()
        clock.advance(by: 60)
        #expect(core.state.cards.first?.cloudCredit == nil)
    }

    @Test func aCreditObjectDoesNotMakeACreditOnlyResponseAQuotaReading() async {
        let core = await panel(#"{"remaining_dollars":90,"resets_at":"2030-01-02T12:00:00Z"}"#, withQuotas: false)
        #expect(core.state.cards.first?.content == .failed(.incompatibleResponse))
        #expect(core.state.cards.first?.cloudCredit == nil)
    }

    private func panel(_ grant: String, withQuotas: Bool = true) async -> UsageCore {
        let quota = withQuotas ? #""five_hour":{"utilization":35},"# : ""
        let body = "{\(quota)\"iguana_necktie\":\(grant),\"harbor_lantern\":null}"
        let core = UsageCore(
            claudeSessionReader: SampleSessionReader(), codexSessionReader: NoSessionReader(), cursorSessionReader: NoSessionReader(),
            transport: SampleTransport(claudeResponse: Data(body.utf8)), clock: FixedClock(Samples.readingMoment),
            initialEnabledProviders: [.claude]
        )
        core.panelOpened()
        await core.queriesFinished()
        return core
    }
    @Test(arguments: ["{}", #"{"kind":"unknown"}"#])
    func unknownLimitsDoNotMakeACreditOnlyPayloadCompatible(_ limit: String) async {
        let body = """
            {"limits":[\(limit)],"iguana_necktie":{"remaining_dollars":90,"resets_at":"2030-01-02T12:00:00Z"}}
            """
        let core = UsageCore(claudeSessionReader: SampleSessionReader(), codexSessionReader: NoSessionReader(), cursorSessionReader: NoSessionReader(), transport: SampleTransport(claudeResponse: Data(body.utf8)), clock: FixedClock(Samples.readingMoment), initialEnabledProviders: [.claude])
        core.panelOpened()
        await core.queriesFinished()
        #expect(core.state.cards.first?.content == .failed(.incompatibleResponse))
        #expect(core.state.cards.first?.cloudCredit == nil)
    }

}
