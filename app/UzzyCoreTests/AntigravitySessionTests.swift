import Foundation
import Testing
import UzzyCore

/// Antigravity's session as the panel sees it: the Google token in the
/// Keychain item Antigravity writes (service `gemini`, account
/// `antigravity`), read through `security`. Each test runs a fictional
/// `security`, so no real Keychain is read.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AntigravitySessionTests {
    let transport = ControlledTransport()
    let tool: SampleSecurityTool
    let core: UsageCore

    init() throws {
        tool = try SampleSecurityTool()
        core = UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            antigravitySessionReader: AntigravitySessionReader(securityTool: tool.file),
            transport: transport,
            clock: ManualClock(Samples.readingMoment),
            log: RecordingLog()
        )
    }

    /// The item as Antigravity writes it: `go-keyring-base64:` and the
    /// base64 of its JSON. Fictional values.
    nonisolated static func item(_ json: String) -> String {
        "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
    }

    nonisolated static let sampleItem = item("""
        {"auth_method":"consumer","id_token_email":"sample@example.com",\
        "token":{"access_token":"sample-token","token_type":"Bearer","refresh_token":"sample-refresh",\
        "expiry":"2026-09-23T15:30:00-06:00","expires_in":3599},"writer_id":"sample-writer"}
        """)

    func antigravityContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .antigravity })?.content
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test func queriesWithTheAccessTokenAntigravityKeeps() async throws {
        try tool.answer(output: Self.sampleItem)

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token" })
        guard case .quotas = antigravityContent() else {
            Issue.record("The Antigravity card does not show its quotas")
            return
        }
    }

    @Test func asksForTheItemPasswordOfAntigravitysServiceAndAccount() async throws {
        try tool.answer(output: Self.sampleItem)

        await openPanel()

        #expect(try tool.arguments() == ["find-generic-password", "-s", "gemini", "-a", "antigravity", "-w"])
    }

    /// The account is the email the item names: the readings of another
    /// Google account are never shown as this one's.
    @Test func anotherAccountInTheItemClearsThePreviousReading() async throws {
        try tool.answer(output: Self.sampleItem)
        await openPanel()
        await transport.hold(.antigravity)
        try tool.answer(output: Self.item("""
            {"id_token_email":"other@example.com","token":{"access_token":"other-token"}}
            """))

        core.refresh()
        await transport.waitForQuotaRequests(3)

        #expect(antigravityContent() == .loadingNewAccount)
        await transport.release()
        await core.queriesFinished()
    }

    /// Antigravity may keep the item as plain JSON too.
    @Test func anItemOfPlainJSONIsRead() async throws {
        try tool.answer(output: #"{"id_token_email":"sample@example.com","token":{"access_token":"sample-token"}}"#)

        await openPanel()

        #expect(await transport.quotaRequests(to: .antigravity).first?.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
    }

    @Test func withoutTheKeychainItemThereIsNoSessionAndNoQuery() async throws {
        try tool.answer(exitStatus: 44)

        await openPanel()

        #expect(antigravityContent() == .failed(.noSession))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    @Test(arguments: [Int32(128), 51])
    func aDeniedPromptIsAccessDenied(exitStatus: Int32) async throws {
        try tool.answer(exitStatus: exitStatus)

        await openPanel()

        #expect(antigravityContent() == .failed(.sessionAccessDenied))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    @Test func anotherKeychainErrorIsAnUnavailableStore() async throws {
        try tool.answer(exitStatus: 1)

        await openPanel()

        #expect(antigravityContent() == .failed(.sessionStoreUnavailable))
    }

    @Test(arguments: ["not json", "go-keyring-base64:not base64", AntigravitySessionTests.item("[]")])
    func anItemInAnotherFormatIsAnIncompatibleSession(item: String) async throws {
        try tool.answer(output: item)

        await openPanel()

        #expect(antigravityContent() == .failed(.incompatibleSession))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    @Test(arguments: [
        AntigravitySessionTests.item("{}"),
        AntigravitySessionTests.item(#"{"token":{"access_token":""}}"#),
    ])
    func withoutAnAccessTokenThereIsNoSessionAndNoQuery(item: String) async throws {
        try tool.answer(output: item)

        await openPanel()

        #expect(antigravityContent() == .failed(.noSession))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    /// Without the email the account cannot be verified, but the token still
    /// queries.
    @Test func withoutTheEmailTheIdentityIsUncertainAndTheQuotasShow() async throws {
        try tool.answer(output: Self.item(#"{"token":{"access_token":"sample-token"}}"#))

        await openPanel()

        guard case .quotas = antigravityContent() else {
            Issue.record("The Antigravity card does not show its quotas")
            return
        }
    }
}
