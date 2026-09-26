import Foundation
import Testing
import UzzyCore

/// The plan next to each card's title: read from what the provider already
/// reports, named as the provider names it, and never guessed.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PlanTests {
    let clock = ManualClock(Samples.readingMoment)
    let transport = ControlledTransport()

    func openPanel(_ core: UsageCore) async {
        core.panelOpened()
        await core.queriesFinished()
    }

    func card(_ provider: Provider, of core: UsageCore) -> Card? {
        core.state.cards.first { $0.provider == provider }
    }

    func showsQuotas(_ card: Card?) -> Bool {
        if case .quotas = card?.content { true } else { false }
    }

    // MARK: Codex: `plan_type` in the usage response

    func codexCore() -> UsageCore {
        UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: ControlledSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    /// The sample response's windows, with `plan` as its `plan_type` JSON,
    /// or without one when `nil`.
    func codexResponse(plan: String?) -> HTTPResult {
        let planField = plan.map { #""plan_type": \#($0), "# } ?? ""
        return .json(#"""
        {\#(planField)"rate_limit": {"primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1790186400}}}
        """#)
    }

    @Test func theSampleCodexResponseIsOnPlus() async {
        let core = codexCore()

        await openPanel(core)

        #expect(card(.codex, of: core)?.plan == "Plus")
    }

    @Test(arguments: [
        ("free", "Free"), ("go", "Go"), ("plus", "Plus"), ("pro", "Pro"),
        ("team", "Team"), ("business", "Business"), ("enterprise", "Enterprise"), ("edu", "Edu"),
    ])
    func aKnownCodexPlanIsShownByChatGPTsName(planType: String, name: String) async {
        let core = codexCore()
        await transport.answer(with: codexResponse(plan: #""\#(planType)""#), for: .codex)

        await openPanel(core)

        #expect(card(.codex, of: core)?.plan == name)
    }

    /// An unknown, missing or malformed plan hides the plan and never the quotas.
    @Test(arguments: [nil, "null", #""""#, #""PLUS""#, #""plus_max""#, "1", "true", #"{"name": "plus"}"#, #"["plus"]"#])
    func anyOtherCodexPlanShowsNoPlanAndKeepsTheQuotas(planType: String?) async {
        let core = codexCore()
        await transport.answer(with: codexResponse(plan: planType), for: .codex)

        await openPanel(core)

        #expect(showsQuotas(card(.codex, of: core)))
        #expect(card(.codex, of: core)?.plan == nil)
    }

    /// Codex CLI's session is never asked for a plan: only the response names it.
    @Test func codexIgnoresAPlanInItsSession() async {
        let core = UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: ControlledSessionReader(session: Samples.claudeSession),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
        await transport.answer(with: codexResponse(plan: nil), for: .codex)

        await openPanel(core)

        #expect(card(.codex, of: core)?.plan == nil)
    }

    // MARK: Claude: `subscriptionType` in Claude Code's Keychain item

    func claudeCore(_ tool: SampleSecurityTool) -> UsageCore {
        UsageCore(
            claudeSessionReader: ClaudeCodeSessionReader(home: tool.directory, securityTool: tool.file),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    /// Claude Code's Keychain item with `subscriptionType` as `plan` JSON,
    /// or without one when `nil`.
    func claudeItem(plan: String?) -> String {
        let planField = plan.map { #", "subscriptionType": \#($0)"# } ?? ""
        return #"{"claudeAiOauth": {"accessToken": "sample-token", "refreshToken": "sample-refresh", "rateLimitTier": "sample-tier"\#(planField)}}"#
    }

    @Test(arguments: [("pro", "Pro"), ("max", "Max"), ("team", "Team"), ("enterprise", "Enterprise")])
    func aKnownClaudePlanIsShownByClaudesName(subscriptionType: String, name: String) async throws {
        let tool = try SampleSecurityTool()
        try tool.answer(output: claudeItem(plan: #""\#(subscriptionType)""#))
        let core = claudeCore(tool)

        await openPanel(core)

        #expect(card(.claude, of: core)?.plan == name)
    }

    /// The session stands whatever its plan is: it still queries, and only
    /// the plan is missing.
    @Test(arguments: [nil, "null", #""""#, #""MAX""#, #""max_20x""#, #""free""#, "5", #"{"type": "max"}"#])
    func anyOtherClaudePlanShowsNoPlanAndKeepsTheSession(subscriptionType: String?) async throws {
        let tool = try SampleSecurityTool()
        try tool.answer(output: claudeItem(plan: subscriptionType))
        let core = claudeCore(tool)

        await openPanel(core)

        #expect(showsQuotas(card(.claude, of: core)))
        #expect(card(.claude, of: core)?.plan == nil)
        #expect(await transport.requests(to: .claude).first?.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
    }

    /// Claude's usage response names no plan, whatever it holds.
    @Test func claudesPlanNeverComesFromTheUsageResponse() async throws {
        let tool = try SampleSecurityTool()
        try tool.answer(output: claudeItem(plan: nil))
        await transport.answer(with: .json(#"""
        {"plan_type": "max", "subscriptionType": "max", "five_hour": {"utilization": 35.0, "resets_at": "2026-09-23T17:00:00.000000+00:00"}}
        """#), for: .claude)
        let core = claudeCore(tool)

        await openPanel(core)

        #expect(showsQuotas(card(.claude, of: core)))
        #expect(card(.claude, of: core)?.plan == nil)
    }

    // MARK: Cursor: `cursorAuth/stripeMembershipType` in its `state.vscdb`

    func cursorCore(_ database: SampleCursorDatabase) -> UsageCore {
        UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: CursorSessionReader(databaseFile: database.file),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    @Test(arguments: [("free", "Hobby"), ("pro", "Pro"), ("pro_plus", "Pro+"), ("ultra", "Ultra")])
    func aKnownCursorPlanIsShownByCursorsName(membershipType: String, name: String) async throws {
        let database = try SampleCursorDatabase()
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"))
        try database.store(membershipType: "'\(membershipType)'")
        let core = cursorCore(database)

        await openPanel(core)

        #expect(card(.cursor, of: core)?.plan == name)
    }

    /// Stored as text or as a blob of text, like the access token.
    @Test func aCursorPlanStoredAsABlobOfTextIsRead() async throws {
        let database = try SampleCursorDatabase()
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"))
        try database.store(membershipType: "CAST('pro_plus' AS BLOB)")
        let core = cursorCore(database)

        await openPanel(core)

        #expect(card(.cursor, of: core)?.plan == "Pro+")
    }

    /// The session stands whatever its plan is: it still queries, and only
    /// the plan is missing.
    @Test(arguments: [nil, "NULL", "''", "'PRO_PLUS'", "'free_trial'", "'enterprise'", "42", "X'FF'"])
    func anyOtherCursorPlanShowsNoPlanAndKeepsTheSession(membershipType: String?) async throws {
        let database = try SampleCursorDatabase()
        let token = SampleCursorDatabase.token(subject: "auth0|sample-user")
        try database.store(accessToken: token)
        try database.store(membershipType: membershipType)
        let core = cursorCore(database)

        await openPanel(core)

        #expect(showsQuotas(card(.cursor, of: core)))
        #expect(card(.cursor, of: core)?.plan == nil)
        #expect(await transport.requests(to: .cursor).first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test func readingCursorsPlanNeverChangesItsDatabase() async throws {
        let database = try SampleCursorDatabase()
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"))
        try database.store(membershipType: "'pro_plus'")
        let before = try database.snapshot()
        let core = cursorCore(database)

        await openPanel(core)

        #expect(card(.cursor, of: core)?.plan == "Pro+")
        #expect(try database.snapshot() == before)
    }

    // MARK: When the plan is shown

    func claudeCore(_ sessionReader: ControlledSessionReader) -> UsageCore {
        UsageCore(
            claudeSessionReader: sessionReader,
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    @Test func noPlanIsShownBeforeTheFirstReading() async {
        let core = claudeCore(ControlledSessionReader(session: Samples.claudeSession))
        await transport.hold()

        core.panelOpened()
        await transport.waitForRequests(1)

        #expect(card(.claude, of: core)?.content == .loading)
        #expect(card(.claude, of: core)?.plan == nil)
        await transport.release()
        await core.queriesFinished()
    }

    /// The plan tells whose figures they are, so it stays with them.
    @Test func thePlanStaysWithTheStaleQuotasAfterAFailedQuery() async {
        let core = claudeCore(ControlledSessionReader(session: Samples.claudeSession))
        await openPanel(core)

        await transport.answer(with: .networkError, for: .claude)
        core.refresh()
        await core.queriesFinished()

        guard case .stale = card(.claude, of: core)?.content else {
            Issue.record("Not stale: \(String(describing: card(.claude, of: core)?.content))")
            return
        }
        #expect(card(.claude, of: core)?.plan == "Max")
    }

    @Test(arguments: [401, 403, 503])
    func aFailedFirstQueryShowsNoPlan(status: Int) async {
        let core = claudeCore(ControlledSessionReader(session: Samples.claudeSession))
        await transport.answer(with: .status(status), for: .claude)

        await openPanel(core)

        #expect(card(.claude, of: core)?.plan == nil)
    }

    @Test func aSessionWithoutUsableQuotasShowsNoPlan() async {
        let sessionReader = ControlledSessionReader(session: Samples.claudeSession)
        let core = claudeCore(sessionReader)
        await openPanel(core)

        await sessionReader.answer(with: .noSession)
        core.refresh()
        await core.queriesFinished()

        #expect(card(.claude, of: core)?.content == .failed(.noSession))
        #expect(card(.claude, of: core)?.plan == nil)
    }

    /// The previous account's plan goes with its figures; the new account's
    /// plan comes with its first reading.
    @Test func anotherAccountShowsItsOwnPlanOnlyOnceItsQuotasArrive() async {
        let sessionReader = ControlledSessionReader(session: Samples.claudeSession)
        let core = claudeCore(sessionReader)
        await openPanel(core)

        await sessionReader.answer(with: .session(Session(accessToken: "other-token", accountID: "other-account", plan: "pro")))
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(card(.claude, of: core)?.content == .loadingNewAccount)
        #expect(card(.claude, of: core)?.plan == nil)
        await transport.release()
        await core.queriesFinished()
        #expect(card(.claude, of: core)?.plan == "Pro")
    }

    /// An upgrade keeps the account: the next reading brings the new plan.
    @Test func aChangedPlanOfTheSameAccountIsShownWithTheNextReading() async {
        let sessionReader = ControlledSessionReader(session: Session(accessToken: "sample-token", accountID: "sample-account", plan: "pro"))
        let core = claudeCore(sessionReader)
        await openPanel(core)
        #expect(card(.claude, of: core)?.plan == "Pro")

        await sessionReader.answer(with: .session(Samples.claudeSession))
        core.refresh()
        await core.queriesFinished()

        #expect(card(.claude, of: core)?.plan == "Max")
    }

    /// Queries no user action asked for reuse the session read last, plan
    /// included, and keep showing it.
    @Test func anAutomaticQueryKeepsThePlanOfTheReusedSession() async {
        let sessionReader = ControlledSessionReader(session: Samples.claudeSession)
        let core = claudeCore(sessionReader)
        await openPanel(core)

        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        #expect(await transport.requests(to: .claude).count == 2)
        #expect(await sessionReader.reads == 1)
        #expect(card(.claude, of: core)?.plan == "Max")
    }
}
