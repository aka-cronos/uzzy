import Foundation
import Testing
import UzzyCore

/// The Codex card, end to end: the ChatGPT session of Codex CLI, its usage
/// query and its quotas, each named by the length of its quota period.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CodexPanelTests {
    let clock = ManualClock(Samples.readingMoment)
    let claudeSessionReader = ControlledSessionReader()
    let codexSessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore
    // 2026-09-23T18:00:00Z and 2026-09-28T06:00:00Z, from the sample response.
    let fiveHourReset = Date(timeIntervalSince1970: 1_790_186_400)
    let weeklyReset = Date(timeIntervalSince1970: 1_790_575_200)

    init() {
        core = UsageCore(
            claudeSessionReader: claudeSessionReader,
            codexSessionReader: codexSessionReader,
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    func codexContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .codex })?.content
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test func openingThePanelShowsEachCodexQuotaSeparately() async {
        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(12, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .weekly, value: .percent(41, calculated: false), reset: .at(weeklyReset), readAt: Samples.readingMoment),
        ]))
    }

    /// The provider may send its windows in any order, so position says nothing.
    @Test func quotaPeriodsAreNamedByTheirLengthNotByTheirPosition() async {
        await transport.answer(with: .codex(rateLimit: """
            {
              "primary_window": {"used_percent": 41, "limit_window_seconds": 604800, "reset_at": 1790575200},
              "secondary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790186400}
            }
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(12, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .weekly, value: .percent(41, calculated: false), reset: .at(weeklyReset), readAt: Samples.readingMoment),
        ]))
    }

    @Test(arguments: [3_600, 86_400, 2_592_000])
    func aQuotaPeriodOfAnotherLengthIsNamedByThatLength(seconds: Int) async {
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 7.5, "limit_window_seconds": \(seconds), "reset_at": 1790186400}}
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .lasting(seconds: seconds), value: .percent(7.5, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
        ]))
    }

    @Test func additionalLimitsAreShownAsSeparateQuotasNamedByTheProvider() async {
        await transport.answer(with: .codex(
            rateLimit: """
                {"primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790186400}}
                """,
            additional: """
                [{
                  "limit_name": "Sample-Model",
                  "metered_feature": "sample_feature",
                  "rate_limit": {
                    "allowed": true,
                    "limit_reached": false,
                    "primary_window": {"used_percent": 3, "limit_window_seconds": 18000, "reset_at": 1790186400},
                    "secondary_window": {"used_percent": 9, "limit_window_seconds": 604800, "reset_at": 1790575200}
                  }
                }]
                """
        ), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(12, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .limit("Sample-Model", .fiveHours), value: .percent(3, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .limit("Sample-Model", .weekly), value: .percent(9, calculated: false), reset: .at(weeklyReset), readAt: Samples.readingMoment),
        ]))
    }

    /// A named limit is one quota per name and period, however many entries
    /// of the response repeat it.
    @Test func copiesOfANamedLimitThatAgreeAreShownOnce() async {
        await transport.answer(with: .codex(
            rateLimit: "null",
            additional: """
                [
                  {"limit_name": "Model", "rate_limit": {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": 1790186400}}},
                  {"limit_name": "Model", "rate_limit": {"primary_window": {"used_percent": 10.5, "limit_window_seconds": 18000, "reset_at": 1790186430}}}
                ]
                """
        ), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .limit("Model", .fiveHours), value: .percent(10, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
        ]))
    }

    /// Copies that contradict each other are one quota whose figure cannot be
    /// trusted, whichever copy comes first.
    @Test(arguments: [(10, 90), (90, 10)])
    func contradictoryCopiesOfANamedLimitAreOneUninterpretableQuota(first: Int, second: Int) async {
        await transport.answer(with: .codex(
            rateLimit: "null",
            additional: """
                [
                  {"limit_name": "Model", "rate_limit": {"primary_window": {"used_percent": \(first), "limit_window_seconds": 18000, "reset_at": 1790186400}}},
                  {"limit_name": "Model", "rate_limit": {"primary_window": {"used_percent": \(second), "limit_window_seconds": 18000, "reset_at": 1790186400}}}
                ]
                """
        ), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .limit("Model", .fiveHours), value: .uninterpretable, reset: .at(fiveHourReset), readAt: Samples.readingMoment),
        ]))
    }

    /// Copies that disagree on the reset give no date to trust, so the reset
    /// is unknown and the agreeing figure is kept.
    @Test(arguments: [(1790186400, 1790190000), (1790190000, 1790186400)])
    func copiesOfANamedLimitWithContradictoryResetsHaveAnUnknownReset(first: Int, second: Int) async {
        await transport.answer(with: .codex(
            rateLimit: "null",
            additional: """
                [
                  {"limit_name": "Model", "rate_limit": {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": \(first)}}},
                  {"limit_name": "Model", "rate_limit": {"secondary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": \(second)}}}
                ]
                """
        ), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .limit("Model", .fiveHours), value: .percent(10, calculated: false), reset: .unknown, readAt: Samples.readingMoment),
        ]))
    }

    /// Only the same name over the same period is reconciled. A name's quotas
    /// stay together, in the order the names first appear, the shortest first.
    @Test func namedLimitsAreReconciledOnlyWithTheSameNameAndPeriod() async {
        await transport.answer(with: .codex(
            rateLimit: """
                {"primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790186400}}
                """,
            additional: """
                [
                  {"limit_name": "Model-A", "rate_limit": {"primary_window": {"used_percent": 30, "limit_window_seconds": 604800, "reset_at": 1790575200}}},
                  {"limit_name": "Model-B", "rate_limit": {"primary_window": {"used_percent": 20, "limit_window_seconds": 18000, "reset_at": 1790186400}}},
                  {"limit_name": "Model-A", "rate_limit": {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": 1790186400}}},
                  {"limit_name": "Model-A", "rate_limit": {"primary_window": {"used_percent": 30, "limit_window_seconds": 604800, "reset_at": 1790575200}}}
                ]
                """
        ), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(12, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .limit("Model-A", .fiveHours), value: .percent(10, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .limit("Model-A", .weekly), value: .percent(30, calculated: false), reset: .at(weeklyReset), readAt: Samples.readingMoment),
            Quota(period: .limit("Model-B", .fiveHours), value: .percent(20, calculated: false), reset: .at(fiveHourReset), readAt: Samples.readingMoment),
        ]))
    }

    @Test func aQuotaWithoutUsageOrResetShowsWhatIsMissingWithoutInventingIt() async {
        await transport.answer(with: .codex(rateLimit: """
            {
              "primary_window": {"used_percent": null, "limit_window_seconds": 18000, "reset_at": 1790186400},
              "secondary_window": {"used_percent": 41, "limit_window_seconds": 604800, "reset_at": null}
            }
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .unavailable, reset: .at(fiveHourReset), readAt: Samples.readingMoment),
            Quota(period: .weekly, value: .percent(41, calculated: false), reset: .unknown, readAt: Samples.readingMoment),
        ]))
    }

    /// A reset more than a year away from the reading, ahead or behind,
    /// cannot be the quota's reset. The figure is kept.
    @Test(arguments: ["1e30", "-1e30", "1.7976931348623157e308", "0", "1853882000", "1726000000"])
    func aResetOutsideAYearOfTheReadingIsUnknownAndTheFigureIsKept(resetAt: String) async {
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": \(resetAt)}}
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(10, calculated: false), reset: .unknown, readAt: Samples.readingMoment),
        ]))
        // The other cards are not affected.
        guard case .quotas = core.state.cards.first(where: { $0.provider == .claude })?.content else {
            Issue.record("The Claude card does not show its quotas")
            return
        }
    }

    /// The bounds are a year either side of the reading, leap years included.
    @Test(arguments: [366.0, -366.0])
    func aResetWithinAYearOfTheReadingIsKept(days: Double) async {
        let reset = Samples.readingMoment.addingTimeInterval(days * 86_400)
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": \(reset.timeIntervalSince1970)}}
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(
                period: .fiveHours,
                value: .percent(10, calculated: false),
                reset: days > 0 ? .at(reset) : .pendingConfirmation,
                readAt: Samples.readingMoment,
                isStale: days < 0
            ),
        ]))
    }

    @Test(arguments: ["1e400", "-1e400"])
    func anUnrepresentableResetKeepsTheValidPercentage(reset: String) async {
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": \(reset)}}
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(10, calculated: false),
                  reset: .unknown, readAt: Samples.readingMoment),
        ]))
    }

    @Test func anUnrepresentableCopyDoesNotBorrowAnotherCopysReset() async {
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": 1e400},
             "secondary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": 1790186400}}
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .percent(10, calculated: false),
                  reset: .unknown, readAt: Samples.readingMoment),
        ]))
    }

    @Test func aPercentOutOfRangeIsUninterpretable() async {
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 104, "limit_window_seconds": 18000, "reset_at": 1790186400}}
            """), for: .codex)

        await openPanel()

        #expect(codexContent() == .quotas([
            Quota(period: .fiveHours, value: .uninterpretable, reset: .at(fiveHourReset), readAt: Samples.readingMoment),
        ]))
    }

    /// Without its length a window cannot be named, and it is never named by
    /// its position.
    @Test(arguments: [
        #"{"primary_window": {"used_percent": 12, "reset_at": 1790186400}}"#,
        #"{"primary_window": null, "secondary_window": null}"#,
        "null",
    ])
    func aResponseWithoutNamedWindowsIsIncompatible(rateLimit: String) async {
        await transport.answer(with: .codex(rateLimit: rateLimit), for: .codex)

        await openPanel()

        #expect(codexContent() == .failed(.incompatibleResponse))
    }

    /// E.g. Codex CLI signed in with an API key.
    @Test func aSessionWithoutSubscriptionQuotasSaysSoAndIsNotQueried() async {
        await codexSessionReader.answer(with: .withoutSubscriptionQuotas)

        await openPanel()
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        #expect(codexContent() == .failed(.sessionWithoutSubscriptionQuotas))
        #expect(await transport.requests(to: .codex).isEmpty)
    }

    @Test func anotherCodexAccountClearsThePreviousReadingAndIsQueriedWithItsOwnAccount() async {
        await openPanel()

        await codexSessionReader.answer(with: .session(Session(accessToken: "other-token", accountID: "other-account")))
        await transport.hold(.codex)
        core.refresh()
        await transport.waitForRequests(4)

        #expect(codexContent() == .loadingNewAccount)
        let request = await transport.requests(to: .codex).last
        #expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "other-account")
        await transport.release()
        await core.queriesFinished()
    }

    @Test func queriesCodexUsageWithTheAccessTokenAndTheAccount() async {
        await openPanel()

        let requests = await transport.requests(to: .codex)
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "GET")
        #expect(requests.first?.url == URL(string: "https://chatgpt.com/backend-api/wham/usage"))
        #expect(requests.first?.allHTTPHeaderFields == [
            "Authorization": "Bearer sample-token",
            "ChatGPT-Account-Id": "sample-account",
        ])
    }
}
