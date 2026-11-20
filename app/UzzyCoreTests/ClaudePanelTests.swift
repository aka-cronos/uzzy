import Foundation
import Testing
import UzzyCore

@MainActor
struct ClaudePanelTests {
    let readingMoment = Samples.readingMoment

    func core(transport: SampleTransport) -> UsageCore {
        UsageCore(
            claudeSessionReader: SampleSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            antigravitySessionReader: NoSessionReader(),
            transport: transport,
            clock: FixedClock(readingMoment)
        )
    }

    func claudeContent(_ core: UsageCore) -> CardContent? {
        core.state.cards.first(where: { $0.provider == .claude })?.content
    }

    @Test func beforeTheFirstReadingTheClaudeCardIsLoading() {
        let core = core(transport: SampleTransport())

        #expect(core.state.magnitude == .used)
        #expect(claudeContent(core) == .loading)
    }

    @Test func openingThePanelShowsEachClaudeQuotaSeparately() async {
        let core = core(transport: SampleTransport())

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent(core) == .quotas([
            Quota(
                period: .fiveHours,
                value: .percent(35, calculated: false),
                // 2026-09-23T17:00:00Z
                reset: .at(Date(timeIntervalSince1970: 1_790_182_800)),
                readAt: readingMoment
            ),
            Quota(
                period: .weekly,
                value: .percent(62, calculated: false),
                // 2026-09-25T09:00:00Z
                reset: .at(Date(timeIntervalSince1970: 1_790_326_800)),
                readAt: readingMoment
            ),
        ]))
    }

    /// An untouched window has not started, so the date Claude reports for it
    /// is the reading moment plus the window's length, not a reset. The
    /// query's latency puts it a few seconds off.
    @Test func anUntouchedWindowHasNoReset() async {
        // The reading moment, 2026-09-23T14:32:00Z, plus 5 hours and 7 days.
        let core = core(transport: SampleTransport(claudeResponse: Data(#"""
            {
              "five_hour": {"utilization": 0.0, "resets_at": "2026-09-23T19:32:00.412000+00:00"},
              "seven_day": {"utilization": 0.0, "resets_at": "2026-09-30T14:32:30.000000+00:00"}
            }
            """#.utf8)))

        core.panelOpened()
        await core.queriesFinished()

        #expect(claudeContent(core) == .quotas([
            Quota(period: .fiveHours, value: .percent(0, calculated: false), reset: nil, readAt: readingMoment),
            Quota(period: .weekly, value: .percent(0, calculated: false), reset: nil, readAt: readingMoment),
        ]))
    }

    @Test func queriesClaudeUsageAndResetsWithTheExistingSession() async {
        let transport = SampleTransport()
        let core = core(transport: transport)

        core.panelOpened()
        await core.queriesFinished()

        let requests = await transport.quotaRequests
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "GET")
        #expect(requests.first?.url == URL(string: "https://api.anthropic.com/api/oauth/usage?cedar_ember=1"))
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
        #expect(requests.first?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(requests.first?.value(forHTTPHeaderField: "User-Agent") == "claude-cli/2.1.322 (external, cli)")
    }
}
