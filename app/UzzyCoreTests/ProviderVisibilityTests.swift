import Foundation
import Testing
import UzzyCore

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderVisibilityTests {
    let clock = ManualClock(Samples.readingMoment)
    let claudeReader = ControlledSessionReader()
    let codexReader = ControlledSessionReader()
    let cursorReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore

    init() {
        core = UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            transport: transport,
            clock: clock
        )
    }

    @Test func defaultShowsAndQueriesAllProvidersInOrder() async {
        #expect(core.enabledProviders == Set(Provider.allCases))
        #expect(core.state.cards.map(\.provider) == Provider.allCases)

        core.panelOpened()
        await core.queriesFinished()

        #expect(await claudeReader.reads == 1)
        #expect(await codexReader.reads == 1)
        #expect(await cursorReader.reads == 1)
        #expect(await transport.requests.count == 3)
    }

    @Test func restoredChoicesHideAndNeverReadDisabledProviders() async {
        let restored = UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            transport: transport,
            clock: clock,
            initialEnabledProviders: [.claude, .cursor]
        )

        #expect(restored.state.cards.map(\.provider) == [.claude, .cursor])
        restored.panelOpened()
        await restored.queriesFinished()

        #expect(await codexReader.reads == 0)
        #expect(await transport.requests(to: .codex).isEmpty)
        #expect(await transport.requests(to: .claude).count == 1)
        #expect(await transport.requests(to: .cursor).count == 1)
    }

    @Test func allDisabledHasNoCardsOrSessionAndNetworkWork() async {
        let disabled = UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            transport: transport,
            clock: clock,
            initialEnabledProviders: []
        )

        disabled.panelOpened()
        disabled.refresh()
        disabled.systemWoke()
        clock.advance(by: 10 * 60)
        await disabled.queriesFinished()
        disabled.panelClosed()
        disabled.panelOpened()
        await disabled.queriesFinished()

        #expect(disabled.state.cards.isEmpty)
        #expect(!disabled.state.isQuerying)
        #expect(await claudeReader.reads == 0)
        #expect(await codexReader.reads == 0)
        #expect(await cursorReader.reads == 0)
        #expect(await transport.requests.isEmpty)
    }

    @Test func disablingOneProviderSuppressesEveryTriggerAndLeavesOthersWorking() async {
        core.panelOpened()
        await core.queriesFinished()
        core.setEnabled(false, for: .codex)

        #expect(core.state.cards.map(\.provider) == [.claude, .cursor])
        core.refresh()
        core.systemWoke()
        clock.advance(by: 5 * 60)
        await core.queriesFinished()
        core.panelClosed()
        core.panelOpened()
        await core.queriesFinished()

        #expect(await codexReader.reads == 1)
        #expect(await transport.requests(to: .codex).count == 1)
        #expect(await transport.requests(to: .claude).count > 1)
        #expect(await transport.requests(to: .cursor).count > 1)
        #expect(core.state.cards.map(\.provider) == [.claude, .cursor])
    }

    @Test func enablingWhileOpenStartsFreshAndNeverRestoresTheOldReading() async {
        core.panelOpened()
        await core.queriesFinished()
        core.setEnabled(false, for: .claude)
        core.setEnabled(true, for: .claude)

        #expect(core.state.cards.map(\.provider) == Provider.allCases)
        #expect(core.state.cards[0].content == .loading)
        await core.queriesFinished(of: .claude)

        #expect(await claudeReader.reads == 2)
        #expect(await transport.requests(to: .claude).count == 2)
        guard case .quotas = core.state.cards[0].content else {
            Issue.record("Re-enabled provider did not get a fresh reading")
            return
        }
    }

    @Test func enablingWhileClosedWaitsForTheNextPanelOpening() async {
        core.setEnabled(false, for: .codex)
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()
        core.setEnabled(true, for: .codex)

        #expect(core.state.cards[1].content == .loading)
        #expect(await codexReader.reads == 0)
        #expect(await transport.requests(to: .codex).isEmpty)

        core.panelOpened()
        await core.queriesFinished(of: .codex)

        #expect(await codexReader.reads == 1)
        #expect(await transport.requests(to: .codex).count == 1)
    }

    @Test func disablingDuringSessionReadCannotStartANetworkRequest() async {
        await claudeReader.hold()
        core.panelOpened()
        await claudeReader.waitForReads(1)

        core.setEnabled(false, for: .claude)
        await claudeReader.release()
        await core.queriesFinished(of: .claude)

        #expect(!core.enabledProviders.contains(.claude))
        #expect(await transport.requests(to: .claude).isEmpty)

        core.setEnabled(true, for: .claude)
        await core.queriesFinished(of: .claude)
        #expect(await claudeReader.reads == 2)
        #expect(await transport.requests(to: .claude).count == 1)
    }

    @Test func disablingDuringNetworkRequestIgnoresItsLateResult() async {
        await transport.hold(.claude)
        core.panelOpened()
        await transport.waitForRequests(3)
        await core.queriesFinished(of: .codex)
        await core.queriesFinished(of: .cursor)

        core.setEnabled(false, for: .claude)
        #expect(core.state.cards.map(\.provider) == [.codex, .cursor])
        #expect(!core.state.isQuerying)

        await transport.release()
        await core.queriesFinished()
        #expect(core.state.cards.map(\.provider) == [.codex, .cursor])

        core.setEnabled(true, for: .claude)
        #expect(core.state.cards[0].content == .loading)
        await core.queriesFinished(of: .claude)
        #expect(await claudeReader.reads == 2)
        #expect(await transport.requests(to: .claude).count == 2)
    }

    @Test func disablingInvalidatesAScheduledRetry() async {
        await transport.answer(with: .networkError, for: .claude)
        core.panelOpened()
        await core.queriesFinished()
        core.setEnabled(false, for: .claude)

        clock.advance(by: 30)
        await core.queriesFinished()

        #expect(await claudeReader.reads == 1)
        #expect(await transport.requests(to: .claude).count == 1)
    }

    @Test func disablingRetiresTheScheduledRetry() async {
        await transport.answer(with: .networkError, for: .claude)
        core.panelOpened()
        await core.queriesFinished()

        core.setEnabled(false, for: .claude)

        #expect(clock.scheduledDeadlines == [Samples.readingMoment.addingTimeInterval(5 * 60)])
    }

    @Test func reEnablingDoesNotBypassRetryAfter() async {
        let until = Samples.readingMoment.addingTimeInterval(600)
        await transport.answer(
            with: .response(HTTPResponse(status: 429, headers: ["Retry-After": "600"], body: Data())),
            for: .claude
        )
        core.panelOpened()
        await core.queriesFinished()
        core.setEnabled(false, for: .claude)

        clock.advance(by: 60)
        core.setEnabled(true, for: .claude)
        await core.queriesFinished(of: .claude)
        core.refresh()
        await core.queriesFinished(of: .claude)

        #expect(core.state.cards[0].content == .failed(.rateLimited(until: until)))
        #expect(await transport.requests(to: .claude).count == 1)
        await transport.answer(with: .claudeSample, for: .claude)

        clock.advance(by: 540)
        await core.queriesFinished(of: .claude)

        #expect(await transport.requests(to: .claude).count == 2)
        guard case .quotas = core.state.cards[0].content else {
            Issue.record("Provider did not query after Retry-After ended")
            return
        }
    }
}
