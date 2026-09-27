import Foundation
import Testing
import UzzyCore

/// The reset text of a quota, through the usage core and the app's formatter,
/// which this target compiles from `Uzzy/Format.swift`.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ResetTextTests {
    let now = Samples.readingMoment

    func codexReset(resetAt: String) async -> Reset? {
        let transport = ControlledTransport()
        await transport.answer(with: .codex(rateLimit: """
            {"primary_window": {"used_percent": 10, "limit_window_seconds": 18000, "reset_at": \(resetAt)}}
            """), for: .codex)
        let core = UsageCore(
            claudeSessionReader: ControlledSessionReader(),
            codexSessionReader: ControlledSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: ManualClock(now),
            log: RecordingLog()
        )
        core.panelOpened()
        await core.queriesFinished()
        guard case .quotas(let quotas) = core.state.cards.first(where: { $0.provider == .codex })?.content else {
            return nil
        }
        return quotas.first?.reset
    }

    @Test(arguments: ["1e30", "-1e30", "1.7976931348623157e308", "-1.7976931348623157e308"])
    func anExtremeResetFromTheProviderReadsAsUnknown(resetAt: String) async throws {
        let reset = try #require(await codexReset(resetAt: resetAt))

        #expect(Format.reset(reset, now: now) == "Reinicio desconocido")
    }

    @Test func aMissingResetFromTheProviderReadsAsUnknown() async throws {
        let reset = try #require(await codexReset(resetAt: "null"))

        #expect(Format.reset(reset, now: now) == "Reinicio desconocido")
    }

    @Test func anOrdinaryResetReadsAsItsCountdown() async throws {
        let resetAt = now.addingTimeInterval(2 * 3_600 + 5 * 60).timeIntervalSince1970
        let reset = try #require(await codexReset(resetAt: "\(resetAt)"))

        #expect(Format.reset(reset, now: now).hasSuffix(" · en 2 h 5 min"))
    }

    @Test func aPassedResetReadsAsPendingConfirmation() async throws {
        let resetAt = now.addingTimeInterval(-60).timeIntervalSince1970
        let reset = try #require(await codexReset(resetAt: "\(resetAt)"))

        #expect(Format.reset(reset, now: now) == "Reinicio pendiente de confirmar")
    }

    /// Invalid data that reaches the formatter must not stop the app.
    @Test(arguments: [1e30, 1.7976931348623157e308, .infinity])
    func anExtremeIntervalAheadDoesNotStopTheFormatter(seconds: Double) {
        let text = Format.reset(.at(Date(timeIntervalSince1970: seconds)), now: now)

        #expect(text.hasPrefix("Reinicio: "))
    }

    /// E.g. the panel is redrawn after the reset passed, before the next reading.
    @Test(arguments: [-60.0, -1e30, -1.7976931348623157e308, -.infinity, .nan])
    func anIntervalThatIsNotAheadCountsDownToZero(seconds: Double) {
        let text = Format.reset(.at(now.addingTimeInterval(seconds)), now: now)

        #expect(text.hasSuffix(" · en 0 min"))
    }
}
