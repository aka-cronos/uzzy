import Foundation
import Testing
import UzzyCore

/// Keeps the alerts a core fires.
@MainActor
final class AlertRecorder {
    private(set) var alerts: [UsageAlert] = []

    func record(_ alert: UsageAlert) {
        alerts.append(alert)
    }
}

/// Which alerts background refresh fires, and when: once per reset window,
/// only with the panel closed, after a baseline, and a reset only once a
/// fresh reading of the same account confirms it.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UsageAlertTests {
    let clock = ManualClock(Samples.readingMoment)
    let sessionReader = ControlledSessionReader()
    let transport = ControlledTransport()
    let recorder = AlertRecorder()
    let core: UsageCore
    let interval = BackgroundRefresh.defaultInterval
    /// A reset far enough ahead that no test reaches it.
    let farReset = Samples.readingMoment.addingTimeInterval(4 * 3_600)
    /// A 5-hour window's reset 20 minutes after the first reading, between
    /// the first two background ticks.
    let resetAt = Samples.readingMoment.addingTimeInterval(20 * 60)
    let nextResetAt = Samples.readingMoment.addingTimeInterval(20 * 60 + 5 * 3_600)
    let otherAccount = Session(accessToken: "other-token", accountID: "other-account")

    init() {
        core = UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: sessionReader,
            cursorSessionReader: NoSessionReader(),
            antigravitySessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog(),
            initialBackgroundRefresh: BackgroundRefresh(isOn: true),
            initialAlerts: AlertSettings(nearLimit: true, limitReached: true, limitReset: true)
        )
        core.alertFired = { [recorder] in recorder.record($0) }
    }

    /// Codex answers with a 5-hour window at `used`, resetting at `reset`,
    /// or `farReset` by default.
    func answer(used: Double, reset: Date? = nil, limitName: String? = nil) async {
        let resetAt = (reset ?? farReset).timeIntervalSince1970
        let window = #"{"primary_window": {"used_percent": \#(used), "limit_window_seconds": 18000, "reset_at": \#(resetAt)}}"#
        if let limitName {
            await transport.answer(with: .codex(
                rateLimit: #"{"primary_window": {"used_percent": 1, "limit_window_seconds": 604800, "reset_at": \#(nextResetAt.timeIntervalSince1970)}}"#,
                additional: #"[{"limit_name": "\#(limitName)", "rate_limit": \#(window)}]"#
            ), for: .codex)
        } else {
            await transport.answer(with: .codex(rateLimit: window), for: .codex)
        }
    }

    /// The first reading, on opening the panel, then the panel closes.
    func start(used: Double, reset: Date? = nil) async {
        await answer(used: used, reset: reset)
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()
    }

    /// The next background tick, with Codex answering `used`.
    func tick(used: Double, reset: Date? = nil) async {
        await answer(used: used, reset: reset)
        clock.advance(by: interval)
        await core.queriesFinished()
    }

    func requestCount() async -> Int {
        await transport.quotaRequests(to: .codex).count
    }

    @Test func theFirstReadingOnlySetsTheBaseline() async {
        await start(used: 90)
        await tick(used: 92)

        #expect(recorder.alerts == [])
    }

    @Test func theFirstReadingAtTheLimitFiresNothing() async {
        await start(used: 100)
        await tick(used: 100)

        #expect(recorder.alerts == [])
    }

    @Test func crossingTheThresholdFiresOnceWithTheReadingsPercentage() async {
        await start(used: 50)

        await tick(used: 85)
        await tick(used: 88)

        #expect(recorder.alerts == [.nearLimit(.codex, period: .fiveHours, usedPercent: 85, reset: farReset)])
    }

    @Test func theNearLimitAlertCarriesTheResetAhead() async {
        let reset = Samples.readingMoment.addingTimeInterval(2 * 3_600)
        await start(used: 50, reset: reset)

        await tick(used: 85, reset: reset)

        #expect(recorder.alerts == [.nearLimit(.codex, period: .fiveHours, usedPercent: 85, reset: reset)])
    }

    @Test func jumpingStraightToTheLimitFiresOnlyLimitReached() async {
        let reset = Samples.readingMoment.addingTimeInterval(2 * 3_600)
        await start(used: 50, reset: reset)

        await tick(used: 100, reset: reset)

        #expect(recorder.alerts == [.limitReached(.codex, period: .fiveHours, reset: reset)])
    }

    @Test func reachingTheLimitAfterTheThresholdFiresEachOnce() async {
        let reset = Samples.readingMoment.addingTimeInterval(2 * 3_600)
        await start(used: 50, reset: reset)

        await tick(used: 85, reset: reset)
        await tick(used: 100, reset: reset)
        await tick(used: 100, reset: reset)

        #expect(recorder.alerts == [
            .nearLimit(.codex, period: .fiveHours, usedPercent: 85, reset: reset),
            .limitReached(.codex, period: .fiveHours, reset: reset),
        ])
    }

    @Test func droppingBelowTheThresholdFiresAgainOnTheNextCrossing() async {
        let reset = Samples.readingMoment.addingTimeInterval(2 * 3_600)
        await start(used: 50, reset: reset)

        await tick(used: 85, reset: reset)
        await tick(used: 40, reset: reset)
        await tick(used: 86, reset: reset)

        #expect(recorder.alerts == [
            .nearLimit(.codex, period: .fiveHours, usedPercent: 85, reset: reset),
            .nearLimit(.codex, period: .fiveHours, usedPercent: 86, reset: reset),
        ])
    }

    @Test func aNewWindowFiresAgain() async {
        let reset = Samples.readingMoment.addingTimeInterval(2 * 3_600)
        let next = reset.addingTimeInterval(5 * 3_600)
        await start(used: 50, reset: reset)

        await tick(used: 85, reset: reset)
        await tick(used: 90, reset: next)

        #expect(recorder.alerts == [
            .nearLimit(.codex, period: .fiveHours, usedPercent: 85, reset: reset),
            .nearLimit(.codex, period: .fiveHours, usedPercent: 90, reset: next),
        ])
    }

    @Test func nothingFiresWhileThePanelIsOpen() async {
        await start(used: 50)

        await answer(used: 85)
        core.panelOpened()
        await core.queriesFinished()
        core.refresh()
        await core.queriesFinished()
        core.panelClosed()
        #expect(recorder.alerts == [])

        // The crossing was seen in the panel, so it never fires later.
        await tick(used: 87)
        #expect(recorder.alerts == [])
    }

    @Test func anAlertTurnedOffFiresNothing() async {
        core.setAlerts(AlertSettings(nearLimit: false, limitReached: true, limitReset: false))
        await start(used: 50)

        await tick(used: 85)
        #expect(recorder.alerts == [])

        await tick(used: 100)
        #expect(recorder.alerts == [.limitReached(.codex, period: .fiveHours, reset: farReset)])
    }

    @Test func nothingFiresWithBackgroundRefreshOff() async {
        core.setBackgroundRefresh(false)
        await start(used: 50)

        await answer(used: 100)
        core.refresh()
        await core.queriesFinished()

        #expect(recorder.alerts == [])
    }

    /// The first reading after turning it on only sets the baseline, even
    /// when the quota moved while it was off.
    @Test func turningBackgroundRefreshOnStartsFromABaseline() async {
        core.setBackgroundRefresh(false)
        await start(used: 50)

        core.setBackgroundRefresh(true)
        await tick(used: 90)

        #expect(recorder.alerts == [])
    }

    @Test func aHigherThresholdRestartsTheNearLimitAlert() async {
        await start(used: 50)
        core.setAlerts(AlertSettings(nearLimit: true, threshold: 90, limitReached: true, limitReset: true))

        await tick(used: 85)
        #expect(recorder.alerts == [])

        await tick(used: 91)
        #expect(recorder.alerts == [.nearLimit(.codex, period: .fiveHours, usedPercent: 91, reset: farReset)])
    }

    /// A lower threshold the quota is already over fires nothing at once.
    @Test func aLowerThresholdAlreadyCrossedFiresNothing() async {
        core.setAlerts(AlertSettings(nearLimit: true, threshold: 90, limitReached: true, limitReset: true))
        await start(used: 50)
        await tick(used: 85)

        core.setAlerts(AlertSettings(nearLimit: true, threshold: 80, limitReached: true, limitReset: true))
        await tick(used: 86)

        #expect(recorder.alerts == [])
    }

    @Test func anotherAccountSetsANewBaseline() async {
        await start(used: 50)

        await sessionReader.answer(with: .session(otherAccount))
        await answer(used: 95)
        core.refresh()
        await core.queriesFinished()

        #expect(recorder.alerts == [])
    }

    @Test func aProviderTurnedOffAndOnStartsFromABaseline() async {
        await start(used: 50)

        core.setEnabled(false, for: .codex)
        core.setEnabled(true, for: .codex)
        await answer(used: 95)
        core.refresh()
        await core.queriesFinished()

        #expect(recorder.alerts == [])
    }

    @Test func aNamedLimitFollowsTheSameRules() async {
        await answer(used: 50, limitName: "GPT-5.3-Codex-Spark")
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        await answer(used: 85, limitName: "GPT-5.3-Codex-Spark")
        clock.advance(by: interval)
        await core.queriesFinished()

        #expect(recorder.alerts == [
            .nearLimit(.codex, period: .limit("GPT-5.3-Codex-Spark", .fiveHours), usedPercent: 85, reset: farReset),
        ])
    }

    // MARK: - Resets

    /// Reaches the limit on the first tick, 15 minutes in, with the reset at
    /// 20 minutes.
    func reachTheLimit() async {
        await start(used: 50, reset: resetAt)
        await tick(used: 100, reset: resetAt)
        #expect(recorder.alerts == [.limitReached(.codex, period: .fiveHours, reset: resetAt)])
    }

    @Test func aLimitedQuotaSchedulesOneQueryRightAfterItsReset() async {
        await reachTheLimit()

        #expect(clock.scheduledDeadlines.contains(resetAt.addingTimeInterval(UsageCore.resetVerificationDelay)))
    }

    @Test func aConfirmedResetFiresOnce() async {
        await reachTheLimit()
        let requests = await requestCount()

        await answer(used: 3, reset: nextResetAt)
        clock.move(to: resetAt.addingTimeInterval(UsageCore.resetVerificationDelay))
        await core.queriesFinished()

        #expect(await requestCount() == requests + 1)
        #expect(recorder.alerts.last == .limitReset(.codex, period: .fiveHours))

        await tick(used: 4, reset: nextResetAt)
        #expect(recorder.alerts.filter { if case .limitReset = $0 { true } else { false } }.count == 1)
    }

    /// The provider still reports the passed reset: the reading does not
    /// confirm it, so nothing fires until one does.
    @Test func anUnconfirmedResetFiresNothing() async {
        await reachTheLimit()

        await answer(used: 100, reset: resetAt)
        clock.move(to: resetAt.addingTimeInterval(UsageCore.resetVerificationDelay))
        await core.queriesFinished()
        #expect(recorder.alerts.count == 1)

        await tick(used: 2, reset: nextResetAt)
        #expect(recorder.alerts.last == .limitReset(.codex, period: .fiveHours))
    }

    @Test func aFailedVerificationFiresNothing() async {
        await reachTheLimit()

        await transport.answer(with: .networkError, for: .codex)
        clock.move(to: resetAt.addingTimeInterval(UsageCore.resetVerificationDelay))
        await core.queriesFinished()

        #expect(recorder.alerts.count == 1)
    }

    @Test func aResetOfAnotherAccountFiresNothing() async {
        await reachTheLimit()

        await sessionReader.answer(with: .session(otherAccount))
        await answer(used: 3, reset: nextResetAt)
        core.refresh()
        await core.queriesFinished()

        #expect(recorder.alerts.count == 1)
    }

    @Test func withResetAlertsOffNoVerificationIsScheduled() async {
        core.setAlerts(AlertSettings(nearLimit: true, limitReached: true, limitReset: false))
        await reachTheLimit()

        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(interval)])
    }

    @Test func turningBackgroundRefreshOffCancelsTheVerification() async {
        await reachTheLimit()

        core.setBackgroundRefresh(false)

        #expect(clock.scheduledDeadlines == [])
    }

    @Test func aTurnedOffProviderCancelsItsVerification() async {
        await reachTheLimit()

        core.setEnabled(false, for: .codex)

        #expect(clock.scheduledDeadlines == [clock.now().addingTimeInterval(interval)])
    }

    @Test func wakingReschedulesTheVerification() async {
        await reachTheLimit()

        clock.advance(by: 60)
        await answer(used: 100, reset: resetAt)
        core.systemWoke()
        await core.queriesFinished()

        #expect(clock.scheduledDeadlines == [
            resetAt.addingTimeInterval(UsageCore.resetVerificationDelay),
            clock.now().addingTimeInterval(interval),
        ])
    }
}
