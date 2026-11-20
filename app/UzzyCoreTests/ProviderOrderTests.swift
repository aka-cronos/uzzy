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
    let antigravityReader = ControlledSessionReader()
    let transport = ControlledTransport()

    func makeCore(
        order: [Provider] = Provider.allCases,
        enabled: Set<Provider> = Set(Provider.allCases)
    ) -> UsageCore {
        UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            antigravitySessionReader: antigravityReader,
            transport: transport,
            clock: clock,
            initialEnabledProviders: enabled,
            initialOrder: order
        )
    }

    @Test func defaultOrderIsClaudeCodexCursorAntigravity() {
        let core = UsageCore(
            claudeSessionReader: claudeReader,
            codexSessionReader: codexReader,
            cursorSessionReader: cursorReader,
            antigravitySessionReader: antigravityReader,
            transport: transport,
            clock: clock
        )

        #expect(core.order == [.claude, .codex, .cursor, .antigravity])
        #expect(core.state.cards.map(\.provider) == [.claude, .codex, .cursor, .antigravity])
    }

    @Test func restoredOrderSortsTheCards() {
        let core = makeCore(order: [.antigravity, .cursor, .claude, .codex])

        #expect(core.order == [.antigravity, .cursor, .claude, .codex])
        #expect(core.state.cards.map(\.provider) == [.antigravity, .cursor, .claude, .codex])
    }

    @Test(arguments: [[Provider]](
        [[.claude, .codex, .cursor, .antigravity], [.antigravity, .cursor, .codex, .claude],
         [.codex, .antigravity, .claude, .cursor], [.cursor, .claude, .antigravity, .codex]]
    ))
    func everyEnabledSubsetFollowsTheOrder(order: [Provider]) {
        for mask in 0 ..< 1 << Provider.allCases.count {
            let enabled = Set(Provider.allCases.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element))
            let core = makeCore(order: order, enabled: enabled)

            #expect(core.state.cards.map(\.provider) == order.filter(enabled.contains))
            #expect(core.order == order)
        }
    }

    @Test func reEnablingRestoresTheSavedPosition() async {
        let core = makeCore(order: [.cursor, .claude, .codex, .antigravity])
        core.panelOpened()
        await core.queriesFinished()

        core.setEnabled(false, for: .claude)
        #expect(core.state.cards.map(\.provider) == [.cursor, .codex, .antigravity])
        #expect(core.order == [.cursor, .claude, .codex, .antigravity])

        core.setEnabled(true, for: .claude)
        #expect(core.state.cards.map(\.provider) == [.cursor, .claude, .codex, .antigravity])
        #expect(core.state.cards[1].content == .loading)
        await core.queriesFinished(of: .claude)
        #expect(await claudeReader.reads == 2)
    }

    @Test func allDisabledKeepsTheOrder() {
        let core = makeCore(order: [.cursor, .codex, .claude, .antigravity], enabled: [])
        core.setOrder([.antigravity, .codex, .cursor, .claude])

        #expect(core.state.cards.isEmpty)
        #expect(core.order == [.antigravity, .codex, .cursor, .claude])

        core.setEnabled(true, for: .claude)
        core.setEnabled(true, for: .antigravity)
        #expect(core.state.cards.map(\.provider) == [.antigravity, .claude])
    }

    @Test func reorderingKeepsDisabledProvidersInPlace() {
        let core = makeCore(enabled: [.claude, .cursor])
        core.setOrder([.cursor, .antigravity, .codex, .claude])

        #expect(core.state.cards.map(\.provider) == [.cursor, .claude])
        core.setEnabled(true, for: .antigravity)
        #expect(core.state.cards.map(\.provider) == [.cursor, .antigravity, .claude])
    }

    @Test func setOrderRestoresACanonicalPermutation() {
        let core = makeCore()

        core.setOrder([.cursor, .cursor])
        #expect(core.order == [.cursor, .claude, .codex, .antigravity])

        core.setOrder([])
        #expect(core.order == [.claude, .codex, .cursor, .antigravity])
    }

    @Test func reorderingDuringAQueryKeepsItsResultAndStartsNoWork() async {
        let core = makeCore()
        await transport.hold(.claude)
        core.panelOpened()
        await transport.waitForQuotaRequests(4)
        await core.queriesFinished(of: .codex)
        await core.queriesFinished(of: .cursor)
        await core.queriesFinished(of: .antigravity)
        let deadlines = clock.scheduledDeadlines

        core.setOrder([.cursor, .codex, .claude, .antigravity])

        #expect(core.state.cards.map(\.provider) == [.cursor, .codex, .claude, .antigravity])
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
        #expect(await antigravityReader.reads == 1)
        // Cursor and Antigravity each make two quota queries.
        #expect(await transport.quotaRequests.count == 6)
    }

    @Test func reorderingKeepsFreshReadingsFresh() async {
        let core = makeCore()
        core.panelOpened()
        await core.queriesFinished()
        core.panelClosed()

        core.setOrder([.codex, .antigravity, .claude, .cursor])
        clock.advance(by: 60)
        core.panelOpened()
        await core.queriesFinished()

        #expect(await transport.quotaRequests.count == 6)
        #expect(core.order == [.codex, .antigravity, .claude, .cursor])
    }
}

struct RestoredProviderOrderTests {
    static let defaultOrder: [Provider] = [.claude, .codex, .cursor, .antigravity]

    @Test func missingOrInvalidRootUsesTheDefault() {
        #expect(Provider.order(restoring: nil) == Self.defaultOrder)
        #expect(Provider.order(restoring: "cursor") == Self.defaultOrder)
        #expect(Provider.order(restoring: 3) == Self.defaultOrder)
        #expect(Provider.order(restoring: ["cursor": "claude"]) == Self.defaultOrder)
        #expect(Provider.order(restoring: [String]()) == Self.defaultOrder)
    }

    @Test func restoresASavedPermutation() {
        #expect(Provider.order(restoring: ["antigravity", "cursor", "claude", "codex"]) == [.antigravity, .cursor, .claude, .codex])
    }

    /// An order saved before Antigravity existed keeps its cards in place
    /// and puts Antigravity last.
    @Test func anOrderSavedBeforeAntigravityPutsItLast() {
        #expect(Provider.order(restoring: ["cursor", "claude", "codex"]) == [.cursor, .claude, .codex, .antigravity])
    }

    @Test func ignoresUnknownIdentifiersAndKeepsTheFirstDuplicate() {
        let stored: [Any] = ["gemini", "cursor", 7, "Claude", "codex", "cursor"]

        #expect(Provider.order(restoring: stored) == [.cursor, .codex, .claude, .antigravity])
    }

    @Test func appendsMissingProvidersInDefaultOrder() {
        #expect(Provider.order(restoring: ["cursor"]) == [.cursor, .claude, .codex, .antigravity])
        #expect(Provider.order(restoring: ["codex", "unknown"]) == [.codex, .claude, .cursor, .antigravity])
    }

    @Test func storesStableIdentifiersThatRoundTrip() {
        #expect(Provider.allCases.map(\.identifier) == ["claude", "codex", "cursor", "antigravity"])
        let order: [Provider] = [.codex, .antigravity, .cursor, .claude]

        #expect(Provider.order(restoring: order.map(\.identifier)) == order)
    }

    @Test func canonicalizesAnOrderOfProviders() {
        #expect(Provider.order(completing: [.codex, .codex]) == [.codex, .claude, .cursor, .antigravity])
    }
}
