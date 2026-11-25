import Foundation
import Testing
import UzzyCore

/// When providers are queried while the panel is closed: never with
/// background refresh off, at its interval with it on, always reusing the
/// session read on a user action.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct BackgroundRefreshTests {
    let clock = ManualClock(Samples.readingMoment)
    let sessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let panelInterval: TimeInterval = 5 * 60
    let backgroundInterval = BackgroundRefresh.defaultInterval

    func makeCore(backgroundRefresh: BackgroundRefresh = BackgroundRefresh(isOn: true)) -> UsageCore {
        UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: sessionReader,
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog(),
            initialBackgroundRefresh: backgroundRefresh
        )
    }

    func requestCount() async -> Int {
        await transport.quotaRequests(to: .codex).count
    }

    /// Opens and closes the panel: a user action that reads the session.
    func openAndClose(_ core: UsageCore) async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()
    }

    func advance(_ core: UsageCore, by interval: TimeInterval) async {
        clock.advance(by: interval)
        await core.queriesFinished()
    }

    @Test func itIsOffByDefault() {
        #expect(BackgroundRefresh.off.isOn == false)
        #expect(BackgroundRefresh.off.interval == 15 * 60)
        let expected: [TimeInterval] = [300, 600, 900, 1800]
        #expect(BackgroundRefresh.intervals == expected)
    }

    @Test func itsIntervalIsNeverUnderFiveMinutes() {
        var refresh = BackgroundRefresh(isOn: true, interval: 60)
        #expect(refresh.interval == 5 * 60)

        refresh.interval = 1
        #expect(refresh.interval == 5 * 60)
    }

    @Test func withItOffClosingThePanelStopsTheQueries() async {
        let core = makeCore(backgroundRefresh: .off)
        await openAndClose(core)

        await advance(core, by: 60 * 60)

        #expect(await requestCount() == 1)
        #expect(clock.scheduledDeadlines == [])
    }

    @Test func withItOnTheClosedPanelQueriesAtItsInterval() async {
        let core = makeCore()
        await openAndClose(core)

        await advance(core, by: backgroundInterval - 1)
        #expect(await requestCount() == 1)

        await advance(core, by: 1)
        #expect(await requestCount() == 2)

        await advance(core, by: backgroundInterval)
        #expect(await requestCount() == 3)
    }

    @Test func theOpenPanelKeepsItsFiveMinuteCadence() async {
        let core = makeCore()
        core.panelOpened()
        await core.queriesFinished()

        await advance(core, by: panelInterval)

        #expect(await requestCount() == 2)
        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(panelInterval)])
    }

    @Test func itNeverReadsTheSessionWhileThePanelIsClosed() async {
        let core = makeCore()
        await openAndClose(core)

        for _ in 0..<3 {
            await advance(core, by: backgroundInterval)
        }

        #expect(await sessionReader.reads == 1)
        #expect(await requestCount() == 4)
    }

    @Test func changingTheIntervalRestartsTheCadenceFromThen() async {
        let core = makeCore()
        await openAndClose(core)
        clock.advance(by: 60)

        core.setBackgroundInterval(5 * 60)

        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(5 * 60)])
    }

    @Test func turningItOffStopsTheQueries() async {
        let core = makeCore()
        await openAndClose(core)

        core.setBackgroundRefresh(false)
        await advance(core, by: 60 * 60)

        #expect(clock.scheduledDeadlines == [])
        #expect(await requestCount() == 1)
    }

    /// Turning it on in Settings is a user action, so a provider with no
    /// session in memory reads it once; the ticks then reuse it.
    @Test func turningItOnReadsAMissingSessionOnce() async {
        let core = makeCore(backgroundRefresh: .off)

        core.setBackgroundRefresh(true)
        await sessionReader.waitForReads(1)
        await core.queriesFinished()
        #expect(await requestCount() == 1)

        await advance(core, by: backgroundInterval)
        #expect(await sessionReader.reads == 1)
        #expect(await requestCount() == 2)
    }

    @Test func turningItOnReusesASessionAlreadyRead() async {
        let core = makeCore(backgroundRefresh: .off)
        await openAndClose(core)

        core.setBackgroundRefresh(true)
        await core.queriesFinished()

        #expect(await sessionReader.reads == 1)
        #expect(await requestCount() == 1)
    }

    @Test func turningItOnNeverAsksAgainAfterAccessWasDenied() async {
        await sessionReader.answer(with: .accessDenied)
        let core = makeCore(backgroundRefresh: .off)
        await openAndClose(core)

        core.setBackgroundRefresh(true)
        await core.queriesFinished()
        await advance(core, by: backgroundInterval)

        #expect(await sessionReader.reads == 1)
        #expect(await requestCount() == 0)
    }

    @Test func turningItOnNeverReadsAKeyThatWaitsForConsent() async {
        await sessionReader.answer(with: .needsAccess)
        let core = makeCore(backgroundRefresh: .off)
        await openAndClose(core)

        core.setBackgroundRefresh(true)
        await core.queriesFinished()

        #expect(await sessionReader.reads == 1)
    }

    @Test func aRejectedReusedSessionStopsTheQueriesUntilTheNextUserAction() async {
        let core = makeCore()
        await openAndClose(core)

        await transport.answer(with: .status(401), for: .codex)
        await advance(core, by: backgroundInterval)
        #expect(await requestCount() == 2)

        await advance(core, by: 4 * backgroundInterval)
        #expect(await requestCount() == 2)
        #expect(await sessionReader.reads == 1)

        await transport.answer(with: .codexSample, for: .codex)
        core.panelOpened()
        await core.queriesFinished()
        #expect(await sessionReader.reads == 2)
        #expect(await requestCount() == 3)
    }

    /// While closed, a failure schedules no 30-second retry: the next tick
    /// queries once the wait allows it.
    @Test func aFailureWhileClosedWaitsForTheNextTick() async {
        let core = makeCore()
        await openAndClose(core)

        await transport.answer(with: .networkError, for: .codex)
        await advance(core, by: backgroundInterval)
        #expect(await requestCount() == 2)
        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(backgroundInterval)])

        await transport.answer(with: .codexSample, for: .codex)
        await advance(core, by: backgroundInterval)
        #expect(await requestCount() == 3)
    }

    @Test func aRetryAfterHoldsTheTicksBackUntilItEnds() async {
        let core = makeCore()
        await openAndClose(core)

        await transport.answer(
            with: .response(HTTPResponse(status: 429, headers: ["Retry-After": "3600"], body: Data())), for: .codex
        )
        await advance(core, by: backgroundInterval)
        #expect(await requestCount() == 2)

        await transport.answer(with: .codexSample, for: .codex)
        await advance(core, by: 3 * backgroundInterval)
        #expect(await requestCount() == 2)

        await advance(core, by: backgroundInterval)
        #expect(await requestCount() == 3)
    }

    @Test func wakingWithThePanelClosedQueriesAndRestartsTheCadence() async {
        let core = makeCore()
        await openAndClose(core)

        clock.advance(by: 60)
        core.systemWoke()
        await core.queriesFinished()

        #expect(await requestCount() == 2)
        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(backgroundInterval)])
    }

    @Test func wakingWithItOffAndThePanelClosedDoesNotQuery() async {
        let core = makeCore(backgroundRefresh: .off)
        await openAndClose(core)

        clock.advance(by: 60 * 60)
        core.systemWoke()
        await core.queriesFinished()

        #expect(await requestCount() == 1)
    }

    @Test func aTurnedOffProviderIsNotQueriedInTheBackground() async {
        let core = makeCore()
        await openAndClose(core)

        core.setEnabled(false, for: .codex)
        await advance(core, by: 2 * backgroundInterval)

        #expect(await requestCount() == 1)
    }
}
