import Foundation
import Testing
import UzzyCore

@MainActor
struct PrepaidStateTests {
    let transport = ControlledTransport()
    let session = ControlledSessionReader()
    let clock = ManualClock(Samples.readingMoment)
    let organization = "00000000-0000-4000-8000-000000000201"

    func core(_ provider: Provider) -> UsageCore {
        UsageCore(
            claudeSessionReader: provider == .claude ? session : NoSessionReader(),
            codexSessionReader: provider == .codex ? session : NoSessionReader(),
            cursorSessionReader: provider == .cursor ? session : NoSessionReader(),
            transport: transport, clock: clock, initialEnabledProviders: [provider]
        )
    }

    func open(_ core: UsageCore) async {
        core.panelOpened()
        await core.queriesFinished()
    }

    func profile(organization: String? = nil, account: String = "sample-account") async {
        await transport.answerProfile(with: .json("""
            {"account":{"uuid":"\(account)"},"organization":{"uuid":"\(organization ?? self.organization)"}}
            """))
    }

    @Test func claudeResolvesOrganizationAndUsesItsCurrencyExponent() async {
        await profile()
        await transport.answerCredits(with: .json(#"{"amount":999,"amount_without_scoped_credits":725,"currency":"KWD"}"#), for: .claude)
        let core = core(.claude)
        await open(core)
        let reading = core.state.cards.first?.creditBalance
        #expect(reading?.value == .money(Money(amount: Decimal(string: "0.725")!, currency: "KWD")))
        #expect(reading?.accountID == "sample-account")
        #expect(reading?.organizationID == organization)
        let request = await transport.requests.last
        #expect(request?.url?.path == "/api/oauth/organizations/\(organization)/prepaid/credits")
        #expect(request?.value(forHTTPHeaderField: "x-organization-uuid") == organization)
    }

    @Test func legacyClaudeMoneyCannotIncludePositiveScopedTranches() async {
        await profile()
        await transport.answerCredits(with: .json(#"{"amount":725,"currency":"USD","tranches":[{"remaining_amount_minor_units":100,"scope":{"product":"cloud"}}]}"#), for: .claude)
        let core = core(.claude)
        await open(core)
        #expect(core.state.cards.first?.creditBalance == nil)
        guard case .quotas = core.state.cards.first?.content else { Issue.record("Expected fresh usage limits"); return }
    }

    @Test func optionalFailureRetainsItsOwnTimestampWhileQuotasRefresh() async {
        await transport.answerCredits(with: .json(#"{"billingMode":2,"eligible":true,"availableCents":"725"}"#), for: .cursor)
        let core = core(.cursor)
        await open(core)
        clock.advance(by: 60)
        await transport.answerCredits(with: .timeout, for: .cursor)
        core.refresh()
        await core.queriesFinished()
        let card = core.state.cards.first
        #expect(card?.creditBalance?.isStale == true)
        #expect(card?.creditBalance?.readAt == Samples.readingMoment)
        guard case .quotas(let quotas) = card?.content else { Issue.record("Optional failure failed the quota"); return }
        #expect(quotas.allSatisfy { !$0.isStale && $0.readAt == clock.now() })
        let request = await transport.requests.last
        #expect(request?.httpBody == Data(#"{"limit":1,"skipBalanceCache":true}"#.utf8))
    }

    @Test func newOrganizationNeverRetainsThePreviousOrganizationsBalance() async {
        await profile()
        await transport.answerCredits(with: .json(#"{"amount":725,"currency":"USD"}"#), for: .claude)
        let core = core(.claude)
        await open(core)
        #expect(core.state.cards.first?.creditBalance != nil)
        await profile(organization: "00000000-0000-4000-8000-000000000202")
        await transport.answerCredits(with: .networkError, for: .claude)
        core.refresh()
        await core.queriesFinished()
        #expect(core.state.cards.first?.creditBalance == nil)
    }

    @Test(arguments: [SessionReading.noSession, .session(Session(accessToken: "other-token", accountID: "other-account")), .session(Session(accessToken: "uncertain-token", accountID: nil))])
    func signOutAccountChangeAndUncertainIdentityClearCredit(_ next: SessionReading) async {
        await transport.answerCredits(with: .json(#"{"billingMode":2,"eligible":true,"availableCents":"725"}"#), for: .cursor)
        let core = core(.cursor)
        await open(core)
        #expect(core.state.cards.first?.creditBalance != nil)
        await session.answer(with: next)
        await transport.answerCredits(with: .timeout, for: .cursor)
        core.refresh()
        await core.queriesFinished()
        #expect(core.state.cards.first?.creditBalance == nil)
    }

    @Test(arguments: [#"{"billingMode":2,"eligible":true}"#, #"{"billingMode":2,"eligible":true,"availableCents":"0"}"#, #"{"billingMode":2,"eligible":false,"availableCents":"725"}"#, #"{"billingMode":999,"eligible":true,"availableCents":"725"}"#, #"{"billingMode":2,"eligible":true,"availableCents":725}"#, #"{"billingMode":2,"eligible":true,"availableCents":"9223372036854775808"}"#, "{}"])
    func cursorZeroIneligibleAndIncompatibleResponsesHaveNoBalance(_ response: String) async {
        await transport.answerCredits(with: .json(response), for: .cursor)
        let core = core(.cursor)
        await open(core)
        #expect(core.state.cards.first?.creditBalance == nil)
        guard case .quotas = core.state.cards.first?.content else { Issue.record("Expected valid quotas"); return }
    }

    @Test func disabledProvidersReadNoSessionsOrOptionalEndpoints() async {
        let core = core(.claude)
        core.setEnabled(false, for: .claude)
        await open(core)
        #expect(await session.reads == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test func profileAccountMismatchAndLookupFailureClearOrganizationScope() async {
        await profile()
        await transport.answerCredits(with: .json(#"{"amount":725,"currency":"USD"}"#), for: .claude)
        let core = core(.claude)
        await open(core)
        await profile(account: "other-account")
        core.refresh()
        await core.queriesFinished()
        #expect(core.state.cards.first?.creditBalance == nil)
        await transport.answerProfile(with: .timeout)
        core.refresh()
        await core.queriesFinished()
        #expect(core.state.cards.first?.creditBalance == nil)
    }
    @Test func aSlowOptionalEndpointDoesNotDelaySuccessfulQuotas() async {
        await transport.holdCredits(for: .cursor)
        let core = core(.cursor)
        core.panelOpened()
        await transport.waitForRequests(3)
        guard case .quotas = core.state.cards.first?.content else {
            Issue.record("Fresh quotas must be visible while the optional request is held")
            await transport.release()
            await core.queriesFinished()
            return
        }
        #expect(core.state.isQuerying)
        await transport.release()
        await core.queriesFinished()
    }

}
