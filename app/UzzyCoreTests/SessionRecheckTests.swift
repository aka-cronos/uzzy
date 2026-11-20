import Foundation
import Testing
import UzzyCore

/// After a provider rejects a session, the card reads it again on its own
/// while the panel is open, and queries once the official app has renewed
/// it. Cursor is the exception: its key is read only on a user action.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SessionRecheckTests {
    let clock = ManualClock(Samples.readingMoment)
    let readers: [Provider: ControlledSessionReader] = [
        .claude: ControlledSessionReader(),
        .codex: ControlledSessionReader(),
        .cursor: ControlledSessionReader(),
        .antigravity: ControlledSessionReader(),
    ]
    let transport = ControlledTransport()
    let core: UsageCore
    static let recheck: TimeInterval = 30

    init() {
        core = UsageCore(
            claudeSessionReader: readers[.claude]!,
            codexSessionReader: readers[.codex]!,
            cursorSessionReader: readers[.cursor]!,
            antigravitySessionReader: readers[.antigravity]!,
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    func content(of provider: Provider) -> CardContent? {
        core.state.cards.first { $0.provider == provider }?.content
    }

    func openPanelWithARejectedSession(of provider: Provider) async {
        await transport.answer(with: .status(401), for: provider)
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test(arguments: [Provider.claude, .codex, .antigravity])
    func aRenewedSessionIsQueriedOnItsOwn(provider: Provider) async {
        await openPanelWithARejectedSession(of: provider)
        #expect(content(of: provider) == .failed(.sessionExpired))

        await readers[provider]!.answer(with: .session(Session(accessToken: "renewed-token", accountID: "sample-account")))
        let sample: HTTPResult = switch provider {
        case .claude: .claudeSample
        case .codex: .codexSample
        case .cursor: .cursorSample
        case .antigravity: .antigravitySample
        }
        await transport.answer(with: sample, for: provider)
        clock.advance(by: Self.recheck)
        await core.queriesFinished()

        guard case .quotas = content(of: provider) else {
            Issue.record("The renewed \(provider) session was not queried")
            return
        }
        #expect(await transport.quotaRequests(to: provider).last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed-token")
    }

    /// Cursor's session is encrypted with a Keychain key that is read only
    /// when the user opens the panel or clicks Refresh.
    @Test func cursorStillWaitsForTheUserAfterARejection() async {
        await openPanelWithARejectedSession(of: .cursor)
        let reads = await readers[.cursor]!.reads

        clock.advance(by: Self.recheck * 3)
        await core.queriesFinished()

        #expect(await readers[.cursor]!.reads == reads)
        #expect(content(of: .cursor) == .failed(.sessionExpired))
    }
}
