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
