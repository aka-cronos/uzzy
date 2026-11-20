import Foundation
import Testing
import UzzyCore

/// The Antigravity card, end to end: the Google session Antigravity keeps,
/// its account query, its quota summary and the limits of each model group.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AntigravityPanelTests {
    let clock = ManualClock(Samples.readingMoment)
    let antigravitySessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore

    init() {
        core = UsageCore(
            claudeSessionReader: ControlledSessionReader(),
            codexSessionReader: ControlledSessionReader(),
            cursorSessionReader: ControlledSessionReader(),
            antigravitySessionReader: antigravitySessionReader,
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    func antigravityCard() -> Card? {
        core.state.cards.first(where: { $0.provider == .antigravity })
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test func openingThePanelShowsEachLimitOfEachModelGroup() async {
        await openPanel()

        #expect(antigravityCard()?.content == .quotas([
            // 2026-09-23T18:17:00Z
            Quota(period: .limit("Gemini", .fiveHours), value: .percent(4, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_187_420)), readAt: Samples.readingMoment),
            // 2026-09-28T12:32:00Z
            Quota(period: .limit("Gemini", .weekly), value: .percent(36, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_598_720)), readAt: Samples.readingMoment),
            // Untouched: its resets are the reading moment plus each window.
            Quota(period: .limit("Claude and GPT", .fiveHours), value: .percent(0, calculated: false),
                  reset: nil, readAt: Samples.readingMoment),
            Quota(period: .limit("Claude and GPT", .weekly), value: .percent(0, calculated: false),
                  reset: nil, readAt: Samples.readingMoment),
            // 2026-09-29T08:00:00Z
            Quota(period: .limit("Gemini 4 Argon", .weekly), value: .percent(12, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_668_800)), readAt: Samples.readingMoment),
        ]))
    }

    @Test func asksForTheAccountAndThenForTheQuotaSummaryOfItsProject() async throws {
        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.map(\.url) == [
            URL(string: "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:loadCodeAssist"),
            URL(string: "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:retrieveUserQuotaSummary"),
        ])
        #expect(requests.allSatisfy { $0.httpMethod == "POST" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token" })
        // Cloud Code refuses the summary to a client that is not Antigravity,
        // and leaves out the groups a plan keeps apart (Gemini 4 Argon) unless
        // it presents itself as Antigravity's app ("hub").
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("antigravity/hub/") == true })
        let summaryBody = try #require(requests.last?.httpBody)
        #expect(try JSONSerialization.jsonObject(with: summaryBody) as? [String: String] == ["project": "sample-project"])
    }

    @Test func anAccountWithoutAProjectAsksForTheSummaryWithoutOne() async throws {
        await transport.answerAntigravityAccount(with: .json(#"{"paidTier": {"id": "g1-pro-tier"}}"#))

        await openPanel()

        let summaryBody = try #require(await transport.quotaRequests(to: .antigravity).last?.httpBody)
        #expect(try JSONSerialization.jsonObject(with: summaryBody) as? [String: String] == [:])
        guard case .quotas = antigravityCard()?.content else {
            Issue.record("The Antigravity card does not show its quotas")
            return
        }
    }

    @Test func thePlanIsThePaidTierByGooglesName() async {
        await openPanel()

        #expect(antigravityCard()?.plan == "Google AI Pro")
    }

    @Test(arguments: [
        ("g1-pro-tier", "Google AI Pro"),
        ("g1-ultra-tier", "Google AI Ultra"),
    ])
    func everyKnownPaidTierShowsItsPlan(tier: String, plan: String) async {
        await transport.answerAntigravityAccount(with: .json(#"{"paidTier": {"id": "\#(tier)"}}"#))

        await openPanel()

        #expect(antigravityCard()?.plan == plan)
    }

    /// The current tier is generic, and a paid tier Uzzy does not know is
    /// never shown by its identifier.
    @Test(arguments: [
        #"{"currentTier": {"id": "free-tier", "name": "Antigravity"}}"#,
        #"{"paidTier": {"id": "g1-sample-tier", "name": "Sample Plan"}}"#,
        #"{"paidTier": "g1-pro-tier"}"#,
    ])
    func anUnknownOrMissingPaidTierShowsNoPlan(account: String) async {
        await transport.answerAntigravityAccount(with: .json(account))

        await openPanel()

        #expect(antigravityCard()?.plan == nil)
        guard case .quotas = antigravityCard()?.content else {
            Issue.record("The Antigravity card does not show its quotas")
            return
        }
    }

    /// A group the summary adds goes by its own name; the two groups of
    /// Antigravity's quota screen keep their short names whatever it calls
    /// them.
    @Test func groupsAreNamedByTheirBucketsOrByTheSummary() async {
        await transport.answer(with: .json(#"""
            {"groups": [
              {"displayName": "Renamed Gemini group", "buckets": [
                {"bucketId": "gemini-5h", "window": "5h", "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0.5}]},
              {"displayName": " Sample Group ", "buckets": [
                {"bucketId": "sample-5h", "window": "5h", "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0.25}]},
              {"displayName": "", "buckets": [
                {"bucketId": "unnamed-5h", "window": "5h", "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0.5}]}
            ]}
            """#), for: .antigravity)

        await openPanel()

        guard case .quotas(let quotas) = antigravityCard()?.content else {
            Issue.record("The Antigravity card does not show its quotas")
            return
        }
        #expect(quotas.map(\.period) == [.limit("Gemini", .fiveHours), .limit("Sample Group", .fiveHours)])
        #expect(quotas.map(\.value) == [.percent(50, calculated: false), .percent(75, calculated: false)])
    }

    /// A bucket of a window Uzzy does not know is left out, and a missing
    /// fraction is never taken as zero.
    @Test func unknownWindowsAreLeftOutAndAMissingFractionIsUnavailable() async {
        await transport.answer(with: .json(#"""
            {"groups": [{"displayName": "Gemini Models", "buckets": [
              {"bucketId": "gemini-daily", "window": "daily", "resetTime": "2026-09-24T00:00:00Z", "remainingFraction": 0.5},
              {"bucketId": "gemini-weekly", "window": "weekly", "resetTime": "2026-09-28T12:32:00Z"}
            ]}]}
            """#), for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .quotas([
            Quota(period: .limit("Gemini", .weekly), value: .unavailable,
                  reset: .at(Date(timeIntervalSince1970: 1_790_598_720)), readAt: Samples.readingMoment),
        ]))
    }

    /// A limit the plan turns off is left out, and a group left with none
    /// shows nothing. Only `true` turns a limit off.
    @Test func disabledLimitsAreLeftOut() async {
        await transport.answer(with: .json(#"""
            {"groups": [
              {"displayName": "Gemini Models", "buckets": [
                {"bucketId": "gemini-5h", "window": "5h", "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0.9, "disabled": false},
                {"bucketId": "gemini-weekly", "window": "weekly", "resetTime": "2026-09-28T12:32:00Z", "remainingFraction": 0.8, "disabled": "true"}
              ]},
              {"displayName": "Claude and GPT models", "buckets": [
                {"bucketId": "3p-5h", "window": "5h", "resetTime": "2026-09-23T19:32:00Z", "remainingFraction": 0.5, "disabled": true},
                {"bucketId": "3p-weekly", "window": "weekly", "resetTime": "2026-09-30T14:32:00Z", "remainingFraction": 0.75}
              ]},
              {"displayName": "Gemini 4 Argon", "buckets": [
                {"bucketId": "gemini-argon-wtu-weekly", "window": "weekly", "resetTime": "2026-09-29T08:00:00Z", "remainingFraction": 1, "disabled": true}
              ]}
            ]}
            """#), for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .quotas([
            // 2026-09-23T18:17:00Z
            Quota(period: .limit("Gemini", .fiveHours), value: .percent(10, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_187_420)), readAt: Samples.readingMoment),
            // 2026-09-28T12:32:00Z
            Quota(period: .limit("Gemini", .weekly), value: .percent(20, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_598_720)), readAt: Samples.readingMoment),
            // 2026-09-30T14:32:00Z
            Quota(period: .limit("Claude and GPT", .weekly), value: .percent(25, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_778_720)), readAt: Samples.readingMoment),
        ]))
    }

    @Test(arguments: [#"{}"#, #"{"groups": []}"#, #"{"groups": [{"displayName": "Gemini Models", "buckets": [{"window": "daily"}]}]}"#, "<html></html>"])
    func aSummaryWithoutAnyKnownLimitIsNotUnderstood(summary: String) async {
        await transport.answer(with: .json(summary), for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .failed(.incompatibleResponse))
    }

    @Test func anExhaustedLimitIsFullyUsed() async {
        await transport.answer(with: .json(#"""
            {"groups": [{"displayName": "Gemini Models", "buckets": [
              {"bucketId": "gemini-5h", "window": "5h", "resetTime": "2026-09-23T18:17:00Z", "remainingFraction": 0}
            ]}]}
            """#), for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .quotas([
            Quota(period: .limit("Gemini", .fiveHours), value: .percent(100, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_187_420)), readAt: Samples.readingMoment),
        ]))
    }

    /// Either query may reject the session.
    @Test(arguments: [(401, Failure.sessionExpired), (403, .accessRefused)])
    func aRejectedAccountQueryAsksForNothingElse(status: Int, failure: Failure) async {
        await transport.answerAntigravityAccount(with: .status(status))

        await openPanel()

        #expect(antigravityCard()?.content == .failed(failure))
        #expect(await transport.quotaRequests(to: .antigravity).count == 1)
    }

    @Test(arguments: [(401, Failure.sessionExpired), (403, .accessRefused)])
    func aRejectedSummaryRejectsTheSession(status: Int, failure: Failure) async {
        await transport.answer(with: .status(status), for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .failed(failure))
    }

    @Test func otherCardsAreNotAffectedByAnAntigravityFailure() async {
        await transport.answer(with: .networkError, for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .failed(.offline))
        for card in core.state.cards where card.provider != .antigravity {
            guard case .quotas = card.content else {
                Issue.record("\(card.provider) does not show its quotas")
                continue
            }
        }
    }

    // MARK: Renewal while the panel is open

    /// Antigravity renews its token only while it runs, so an expired
    /// session is common. While the panel is open, the card reads the
    /// session again on its own and queries once Antigravity has renewed it.
    @Test func anExpiredSessionRenewedByAntigravityIsQueriedOnItsOwn() async {
        await transport.answer(with: .status(401), for: .antigravity)
        await openPanel()
        #expect(antigravityCard()?.content == .failed(.sessionExpired))

        await antigravitySessionReader.answer(with: .session(Session(accessToken: "renewed-token", accountID: "sample-account")))
        await transport.answer(with: .antigravitySample, for: .antigravity)
        clock.advance(by: Self.recheck)
        await core.queriesFinished()

        guard case .quotas = antigravityCard()?.content else {
            Issue.record("The renewed session was not queried")
            return
        }
        #expect(await transport.quotaRequests(to: .antigravity).last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token")
    }

    /// Reading the session again costs no query while it is the one rejected.
    @Test func anUnrenewedSessionIsReadAgainButNeverQueriedAgain() async {
        await transport.answer(with: .status(401), for: .antigravity)
        await openPanel()
        let sent = await transport.quotaRequests(to: .antigravity).count
        let reads = await antigravitySessionReader.reads

        for _ in 0 ..< 3 {
            clock.advance(by: Self.recheck)
            await core.queriesFinished()
        }

        #expect(await antigravitySessionReader.reads == reads + 3)
        #expect(await transport.quotaRequests(to: .antigravity).count == sent)
        #expect(antigravityCard()?.content == .failed(.sessionExpired))
    }

    @Test func aClosedPanelNeverReadsTheSessionOnItsOwn() async {
        await transport.answer(with: .status(401), for: .antigravity)
        await openPanel()
        core.panelClosed()
        let reads = await antigravitySessionReader.reads

        clock.advance(by: Self.recheck * 3)
        await core.queriesFinished()

        #expect(await antigravitySessionReader.reads == reads)
    }

    static let recheck: TimeInterval = 30
}

