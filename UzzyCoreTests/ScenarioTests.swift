import Foundation
import Testing
import UzzyCore

/// The debug scenarios put the usage core in each visible state of the
/// panel, from the sample responses, for review by eye.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenarioTests {
    func contents(of core: UsageCore) -> [Provider: CardContent] {
        Dictionary(uniqueKeysWithValues: core.state.cards.map { ($0.provider, $0.content) })
    }

    func quotas(_ content: CardContent?) -> [Quota] {
        switch content {
        case .quotas(let quotas), .stale(let quotas, _): quotas
        default: []
        }
    }

    // 2026-09-23T17:00:00Z and 2026-09-25T09:00:00Z
    let claudeFiveHourReset = Date(timeIntervalSince1970: 1_790_182_800)
    let claudeWeeklyReset = Date(timeIntervalSince1970: 1_790_326_800)

    @Test func quotasShowEverySampleReading() async {
        let core = await Scenario.quotas.start()
        let cards = contents(of: core)

        #expect(quotas(cards[.claude]).map(\.value) == [.percent(35, calculated: false), .percent(62, calculated: false)])
        #expect(quotas(cards[.codex]).map(\.value) == [.percent(12, calculated: false), .percent(41, calculated: false)])
        #expect(quotas(cards[.cursor]).map(\.value) == [.percent(18.5, calculated: false), .percent(42.75, calculated: false)])
        #expect(!core.state.isQuerying)
    }

    @Test func quotasShowEachProvidersPlanNextToItsName() async {
        let core = await Scenario.quotas.start()

        #expect(core.state.cards.map(\.plan) == ["Max", "Plus", "Pro+"])
    }

    @Test func usageCreditsShowsClaudeSpendingPastItsMonthlyLimit() async {
        let core = await Scenario.usageCredits.start()

        #expect(quotas(contents(of: core)[.claude]) == [
            Quota(period: .fiveHours, value: .percent(35, calculated: false), reset: .at(claudeFiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .weekly, value: .percent(62, calculated: false), reset: .at(claudeWeeklyReset), readAt: Samples.readingMoment),
            Quota(
                period: .usageCredits,
                value: .spend(Money(amount: Decimal(string: "53.06")!, currency: "USD"), limit: Money(amount: 40, currency: "USD")),
                reset: nil,
                readAt: Samples.readingMoment
            ),
        ])
    }

    @Test func uncappedUsageCreditsShowsClaudeSpendingWithoutALimit() async {
        let core = await Scenario.uncappedUsageCredits.start()

        #expect(quotas(contents(of: core)[.claude]).last == Quota(
            period: .usageCredits,
            value: .spend(Money(amount: Decimal(string: "53.06")!, currency: "USD"), limit: nil),
            reset: nil,
            readAt: Samples.readingMoment
        ))
    }

    @Test func loadingShowsEveryCardQueryingItsQuotas() async {
        let core = await Scenario.loading.start()

        #expect(core.state.cards.map(\.content) == [.loading, .loading, .loading])
        #expect(core.state.isQuerying)
    }

    @Test func newAccountClearsEveryCardWhileTheOtherAccountIsQueried() async {
        let core = await Scenario.newAccount.start()

        #expect(core.state.cards.map(\.content) == [.loadingNewAccount, .loadingNewAccount, .loadingNewAccount])
    }

    @Test func staleKeepsTheLastValidReadingOfEachCardAfterAFailure() async {
        let core = await Scenario.stale.start()
        let cards = contents(of: core)

        guard case .stale(let claude, .offline) = cards[.claude],
              case .stale(let codex, .serverError(status: 503)) = cards[.codex],
              case .stale(let cursor, .timedOut) = cards[.cursor]
        else { Issue.record("Not stale: \(cards)"); return }
        #expect((claude + codex + cursor).allSatisfy { $0.isStale && $0.readAt == Samples.readingMoment })
        #expect(core.now() > Samples.readingMoment)
    }

    @Test func pendingConfirmationShowsAPassedResetWithoutANewReading() async {
        let core = await Scenario.pendingConfirmation.start()
        let claude = quotas(contents(of: core)[.claude])

        #expect(claude.map(\.reset) == [.pendingConfirmation, .at(claudeWeeklyReset)])
        #expect(claude.allSatisfy { $0.isStale })
    }

    @Test func unknownResetShowsAQuotaWithoutAResetDate() async {
        let core = await Scenario.unknownReset.start()

        #expect(quotas(contents(of: core)[.claude]).map(\.reset) == [.at(claudeFiveHourReset), .unknown])
    }

    @Test func unavailableShowsAMissingQuotaNextToTheValidOne() async {
        let core = await Scenario.unavailable.start()

        #expect(quotas(contents(of: core)[.claude]).map(\.value) == [.percent(35, calculated: false), .unavailable])
    }

    @Test func withoutSubscriptionQuotasShowsASessionWithoutSubscriptionQuotas() async {
        let core = await Scenario.withoutSubscriptionQuotas.start()

        #expect(contents(of: core)[.codex] == .failed(.sessionWithoutSubscriptionQuotas))
    }

    @Test func uninterpretableShowsOutOfRangeAndContradictoryFigures() async {
        let core = await Scenario.uninterpretable.start()
        let cards = contents(of: core)

        #expect(quotas(cards[.claude]).map(\.value) == [.uninterpretable, .uninterpretable])
        #expect(quotas(cards[.cursor]).map(\.value) == [.percent(18.5, calculated: false), .uninterpretable])
    }

    @Test func noSessionShowsEveryCardSignedOut() async {
        let core = await Scenario.noSession.start()

        #expect(core.state.cards.map(\.content) == [.failed(.noSession), .failed(.noSession), .failed(.noSession)])
    }

    @Test func sessionExpiredShowsEverySessionRejected() async {
        let core = await Scenario.sessionExpired.start()

        #expect(core.state.cards.map(\.content) == [.failed(.sessionExpired), .failed(.sessionExpired), .failed(.sessionExpired)])
    }

    @Test func reusedSessionRejectedKeepsEveryReadingStaleWithoutCallingTheSessionExpired() async {
        let core = await Scenario.reusedSessionRejected.start()

        for card in core.state.cards {
            guard case .stale(let quotas, .reusedSessionRejected) = card.content else {
                Issue.record("Not stale: \(card)")
                continue
            }
            #expect(quotas.allSatisfy { $0.isStale && $0.readAt == Samples.readingMoment })
        }
        #expect(core.now() > Samples.readingMoment)
    }

    @Test func sessionAccessDeniedShowsTheKeychainAccessDenied() async {
        let core = await Scenario.sessionAccessDenied.start()

        #expect(contents(of: core)[.claude] == .failed(.sessionAccessDenied))
    }

    @Test func unavailableSessionStoresShowDistinctFailures() async {
        let core = await Scenario.unavailableSessionStores.start()

        #expect(contents(of: core)[.claude] == .failed(.sessionStoreUnavailable))
        #expect(contents(of: core)[.cursor] == .failed(.sessionStoreBusy))
    }

    @Test func incompatibleSessionShowsEverySessionInAnUnknownFormat() async {
        let core = await Scenario.incompatibleSession.start()

        #expect(core.state.cards.map(\.content) == [.failed(.incompatibleSession), .failed(.incompatibleSession), .failed(.incompatibleSession)])
    }

    @Test func incompatibleResponseShowsEveryResponseNotUnderstood() async {
        let core = await Scenario.incompatibleResponse.start()

        #expect(core.state.cards.map(\.content) == [.failed(.incompatibleResponse), .failed(.incompatibleResponse), .failed(.incompatibleResponse)])
    }

    @Test func incompatibleCursorResetShowsItsOwnFailure() async {
        let core = await Scenario.incompatibleCursorReset.start()

        #expect(contents(of: core)[.cursor] == .failed(.incompatibleResetFormat))
    }

    @Test func networkFailuresShowTheNetworkAndServerFailuresWithoutAPreviousReading() async {
        let core = await Scenario.networkFailures.start()

        #expect(core.state.cards.map(\.content) == [.failed(.offline), .failed(.timedOut), .failed(.serverError(status: 503))])
    }

    @Test func refusedShowsARefusedQueryAndTheProviderAskingToWait() async {
        let core = await Scenario.refused.start()

        #expect(core.state.cards.map(\.content) == [
            .failed(.accessRefused),
            .failed(.rateLimited(until: Samples.readingMoment.addingTimeInterval(600))),
            .failed(.rateLimited(until: nil)),
        ])
    }

    @Test func longContentAddsLongNamedLimitsNextToAStaleCard() async {
        let core = await Scenario.longContent.start()
        let cards = contents(of: core)
        let longNames = Scenario.longLimitNames

        #expect(quotas(cards[.claude]).map(\.period) == [
            .fiveHours, .weekly, .limit("Sonnet", .weekly), .limit("Opus", .weekly),
            .limit(longNames[0], .weekly), .limit(longNames[1], .weekly),
        ])
        let codexLimits = (["Sample-Model"] + longNames).flatMap {
            [QuotaPeriod.limit($0, .fiveHours), .limit($0, .weekly)]
        }
        #expect(quotas(cards[.codex]).map(\.period) == [.fiveHours, .weekly] + codexLimits)
        guard case .stale(let cursor, .timedOut) = cards[.cursor] else {
            Issue.record("Not stale: \(String(describing: cards[.cursor]))")
            return
        }
        #expect(cursor.allSatisfy { $0.isStale })
    }

    @Test func bankedResetsShowTheCodexCountNextToItsQuotas() async {
        let core = await Scenario.bankedResets.start()
        let codex = core.state.cards.first { $0.provider == .codex }

        #expect(codex?.bankedResets == 3)
        #expect(quotas(codex?.content).map(\.value) == [.percent(12, calculated: false), .percent(41, calculated: false)])
        #expect(core.state.cards.filter { $0.provider != .codex }.allSatisfy { $0.bankedResets == nil })
    }

    /// The real panel opens its core again every time it is shown.
    @Test(arguments: Scenario.all)
    func reopeningThePanelKeepsShowingTheScenario(_ scenario: Scenario) async {
        let core = await scenario.start()
        let shown = core.state

        core.panelClosed()
        core.panelOpened()
        // A scenario still querying keeps its query held, so it never finishes.
        if !shown.isQuerying {
            await core.queriesFinished()
        }

        #expect(core.state == shown)
    }

    /// The Actualizar button queries again, and the fake answers the same.
    @Test(arguments: Scenario.all)
    func refreshingKeepsShowingTheScenario(_ scenario: Scenario) async {
        let core = await scenario.start()
        let shown = core.state

        core.refresh()
        if !shown.isQuerying {
            await core.queriesFinished()
        }

        #expect(core.state == shown)
    }
}

extension Scenario: @retroactive CustomTestStringConvertible {
    public var testDescription: String {
        id
    }
}
