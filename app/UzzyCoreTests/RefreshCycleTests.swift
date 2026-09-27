import Foundation
import Testing
import UzzyCore

/// When the panel queries each provider: on opening, every 5 minutes while
/// open, on waking from sleep and on a manual refresh.
@MainActor
struct RefreshCycleTests {
    let clock = ManualClock(Samples.readingMoment)
    let transport = ControlledTransport()
    let core: UsageCore
    let refreshInterval: TimeInterval = 5 * 60

    init() {
        core = UsageCore(claudeSessionReader: SampleSessionReader(), codexSessionReader: NoSessionReader(), cursorSessionReader: NoSessionReader(), transport: transport, clock: clock)
    }

    func requestCount() async -> Int {
        await transport.requests.count
    }

    @Test func openingWithAReadingUnderFiveMinutesOldDoesNotQueryAgain() async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        clock.advance(by: refreshInterval - 1)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await requestCount() == 1)
    }

    @Test func openingWithAReadingOfFiveMinutesOrMoreQueriesAgain() async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        clock.advance(by: refreshInterval)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await requestCount() == 2)
    }

    @Test func openingAfterAFailedQueryQueriesAgain() async {
        await transport.answer(with: .networkError)
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        clock.advance(by: 1)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await requestCount() == 2)
    }

    @Test func whileOpenItQueriesEveryFiveMinutes() async {
        core.panelOpened()
        await core.queriesFinished()

        clock.advance(by: refreshInterval - 1)
        await core.queriesFinished()
        #expect(await requestCount() == 1)

        clock.advance(by: 1)
        await core.queriesFinished()
        #expect(await requestCount() == 2)

        clock.advance(by: refreshInterval)
        await core.queriesFinished()
        #expect(await requestCount() == 3)
    }

    @Test func closingThePanelStopsTheQueries() async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        clock.advance(by: 60 * 60)
        await core.queriesFinished()

        #expect(await requestCount() == 1)
    }

    @Test func reopeningKeepsASingleFiveMinuteCadence() async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()
        clock.advance(by: 60)
        core.panelOpened()

        clock.advance(by: refreshInterval - 1)
        await core.queriesFinished()
        #expect(await requestCount() == 1)

        clock.advance(by: 1)
        await core.queriesFinished()
        #expect(await requestCount() == 2)
    }

    @Test func closingThePanelRetiresItsScheduledWork() async {
        await transport.answer(with: .networkError)
        core.panelOpened()
        await core.queriesFinished()

        core.panelClosed()

        #expect(clock.scheduledDeadlines == [])
    }

    @Test func reopeningAndWakingReplaceTheScheduledQuery() async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()
        clock.advance(by: 60)
        core.panelOpened()
        clock.advance(by: 60)
        core.systemWoke()
        await core.queriesFinished()

        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(refreshInterval)])
    }

    @Test func aQueryInFlightWhenThePanelClosesStillFinishes() async {
        await transport.hold()
        core.panelOpened()
        await transport.waitForRequests(1)

        core.panelClosed()
        await transport.release()
        await core.queriesFinished()

        #expect(claudeReadAt() == Samples.readingMoment)
    }

    @Test func wakingFromSleepWithThePanelOpenQueriesAndRestartsTheCadence() async {
        core.panelOpened()
        await core.queriesFinished()

        clock.advance(by: 60)
        core.systemWoke()
        await core.queriesFinished()
        #expect(await requestCount() == 2)

        clock.advance(by: refreshInterval - 1)
        await core.queriesFinished()
        #expect(await requestCount() == 2)

        clock.advance(by: 1)
        await core.queriesFinished()
        #expect(await requestCount() == 3)
    }

    @Test func wakingFromSleepWithThePanelClosedDoesNotQuery() async {
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        clock.advance(by: 60 * 60)
        core.systemWoke()
        await core.queriesFinished()

        #expect(await requestCount() == 1)
    }

    @Test func manualRefreshQueriesEvenWithAFreshReading() async {
        core.panelOpened()
        await core.queriesFinished()

        clock.advance(by: 1)
        core.refresh()
        await core.queriesFinished()

        #expect(await requestCount() == 2)
        #expect(claudeReadAt() == Samples.readingMoment.addingTimeInterval(1))
    }

    @Test func manualRefreshShowsAQueryInFlightUntilItsResultArrives() async {
        core.panelOpened()
        await core.queriesFinished()
        #expect(!core.state.isQuerying)

        await transport.hold()
        core.refresh()
        #expect(core.state.isQuerying)

        await transport.release()
        await core.queriesFinished()
        #expect(!core.state.isQuerying)
    }

    @Test func repeatedRequestsJoinTheQueryInFlight() async {
        await transport.hold()
        core.panelOpened()
        await transport.waitForRequests(1)

        core.refresh()
        core.systemWoke()
        clock.advance(by: refreshInterval)
        await transport.release()
        await core.queriesFinished()

        #expect(await requestCount() == 1)
    }

    @Test func eachQueryWhileOpenShowsItsNewReading() async {
        core.panelOpened()
        await core.queriesFinished()

        clock.advance(by: refreshInterval)
        await core.queriesFinished()

        #expect(claudeReadAt() == Samples.readingMoment.addingTimeInterval(refreshInterval))
    }

    func claudeReadAt() -> Date? {
        guard case .quotas(let quotas) = core.state.cards.first(where: { $0.provider == .claude })?.content else {
            return nil
        }
        return quotas.first?.readAt
    }
}
