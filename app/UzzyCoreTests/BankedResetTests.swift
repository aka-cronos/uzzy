import Foundation
import Testing
import UzzyCore

/// The Codex card's banked resets: the count the account holds, read from
/// the same usage response as its quotas and shown only with them.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BankedResetTests {
    let clock = ManualClock(Samples.readingMoment)
    let codexSessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore
    let windows = """
        {"primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790186400}}
        """

    init() {
        core = UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: codexSessionReader,
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    func codexCard() -> Card? {
        core.state.cards.first(where: { $0.provider == .codex })
    }

    func answer(resetCredits: String?) async {
        await transport.answer(with: .codex(rateLimit: windows, resetCredits: resetCredits), for: .codex)
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    func showsQuotas() -> Bool {
        if case .quotas = codexCard()?.content { true } else { false }
    }

    /// Opens the panel on a response holding 3 banked resets.
    func showThreeBankedResets() async {
        await answer(resetCredits: #"{"available_count": 3, "applicable_available_count": 3}"#)
        await openPanel()
        #expect(codexCard()?.bankedResets == 3)
    }

    // MARK: Which count

    @Test(arguments: [
        (#"{"available_count": 1}"#, 1),
        (#"{"available_count": 12, "applicable_available_count": 0}"#, 12),
        (#"{"available_count": 9223372036854775807}"#, Int.max),
        // Integral-valued number literals decode exactly.
        (#"{"available_count": 2.0}"#, 2),
        (#"{"available_count": 2e0}"#, 2),
    ])
    func aPositiveIntegerCountIsShown(resetCredits: String, count: Int) async {
        await answer(resetCredits: resetCredits)

        await openPanel()

        #expect(codexCard()?.bankedResets == count)
    }

    /// Whatever the count, a problem in it never fails the Codex reading.
    @Test(arguments: [
        nil,
        "null",
        "3",
        "[]",
        #""3""#,
        "{}",
        #"{"applicable_available_count": 2}"#,
        #"{"available_count": null}"#,
        #"{"available_count": 0}"#,
        #"{"available_count": -1}"#,
        #"{"available_count": 1.5}"#,
        #"{"available_count": 9223372036854775808}"#,
        #"{"available_count": -9223372036854775809}"#,
        #"{"available_count": "2"}"#,
        #"{"available_count": true}"#,
        #"{"available_count": [2]}"#,
        #"{"available_count": {"value": 2}}"#,
    ] as [String?])
    func aMissingOrUninterpretableCountIsHiddenAndTheQuotasStillShow(resetCredits: String?) async {
        await answer(resetCredits: resetCredits)

        await openPanel()

        #expect(codexCard()?.bankedResets == nil)
        #expect(showsQuotas())
    }

    /// The official clients show the total; the applicable count says
    /// nothing about it, even when the two differ.
    @Test(arguments: [
        (#"{"available_count": 3}"#, 3),
        (#"{"available_count": 3, "applicable_available_count": 3}"#, 3),
        (#"{"available_count": 3, "applicable_available_count": 1}"#, 3),
        (#"{"available_count": 1, "applicable_available_count": 5}"#, 1),
    ])
    func theApplicableCountNeverChangesTheCountShown(resetCredits: String, count: Int) async {
        await answer(resetCredits: resetCredits)

        await openPanel()

        #expect(codexCard()?.bankedResets == count)
    }

    @Test func theSampleResponseHoldsNoBankedResets() async {
        await openPanel()

        #expect(codexCard()?.bankedResets == nil)
        #expect(showsQuotas())
    }

    @Test func aResponseWithoutQuotasShowsNoBankedResets() async {
        await transport.answer(
            with: .codex(rateLimit: "null", resetCredits: #"{"available_count": 3}"#), for: .codex
        )

        await openPanel()

        #expect(codexCard()?.content == .failed(.incompatibleResponse))
        #expect(codexCard()?.bankedResets == nil)
    }

    @Test func claudeAndCursorCardsShowNoBankedResets() async {
        let core = UsageCore(
            claudeSessionReader: ControlledSessionReader(),
            codexSessionReader: ControlledSessionReader(),
            cursorSessionReader: ControlledSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
        await transport.answer(with: .json(#"""
            {
              "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"},
              "rate_limit_reset_credits": {"available_count": 3}
            }
            """#), for: .claude)
        core.panelOpened()
        await core.queriesFinished()

        #expect(core.state.cards.filter { $0.provider != .codex }.map(\.bankedResets) == [nil, nil])
    }

    // MARK: Account-bound lifetime

    @Test func aSuccessfulRefreshWithoutACountClearsThePreviousOne() async {
        await showThreeBankedResets()

        await answer(resetCredits: nil)
        core.refresh()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == nil)
        #expect(showsQuotas())
    }

    @Test func aSuccessfulRefreshReplacesTheCount() async {
        await showThreeBankedResets()

        await answer(resetCredits: #"{"available_count": 1}"#)
        core.refresh()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == 1)
    }

    /// The same account's quotas stay, stale; the count does not, until the
    /// next successful reading.
    @Test(arguments: [
        HTTPResult.networkError, .timeout, .status(403), .status(429), .status(503), .codex(rateLimit: "null"),
    ])
    func aFailedRefreshHidesTheCountWhileTheQuotasGoStale(failure: HTTPResult) async {
        await showThreeBankedResets()

        await transport.answer(with: failure, for: .codex)
        core.refresh()
        await core.queriesFinished()

        guard case .stale = codexCard()?.content else {
            Issue.record("Not stale: \(String(describing: codexCard()?.content))")
            return
        }
        #expect(codexCard()?.bankedResets == nil)

        await answer(resetCredits: #"{"available_count": 2}"#)
        core.refresh()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == 2)
    }

    @Test func anotherAccountNeverShowsThePreviousAccountsCount() async {
        await showThreeBankedResets()

        await codexSessionReader.answer(with: .session(Session(accessToken: "other-token", accountID: "other-account")))
        await answer(resetCredits: nil)
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(codexCard()?.content == .loadingNewAccount)
        #expect(codexCard()?.bankedResets == nil)

        await transport.release()
        await core.queriesFinished()

        #expect(showsQuotas())
        #expect(codexCard()?.bankedResets == nil)
    }

    @Test func anUncertainIdentityNeverShowsThePreviousAccountsCount() async {
        await showThreeBankedResets()

        await codexSessionReader.answer(with: .session(Session(accessToken: "sample-token", accountID: nil)))
        await answer(resetCredits: nil)
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(codexCard()?.content == .loading)
        #expect(codexCard()?.bankedResets == nil)

        await transport.release()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == nil)
    }

    /// With an uncertain identity the count belongs to no verified account,
    /// so only the fresh result of the session's own reading shows it.
    @Test func anUncertainIdentityShowsOnlyTheCountOfItsOwnFreshReading() async {
        await codexSessionReader.answer(with: .session(Session(accessToken: "sample-token", accountID: nil)))
        await showThreeBankedResets()

        await transport.answer(with: .status(503), for: .codex)
        core.refresh()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == nil)
    }

    @Test func leavingAnUncertainIdentityClearsTheCount() async {
        await codexSessionReader.answer(with: .session(Session(accessToken: "sample-token", accountID: nil)))
        await showThreeBankedResets()

        await codexSessionReader.answer(with: .session(Samples.session))
        await answer(resetCredits: nil)
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(codexCard()?.bankedResets == nil)

        await transport.release()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == nil)
    }

    @Test func reenablingCodexShowsNoCountUntilASuccessfulReading() async {
        await showThreeBankedResets()

        core.setEnabled(false, for: .codex)
        #expect(codexCard() == nil)
        await answer(resetCredits: #"{"available_count": 1}"#)
        await transport.hold()
        core.setEnabled(true, for: .codex)
        await transport.waitForRequests(2)

        #expect(codexCard()?.content == .loading)
        #expect(codexCard()?.bankedResets == nil)

        await transport.release()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == 1)
    }

    @Test(arguments: [
        SessionReading.noSession, .withoutSubscriptionQuotas, .accessDenied, .storeUnavailable, .storeBusy, .unknownFormat,
    ])
    func anInvalidSessionClearsTheCount(session: SessionReading) async {
        await showThreeBankedResets()

        await codexSessionReader.answer(with: session)
        core.refresh()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == nil)
    }

    @Test func aRejectedSessionClearsTheCount() async {
        await showThreeBankedResets()

        await transport.answer(with: .status(401), for: .codex)
        core.refresh()
        await core.queriesFinished()

        #expect(codexCard()?.bankedResets == nil)
    }

    /// Reading the count adds nothing to the query: the same single request
    /// to the usage route, without extra headers.
    @Test func theCountComesFromTheUsageQueryAlone() async {
        await showThreeBankedResets()

        let requests = await transport.requests(to: .codex)
        #expect(requests.map { $0.url?.absoluteString } == ["https://chatgpt.com/backend-api/wham/usage"])
        #expect(requests.first?.httpMethod == "GET")
        #expect(Set(requests.first?.allHTTPHeaderFields?.keys ?? [:].keys) == ["Authorization", "ChatGPT-Account-Id"])
    }
}
