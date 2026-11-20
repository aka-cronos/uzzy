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
            antigravitySessionReader: AntigravitySessionReader(home: tool.directory, securityTool: tool.file),
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

    // MARK: Antigravity Insiders and local daemon fallback

    func writeDaemonFile(
        in channel: String,
        name: String,
        pid: Int32,
        port: Int,
        csrf: String,
        modifiedAt: Date? = nil
    ) throws {
        let dir = tool.directory.appending(path: ".gemini/\(channel)/daemon", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appending(path: name)
        let json = #"{"pid":\#(pid),"httpPort":\#(port),"csrfToken":"\#(csrf)"}"#
        try Data(json.utf8).write(to: file)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path(percentEncoded: false))
        }
    }

    @Test func missingKeychainItemFallsBackToRunningInsidersDaemon() async throws {
        try tool.answer(exitStatus: 44)
        let livePID = ProcessInfo.processInfo.processIdentifier
        try writeDaemonFile(in: "antigravity-insiders", name: "hub_50631.json", pid: livePID, port: 50631, csrf: "sample-csrf")
        await transport.answerAntigravityAccount(with: HTTPResult.response(
            HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Samples.antigravityLocalUserStatusResponse)
        ))

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.map(\.url) == [
            URL(string: "http://127.0.0.1:50631/exa.language_server_pb.LanguageServerService/GetUserStatus"),
            URL(string: "http://127.0.0.1:50631/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"),
        ])
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-codeium-csrf-token") == "sample-csrf" })
        #expect(core.state.cards.first(where: { $0.provider == .antigravity })?.plan == "Google AI Ultra")
    }

    @Test func expiredKeychainTokenFallsBackToRunningInsidersDaemon() async throws {
        try tool.answer(output: Self.item("""
            {"id_token_email":"sample@example.com","token":{"access_token":"expired-token","expiry":"2020-01-01T00:00:00Z"}}
            """))
        let livePID = ProcessInfo.processInfo.processIdentifier
        try writeDaemonFile(in: "antigravity-insiders", name: "hub_50631.json", pid: livePID, port: 50631, csrf: "insiders-csrf")

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.first?.url == URL(string: "http://127.0.0.1:50631/exa.language_server_pb.LanguageServerService/GetUserStatus"))
        #expect(requests.first?.value(forHTTPHeaderField: "x-codeium-csrf-token") == "insiders-csrf")
    }

    @Test func freshKeychainTokenIsPreferredOverRunningDaemon() async throws {
        try tool.answer(output: Self.item("""
            {"id_token_email":"sample@example.com","token":{"access_token":"fresh-token","expiry":"2099-01-01T00:00:00Z"}}
            """))
        let livePID = ProcessInfo.processInfo.processIdentifier
        try writeDaemonFile(in: "antigravity-insiders", name: "hub_50631.json", pid: livePID, port: 50631, csrf: "insiders-csrf")

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.first?.url == URL(string: "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:loadCodeAssist"))
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token")
    }

    @Test func deadDaemonDiscoveryFilesAreSkippedAndInsidersIsPreferredOverStable() async throws {
        try tool.answer(exitStatus: 44)
        let livePID = ProcessInfo.processInfo.processIdentifier
        let deadPID: Int32 = 999_999
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = Date(timeIntervalSince1970: 1_700_000_100)
        try writeDaemonFile(in: "antigravity-insiders", name: "hub_dead.json", pid: deadPID, port: 50001, csrf: "dead-csrf", modifiedAt: newer)
        try writeDaemonFile(in: "antigravity-insiders", name: "hub_live.json", pid: livePID, port: 50002, csrf: "insiders-live-csrf", modifiedAt: older)
        try writeDaemonFile(in: "antigravity", name: "hub_stable.json", pid: livePID, port: 50003, csrf: "stable-live-csrf", modifiedAt: newer)

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.first?.url == URL(string: "http://127.0.0.1:50002/exa.language_server_pb.LanguageServerService/GetUserStatus"))
        #expect(requests.first?.value(forHTTPHeaderField: "x-codeium-csrf-token") == "insiders-live-csrf")
    }

    @Test func deniedKeychainPromptDoesNotFallBackToDaemon() async throws {
        try tool.answer(exitStatus: 128)
        let livePID = ProcessInfo.processInfo.processIdentifier
        try writeDaemonFile(in: "antigravity-insiders", name: "hub_50631.json", pid: livePID, port: 50631, csrf: "insiders-csrf")

        await openPanel()

        #expect(antigravityContent() == .failed(.sessionAccessDenied))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }
}
