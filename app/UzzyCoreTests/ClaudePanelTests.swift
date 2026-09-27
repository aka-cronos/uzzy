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

    @Test func queriesClaudeUsageWithOnlyTheAccessToken() async {
        let transport = SampleTransport()
        let core = core(transport: transport)

        core.panelOpened()
        await core.queriesFinished()

        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.httpMethod == "GET")
        #expect(requests.first?.url == URL(string: "https://api.anthropic.com/api/oauth/usage"))
        #expect(requests.first?.allHTTPHeaderFields == ["Authorization": "Bearer sample-token"])
    }
}
