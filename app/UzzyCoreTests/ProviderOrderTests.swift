import Foundation
import Testing
import UzzyCore

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ProviderOrderTests {
    let clock = ManualClock(Samples.readingMoment)
    let claudeReader = ControlledSessionReader()
    let codexReader = ControlledSessionReader()
    let cursorReader = ControlledSessionReader()
    let transport = ControlledTransport()

    func makeCore(
        order: [Provider] = Provider.allCases,
        enabled: Set<Provider> = Set(Provider.allCases)
    ) -> UsageCore {
        UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            transport: transport,
            clock: clock,
            initialEnabledProviders: enabled,
            initialOrder: order
        )
    }

    @Test func defaultOrderIsClaudeCodexCursor() {
        let core = UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            transport: transport,
            clock: clock
        )

        #expect(core.order == [.claude, .codex, .cursor])
        #expect(core.state.cards.map(\.provider) == [.claude, .codex, .cursor])
    }

    @Test func restoredOrderSortsTheCards() {
        let core = makeCore(order: [.cursor, .claude, .codex])

        #expect(core.order == [.cursor, .claude, .codex])
        #expect(core.state.cards.map(\.provider) == [.cursor, .claude, .codex])
    }

    @Test(arguments: [[Provider]](
        [[.claude, .codex, .cursor], [.claude, .cursor, .codex], [.codex, .claude, .cursor],
         [.codex, .cursor, .claude], [.cursor, .claude, .codex], [.cursor, .codex, .claude]]
    ))
    func everyEnabledSubsetFollowsTheOrder(order: [Provider]) {
        for mask in 0 ..< 8 {
            let enabled = Set(Provider.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            let core = makeCore(order: order, enabled: enabled)

            #expect(core.state.cards.map(\.provider) == order.filter(enabled.contains))
            #expect(core.order == order)
        }
    }

    @Test func reEnablingRestoresTheSavedPosition() async {
        let core = makeCore(order: [.cursor, .claude, .codex])
        core.panelOpened()
        await core.queriesFinished()

        core.setEnabled(false, for: .claude)
        #expect(core.state.cards.map(\.provider) == [.cursor, .codex])
        #expect(core.order == [.cursor, .claude, .codex])

        core.setEnabled(true, for: .claude)
        #expect(core.state.cards.map(\.provider) == [.cursor, .claude, .codex])
        #expect(core.state.cards[1].content == .loading)
        await core.queriesFinished(of: .claude)
        #expect(await claudeReader.reads == 2)
    }

    @Test func allDisabledKeepsTheOrder() {
        let core = makeCore(order: [.cursor, .codex, .claude], enabled: [])
        core.setOrder([.codex, .cursor, .claude])

        #expect(core.state.cards.isEmpty)
        #expect(core.order == [.codex, .cursor, .claude])

        core.setEnabled(true, for: .claude)
        core.setEnabled(true, for: .codex)
        #expect(core.state.cards.map(\.provider) == [.codex, .claude])
    }

    @Test func reorderingKeepsDisabledProvidersInPlace() {
        let core = makeCore(enabled: [.claude, .cursor])
        core.setOrder([.cursor, .codex, .claude])

        #expect(core.state.cards.map(\.provider) == [.cursor, .claude])
        core.setEnabled(true, for: .codex)
        #expect(core.state.cards.map(\.provider) == [.cursor, .codex, .claude])
    }

    @Test func setOrderRestoresACanonicalPermutation() {
        let core = makeCore()

        core.setOrder([.cursor, .cursor])
        #expect(core.order == [.cursor, .claude, .codex])

        core.setOrder([])
        #expect(core.order == [.claude, .codex, .cursor])
    }

    @Test func reorderingDuringAQueryKeepsItsResultAndStartsNoWork() async {
        let core = makeCore()
        await transport.hold(.claude)
        core.panelOpened()
        await transport.waitForRequests(3)
        await core.queriesFinished(of: .codex)
        await core.queriesFinished(of: .cursor)
        let deadlines = clock.scheduledDeadlines

        core.setOrder([.cursor, .codex, .claude])

        #expect(core.state.cards.map(\.provider) == [.cursor, .codex, .claude])
        #expect(core.state.cards[2].content == .loading)
        #expect(core.state.isQuerying)
        guard case .quotas = core.state.cards[0].content else {
            Issue.record("Reordering lost Cursor's reading")
            return
        }

        await transport.release()
        await core.queriesFinished()

        guard case .quotas = core.state.cards[2].content else {
            Issue.record("Reordering lost the in-flight result")
            return
        }
        #expect(clock.scheduledDeadlines == deadlines)
        #expect(await claudeReader.reads == 1)
        #expect(await codexReader.reads == 1)
        #expect(await cursorReader.reads == 1)
        #expect(await transport.requests.count == 3)
    }

    @Test func reorderingKeepsFreshReadingsFresh() async {
        let core = makeCore()
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        core.setOrder([.codex, .claude, .cursor])
        clock.advance(by: 60)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await transport.requests.count == 3)
        #expect(core.order == [.codex, .claude, .cursor])
    }
}

struct RestoredProviderOrderTests {
    @Test func missingOrInvalidRootUsesTheDefault() {
        #expect(Provider.order(restoring: nil) == [.claude, .codex, .cursor])
        #expect(Provider.order(restoring: "cursor") == [.claude, .codex, .cursor])
        #expect(Provider.order(restoring: 3) == [.claude, .codex, .cursor])
        #expect(Provider.order(restoring: ["cursor": "claude"]) == [.claude, .codex, .cursor])
        #expect(Provider.order(restoring: [String]()) == [.claude, .codex, .cursor])
    }

    @Test func restoresASavedPermutation() {
        #expect(Provider.order(restoring: ["cursor", "claude", "codex"]) == [.cursor, .claude, .codex])
    }

    @Test func ignoresUnknownIdentifiersAndKeepsTheFirstDuplicate() {
        let stored: [Any] = ["gemini", "cursor", 7, "Claude", "codex", "cursor"]

        #expect(Provider.order(restoring: stored) == [.cursor, .codex, .claude])
    }

    @Test func appendsMissingProvidersInDefaultOrder() {
        #expect(Provider.order(restoring: ["cursor"]) == [.cursor, .claude, .codex])
        #expect(Provider.order(restoring: ["codex", "unknown"]) == [.codex, .claude, .cursor])
    }

    @Test func storesStableIdentifiersThatRoundTrip() {
        #expect(Provider.allCases.map(\.identifier) == ["claude", "codex", "cursor"])
        let order: [Provider] = [.codex, .cursor, .claude]

        #expect(Provider.order(restoring: order.map(\.identifier)) == order)
    }

    @Test func canonicalizesAnOrderOfProviders() {
        #expect(Provider.order(completing: [.codex, .codex]) == [.codex, .claude, .cursor])
    }
}
