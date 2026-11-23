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
            URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:loadCodeAssist"),
            URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary"),
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

    // MARK: Local daemon sessions

    @Test func aLocalDaemonSessionQueriesGetUserStatusAndRetrieveUserQuotaSummary() async throws {
        let daemon = Session(
            accessToken: "local-csrf",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50001")
        )
        await antigravitySessionReader.answer(with: .session(daemon))
        // Ultra accounts report `planInfo.planName = "Pro"` alongside
        // `userTier.id = "g1-ultra-tier"`; only `userTier.id` names the plan.
        await transport.answerAntigravityDaemonStatus(with: .json(#"""
            {
              "userStatus": {
                "email": "sample@example.com",
                "userTier": {"id": "g1-ultra-tier", "name": "Google AI Ultra"},
                "planStatus": {"planInfo": {"planName": "Pro", "teamsTier": "TEAMS_TIER_PRO"}}
              }
            }
            """#))

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.map(\.url) == [
            URL(string: "http://127.0.0.1:50001/exa.language_server_pb.LanguageServerService/GetUserStatus"),
            URL(string: "http://127.0.0.1:50001/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"),
        ])
        #expect(requests.allSatisfy { $0.httpMethod == "POST" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-codeium-csrf-token") == "local-csrf" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(antigravityCard()?.plan == "Google AI Ultra")
        guard case .quotas(let quotas) = antigravityCard()?.content else {
            Issue.record("The Antigravity card does not show its quotas from the local daemon")
            return
        }
        #expect(quotas.count == 5)
    }

    /// Antigravity's local service caches summaries for several minutes: an
    /// untouched 0% bucket whose reset lags 6 minutes behind `now + window`
    /// hides its reset, while one 20 minutes behind keeps its reset.
    @Test func anUntouchedAntigravityWindowToleratesCachedResetLag() async {
        // Reading moment is 2026-09-23T14:32:00Z. `now + 5h` is 19:32:00Z.
        // 19:26:00Z is 6 minutes behind (untouched, cached); 19:12:00Z is 20 minutes behind (started).
        await transport.answer(with: .json(#"""
            {"groups": [
              {"displayName": "Gemini Models", "buckets": [
                {"bucketId": "gemini-5h", "window": "5h", "resetTime": "2026-09-23T19:26:00Z", "remainingFraction": 1}
              ]},
              {"displayName": "Claude and GPT models", "buckets": [
                {"bucketId": "3p-5h", "window": "5h", "resetTime": "2026-09-23T19:12:00Z", "remainingFraction": 1}
              ]}
            ]}
            """#), for: .antigravity)

        await openPanel()

        #expect(antigravityCard()?.content == .quotas([
            Quota(period: .limit("Gemini", .fiveHours), value: .percent(0, calculated: false),
                  reset: nil, readAt: Samples.readingMoment),
            // 2026-09-23T19:12:00Z
            Quota(period: .limit("Claude and GPT", .fiveHours), value: .percent(0, calculated: false),
                  reset: .at(Date(timeIntervalSince1970: 1_790_190_720)), readAt: Samples.readingMoment),
        ]))
    }

    /// When a local daemon stops while the panel is open, the automatic refresh
    /// marks the reused session unconfirmed (keeping stale readings) and the
    /// 30-second recheck picks up a restarted daemon on a new port.
    @Test func aStoppedDaemonMarksStaleAndRecoversWhenRestarted() async {
        let initialDaemon = Session(
            accessToken: "csrf-1",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50001")
        )
        await antigravitySessionReader.answer(with: .session(initialDaemon))
        await openPanel()
        guard case .quotas = antigravityCard()?.content else {
            Issue.record("Expected initial daemon quotas")
            return
        }

        // Daemon stops before the 5-minute automatic refresh.
        await transport.answerAntigravityDaemonStatus(with: .networkError)
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        guard case .stale(_, failure: .reusedSessionRejected) = antigravityCard()?.content else {
            Issue.record("Expected stale reusedSessionRejected, got \(String(describing: antigravityCard()?.content))")
            return
        }

        // Daemon restarts on a new port; the 30-second recheck recovers on its own.
        let restartedDaemon = Session(
            accessToken: "csrf-2",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50002")
        )
        await antigravitySessionReader.answer(with: .session(restartedDaemon))
        await transport.answerAntigravityDaemonStatus(with: .antigravityDaemonStatusSample)
        clock.advance(by: Self.recheck)
        await core.queriesFinished()

        guard case .quotas = antigravityCard()?.content else {
            Issue.record("Expected recovery after daemon restarted")
            return
        }
        #expect(await transport.quotaRequests(to: .antigravity).last?.url?.port == 50002)
    }

    /// A live daemon that times out (e.g. while waiting on Google upstream)
    /// stays `.timedOut` rather than rejecting the session, so the scheduled
    /// retry recovers with the same port and CSRF token.
    @Test func aSlowDaemonTimesOutAndRetriesWithTheSameSession() async {
        let daemon = Session(
            accessToken: "csrf-1",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50001")
        )
        await antigravitySessionReader.answer(with: .session(daemon))
        await openPanel()
        guard case .quotas = antigravityCard()?.content else {
            Issue.record("Expected initial daemon quotas")
            return
        }

        await transport.answerAntigravityDaemonQuota(with: .timeout)
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        guard case .stale(_, failure: .timedOut) = antigravityCard()?.content else {
            Issue.record("Expected stale timedOut, got \(String(describing: antigravityCard()?.content))")
            return
        }

        // Same daemon responds on the scheduled 30-second retry.
        await transport.answerAntigravityDaemonQuota(with: .antigravityDaemonQuotaSample)
        clock.advance(by: Self.recheck)
        await core.queriesFinished()

        guard case .quotas = antigravityCard()?.content else {
            Issue.record("Expected recovery on scheduled retry with the same daemon session")
            return
        }
        #expect(await transport.quotaRequests(to: .antigravity).last?.url?.port == 50001)
    }

    @Test func anUnreachableDaemonOnFreshReadIsSessionExpiredNotOffline() async {
        let daemon = Session(
            accessToken: "csrf-1",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50001")
        )
        await antigravitySessionReader.answer(with: .session(daemon))
        await transport.answerAntigravityDaemonStatus(with: .networkError)

        await openPanel()

        #expect(antigravityCard()?.content == .failed(.sessionExpired))
    }

    @Test(arguments: [(401, Failure.sessionExpired), (403, .accessRefused)])
    func aRejectedDaemonSessionRechecksAndRecovers(status: Int, failure: Failure) async {
        let initialDaemon = Session(
            accessToken: "csrf-1",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50001")
        )
        await antigravitySessionReader.answer(with: .session(initialDaemon))
        await transport.answerAntigravityDaemonStatus(with: .status(status))

        await openPanel()
        #expect(antigravityCard()?.content == .failed(failure))

        let renewedDaemon = Session(
            accessToken: "csrf-2",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50002")
        )
        await antigravitySessionReader.answer(with: .session(renewedDaemon))
        await transport.answerAntigravityDaemonStatus(with: .antigravityDaemonStatusSample)
        clock.advance(by: Self.recheck)
        await core.queriesFinished()

        guard case .quotas = antigravityCard()?.content else {
            Issue.record("Expected recovery after daemon token changed")
            return
        }
    }

    @Test func reopeningWhileDaemonReadingIsFreshSkipsTheQuery() async {
        let daemon = Session(
            accessToken: "csrf-1",
            accountID: "sample@example.com",
            endpoint: URL(string: "http://127.0.0.1:50001")
        )
        await antigravitySessionReader.answer(with: .session(daemon))
        await openPanel()
        let countBefore = await transport.quotaRequests(to: .antigravity).count

        core.panelClosed()
        clock.advance(by: 60)
        await openPanel()

        #expect(await transport.quotaRequests(to: .antigravity).count == countBefore)
    }

    static let recheck: TimeInterval = 30
}

