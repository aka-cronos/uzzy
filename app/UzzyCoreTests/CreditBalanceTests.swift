import Foundation
import Testing
import UzzyCore

@MainActor
struct CreditBalanceTests {
    @Test func fractionalCodexCreditsAreAQuantityAlongsideUnchangedQuotas() async {
        let transport = SampleTransport(codexResponse: Data("""
            {"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000}},
             "credits":{"balance":"123.45","unlimited":false,"has_credits":true}}
            """.utf8))
        let core = UsageCore(
            claudeSessionReader: NoSessionReader(), codexSessionReader: SampleSessionReader(),
            cursorSessionReader: NoSessionReader(), transport: transport, clock: FixedClock(Samples.readingMoment)
        )
        core.panelOpened()
        await core.queriesFinished()
        let card = core.state.cards.first { $0.provider == .codex }
        #expect(card?.creditBalance?.value == .credits(Decimal(string: "123.45")!))
        #expect(card?.creditBalance?.readAt == Samples.readingMoment)
        #expect(card?.creditBalance?.isStale == false)
        guard case .quotas(let quotas) = card?.content else { Issue.record("Expected subscription quotas"); return }
        #expect(quotas.first?.value == .percent(12, calculated: false))
    }
    @Test(arguments: ["0", "-1", "NaN", "Infinity", "12junk", "1e999", "999999999999999999999999999999999999999999"])
    func invalidOrZeroCodexBalancesNeverHideQuotas(_ balance: String) async {
        let transport = SampleTransport(codexResponse: Data("""
            {"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000}},
             "credits":{"balance":"\(balance)","unlimited":false}}
            """.utf8))
        let core = UsageCore(
            claudeSessionReader: NoSessionReader(), codexSessionReader: SampleSessionReader(),
            cursorSessionReader: NoSessionReader(), transport: transport, clock: FixedClock(Samples.readingMoment)
        )
        core.panelOpened()
        await core.queriesFinished()
        let card = core.state.cards.first { $0.provider == .codex }
        #expect(card?.creditBalance == nil)
        guard case .quotas = card?.content else { Issue.record("Quota decoding failed"); return }
    }

    @Test func cloudGrantIsSeparateFromSpendingAndExpiresWithoutAnotherFetch() async {
        let clock = ManualClock(Samples.readingMoment)
        let expiry = Samples.readingMoment.addingTimeInterval(60)
        let transport = SampleTransport(claudeResponse: Data("""
            {"five_hour":{"utilization":35},
             "extra_usage":{"is_enabled":true,"used_credits":5306,"currency":"USD"},
             "harbor_lantern":null,
             "iguana_necktie":{"remaining_dollars":90,"limit_dollars":120,
               "used_dollars":30,"resets_at":"\(expiry.ISO8601Format())"}}
            """.utf8))
        let core = UsageCore(
            claudeSessionReader: SampleSessionReader(), codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(), transport: transport, clock: clock
        )
        core.panelOpened()
        await core.queriesFinished()
        let card = core.state.cards.first { $0.provider == .claude }
        #expect(card?.cloudCredit?.value == .money(Money(amount: 90, currency: "USD")))
        #expect(card?.cloudCredit?.total == Money(amount: 120, currency: "USD"))
        #expect(card?.creditBalance == nil)
        clock.advance(by: 61)
        #expect(core.state.cards.first { $0.provider == .claude }?.cloudCredit == nil)
    }

    @Test func cursorPrepaidIsMoneyEvenWithAutoTopUpOff() async {
        let transport = ControlledTransport()
        await transport.answerCredits(with: .json(#"{"billingMode":"PREPAID_BILLING_MODE_PREPAID","eligible":true,"availableCents":"725","autoTopUp":{"enabled":false},"noUsageBasedAllowed":true}"#), for: .cursor)
        let core = UsageCore(
            claudeSessionReader: NoSessionReader(), codexSessionReader: NoSessionReader(),
            cursorSessionReader: SampleSessionReader(), transport: transport, clock: FixedClock(Samples.readingMoment)
        )
        core.panelOpened()
        await core.queriesFinished()
        #expect(core.state.cards.first { $0.provider == .cursor }?.creditBalance?.value
                == .money(Money(amount: Decimal(string: "7.25")!, currency: "USD")))
    }

    @Test func aLargeExactCodexCreditQuantityIsPreserved() async {
        let transport = SampleTransport(codexResponse: Data(#"{"rate_limit":{"primary_window":{"used_percent":12,"limit_window_seconds":18000}},"credits":{"balance":"100000000000000000000000000000000000000","unlimited":false}}"#.utf8))
        let core = UsageCore(claudeSessionReader: NoSessionReader(), codexSessionReader: SampleSessionReader(), cursorSessionReader: NoSessionReader(), transport: transport, clock: FixedClock(Samples.readingMoment))
        core.panelOpened()
        await core.queriesFinished()
        #expect(core.state.cards.first { $0.provider == .codex }?.creditBalance?.value == .credits(pow(Decimal(10), 38)))
    }

}
