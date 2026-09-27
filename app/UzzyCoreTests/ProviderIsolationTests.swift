import Foundation
import Testing
import UzzyCore

/// Each provider is queried on its own: a failure, a wait or a slow answer
/// of one never affects the card of another.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderIsolationTests {
    let clock = ManualClock(Samples.readingMoment)
    let claudeSessionReader = ControlledSessionReader()
    let codexSessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let log = RecordingLog()
    let core: UsageCore
    let refreshInterval: TimeInterval = 5 * 60

    init() {
        core = UsageCore(
            claudeSessionReader: claudeSessionReader,
            codexSessionReader: codexSessionReader,
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: log
        )
    }

    func content(of provider: Provider) -> CardContent? {
        core.state.cards.first(where: { $0.provider == provider })?.content
    }

    func showsQuotas(_ provider: Provider) -> Bool {
        if case .quotas = content(of: provider) { true } else { false }
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test(arguments: [(Provider.claude, Provider.codex), (.codex, .claude)])
    func aProviderThatFailsLeavesTheOtherCardShowingItsQuotas(failing: Provider, other: Provider) async {
        await transport.answer(with: .status(500), for: failing)

        await openPanel()

        #expect(content(of: failing) == .failed(.serverError(status: 500)))
        #expect(showsQuotas(other))
        #expect(log.events == [.queryFailed(failing, .serverError(status: 500))])
    }

    @Test func aResponseOverTheByteBudgetFailsOnlyItsOwnProvider() async {
        await transport.answer(with: .responseTooLarge, for: .claude)

        await openPanel()

        #expect(content(of: .claude) == .failed(.responseTooLarge))
        #expect(showsQuotas(.codex))
    }

    @Test func aProviderWithoutASessionLeavesTheOtherCardShowingItsQuotas() async {
        await codexSessionReader.answer(with: .unknownFormat)

        await openPanel()

        #expect(content(of: .codex) == .failed(.incompatibleSession))
        #expect(showsQuotas(.claude))
    }

    @Test func eachCardShowsItsQuotasAsSoonAsTheyArrive() async {
        await transport.hold(.claude)

        core.panelOpened()
        await transport.waitForRequests(2)
        await core.queriesFinished(of: .codex)

        #expect(showsQuotas(.codex))
        #expect(content(of: .claude) == .loading)
        #expect(core.state.isQuerying)
        await transport.release()
        await core.queriesFinished()
        #expect(showsQuotas(.claude))
    }

    @Test func aRejectedSessionStopsOnlyItsOwnProvidersAutomaticQueries() async {
        await transport.answer(with: .status(401), for: .codex)
        await openPanel()

        clock.advance(by: refreshInterval)
        await core.queriesFinished()

        #expect(await transport.requests(to: .claude).count == 2)
        #expect(await transport.requests(to: .codex).count == 1)
        #expect(content(of: .codex) == .failed(.sessionExpired))
    }

    @Test func aRejectedReusedSessionMarksOnlyItsOwnCardStale() async {
        await openPanel()
        await transport.answer(with: .status(401), for: .codex)

        clock.advance(by: refreshInterval)
        await core.queriesFinished()
        clock.advance(by: refreshInterval)
        await core.queriesFinished()

        guard case .stale(_, .reusedSessionRejected) = content(of: .codex) else {
            Issue.record("Not stale: \(String(describing: content(of: .codex)))")
            return
        }
        #expect(showsQuotas(.claude))
        #expect(await transport.requests(to: .claude).count == 3)
        #expect(await transport.requests(to: .codex).count == 2)
    }

    @Test func aProviderAskingToWaitDoesNotHoldBackTheOther() async {
        await openPanel()
        await transport.answer(
            with: .response(HTTPResponse(status: 429, headers: ["Retry-After": "3600"], body: Data())),
            for: .claude
        )
        core.refresh()
        await core.queriesFinished()

        clock.advance(by: 60)
        core.refresh()
        await core.queriesFinished()

        #expect(await transport.requests(to: .claude).count == 2)
        #expect(await transport.requests(to: .codex).count == 3)
    }

    @Test func aZeroRetryAfterWaitsOnlyForItsOwnProvider() async {
        await transport.answer(
            with: .response(HTTPResponse(status: 429, headers: ["Retry-After": "0"], body: Data())),
            for: .claude
        )
        await openPanel()
        for _ in 0..<10 {
            clock.advance(by: 0)
            await core.queriesFinished()
        }
        #expect(await transport.requests(to: .claude).count == 1)

        clock.advance(by: 30)
        await core.queriesFinished()

        #expect(await transport.requests(to: .claude).count == 2)
        #expect(await transport.requests(to: .codex).count == 1)
        #expect(showsQuotas(.codex))
    }

    @Test func aFailingProviderRetriesOnItsOwnWithoutQueryingTheOther() async {
        await transport.answer(with: .networkError, for: .codex)
        await openPanel()

        clock.advance(by: 30)
        await core.queriesFinished()

        #expect(await transport.requests(to: .codex).count == 2)
        #expect(await transport.requests(to: .claude).count == 1)
    }
}
