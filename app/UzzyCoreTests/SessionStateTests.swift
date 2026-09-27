import Foundation
import Testing
import UzzyCore

/// What the card shows when the provider's session is of no use, and how the
/// panel avoids retrying or prompting for it on its own.
@MainActor
struct SessionStateTests {
    let clock = ManualClock(Samples.readingMoment)
    let sessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let core: UsageCore
    let refreshInterval: TimeInterval = 5 * 60

    init() {
        core = UsageCore(claudeSessionReader: sessionReader, codexSessionReader: NoSessionReader(), cursorSessionReader: NoSessionReader(), transport: transport, clock: clock)
    }

    func claudeContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .claude })?.content
    }

    @Test func withoutASessionTheCardSaysSoAndNothingIsQueried() async {
        await sessionReader.answer(with: .noSession)

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent() == .failed(.noSession))
        #expect(await transport.requests.isEmpty)
    }

    @Test func aSessionTheProviderRejectsIsExpired() async {
        await transport.answer(with: HTTPResult.status(401))

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent() == .failed(.sessionExpired))
    }

    @Test func aForbiddenQueryIsRefusedAccessAndNotAnExpiredSession() async {
        await transport.answer(with: HTTPResult.status(403))

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent() == .failed(.accessRefused))
    }

    @Test func deniedAccessToTheSessionIsShownAndNothingIsQueried() async {
        await sessionReader.answer(with: .accessDenied)

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent() == .failed(.sessionAccessDenied))
        #expect(await transport.requests.isEmpty)
    }

    @Test func aSessionInAnUnknownFormatIsIncompatibleAndNothingIsQueried() async {
        await sessionReader.answer(with: .unknownFormat)

        core.panelOpened()
        await core.queriesFinished()

        // The state carries no credential to show.
        #expect(claudeContent() == .failed(.incompatibleSession))
        #expect(await transport.requests.isEmpty)
    }

    @Test func anUnavailableSessionStoreIsNotCalledAnIncompatibleSession() async {
        await sessionReader.answer(with: .storeUnavailable)

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent() == .failed(.sessionStoreUnavailable))
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [401, 403])
    func afterARejectionTheCadenceAndWakingDoNotRetry(status: Int) async {
        await transport.answer(with: .status(status))
        core.panelOpened()
        await core.queriesFinished()

        await runTheCadenceAndWake()

        #expect(await transport.requests.count == 1)
        #expect(await sessionReader.reads == 1)
    }

    @Test(arguments: [(401, Failure.sessionExpired), (403, .accessRefused)])
    func afterARejectionReopeningWithTheSameSessionDoesNotRetry(status: Int, failure: Failure) async {
        await transport.answer(with: HTTPResult.status(status))
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        clock.advance(by: refreshInterval)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await transport.requests.count == 1)
        #expect(claudeContent() == .failed(failure))
    }

    @Test(arguments: [401, 403])
    func afterARejectionReopeningWithARenewedSessionQueriesAgain(status: Int) async {
        await transport.answer(with: HTTPResult.status(status))
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        await sessionReader.answer(with: .session(Session(accessToken: "renewed-token", accountID: "sample-account")))
        await transport.answer(with: .claudeSample)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await transport.requests.count == 2)
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token")
        #expect(claudeReadAt() == Samples.readingMoment)
    }

    @Test(arguments: [401, 403])
    func afterARejectionActualizarQueriesAgainEvenWithTheSameSession(status: Int) async {
        await transport.answer(with: HTTPResult.status(status))
        core.panelOpened()
        await core.queriesFinished()

        await transport.answer(with: .claudeSample)
        core.refresh()
        await core.queriesFinished()

        #expect(await transport.requests.count == 2)
        #expect(claudeReadAt() == Samples.readingMoment)
    }

    @Test func afterDeniedAccessTheAppDoesNotAskAgainOnItsOwn() async {
        await sessionReader.answer(with: .accessDenied)
        core.panelOpened()
        await core.queriesFinished()

        await runTheCadenceAndWake()
        core.panelClosed()
        clock.advance(by: refreshInterval)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await sessionReader.reads == 1)
        #expect(claudeContent() == .failed(.sessionAccessDenied))
    }

    @Test func afterDeniedAccessActualizarAsksAgain() async {
        await sessionReader.answer(with: .accessDenied)
        core.panelOpened()
        await core.queriesFinished()

        await sessionReader.answer(with: .session(Samples.session))
        core.refresh()
        await core.queriesFinished()

        #expect(await sessionReader.reads == 2)
        #expect(claudeReadAt() == Samples.readingMoment)
    }

    @Test func theCadenceAndWakingReuseTheSessionAndNeverReadItAgain() async {
        core.panelOpened()
        await core.queriesFinished()

        await runTheCadenceAndWake()

        #expect(await transport.requests.count == 5)
        #expect(await sessionReader.reads == 1)
    }

    @Test(arguments: [SessionReading.noSession, .unknownFormat])
    func withoutAUsableSessionTheCadenceAndWakingDoNotReadIt(reading: SessionReading) async {
        await sessionReader.answer(with: reading)
        core.panelOpened()
        await core.queriesFinished()

        await runTheCadenceAndWake()

        #expect(await sessionReader.reads == 1)
        #expect(await transport.requests.isEmpty)
    }

    /// The official app may have renewed the token since it was read, so a
    /// query no user action asked for does not claim the session expired:
    /// it marks the figures stale and leaves the next query to the user.
    @Test(arguments: [401, 403])
    func aRejectionOfAReusedSessionMarksTheCardStaleAndWaitsForTheUser(status: Int) async {
        core.panelOpened()
        await core.queriesFinished()

        await transport.answer(with: .status(status))
        await runTheCadenceAndWake()

        #expect(await transport.requests.count == 2)
        #expect(await sessionReader.reads == 1)
        guard case .stale(let quotas, .reusedSessionRejected) = claudeContent() else {
            Issue.record("Not stale: \(String(describing: claudeContent()))")
            return
        }
        #expect(quotas.count == 2)
        #expect(quotas.allSatisfy { $0.isStale && $0.readAt == Samples.readingMoment })

        await sessionReader.answer(with: .session(Session(accessToken: "renewed-token", accountID: "sample-account")))
        await transport.answer(with: .claudeSample)
        core.panelClosed()
        core.panelOpened()
        await core.queriesFinished()

        #expect(await sessionReader.reads == 2)
        #expect(await transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token")
        #expect(claudeReadAt() == clock.now())
    }

    /// The session read again may be the very one rejected: the official
    /// app's current session was never checked, so reopening queries it.
    @Test(arguments: [401, 403])
    func afterARejectionOfAReusedSessionReopeningChecksTheSameSession(status: Int) async {
        core.panelOpened()
        await core.queriesFinished()
        await transport.answer(with: .status(status))
        clock.advance(by: refreshInterval)
        await core.queriesFinished()
        core.panelClosed()

        await transport.answer(with: .claudeSample)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await sessionReader.reads == 2)
        #expect(await transport.requests.count == 3)
        #expect(claudeReadAt() == clock.now())
    }

    @Test(arguments: [401, 403])
    func afterARejectionOfAReusedSessionActualizarChecksItAgain(status: Int) async {
        core.panelOpened()
        await core.queriesFinished()
        await transport.answer(with: .status(status))
        clock.advance(by: refreshInterval)
        await core.queriesFinished()

        await transport.answer(with: .claudeSample)
        core.refresh()
        await core.queriesFinished()

        #expect(await sessionReader.reads == 2)
        #expect(await transport.requests.count == 3)
        #expect(claudeReadAt() == clock.now())
    }

    /// Figures whose account cannot be verified are never kept as stale.
    @Test func aRejectionOfAReusedSessionOfUncertainIdentityKeepsNoFigures() async {
        await sessionReader.answer(with: .session(Session(accessToken: "sample-token", accountID: nil)))
        core.panelOpened()
        await core.queriesFinished()

        await transport.answer(with: .status(401))
        await runTheCadenceAndWake()

        #expect(await transport.requests.count == 2)
        #expect(claudeContent() == .failed(.reusedSessionRejected))
    }

    /// Three ticks of the 5-minute cadence, then waking from sleep: the
    /// queries no user action asks for.
    func runTheCadenceAndWake() async {
        for _ in 1...3 {
            clock.advance(by: refreshInterval)
            await core.queriesFinished()
        }
        core.systemWoke()
        await core.queriesFinished()
    }

    func claudeReadAt() -> Date? {
        guard case .quotas(let quotas) = claudeContent() else { return nil }
        return quotas.first?.readAt
    }

}
