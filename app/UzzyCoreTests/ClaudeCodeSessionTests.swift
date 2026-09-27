import Foundation
import Testing
import UzzyCore

/// Claude Code's session as the panel sees it: the access token in the
/// Keychain item, read through `security`. Each test runs a fictional
/// `security` that answers like the real one, so no real Keychain is read.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClaudeCodeSessionTests {
    let transport = ControlledTransport()
    let tool: SampleSecurityTool
    let core: UsageCore

    init() throws {
        tool = try SampleSecurityTool()
        core = UsageCore(
            claudeSessionReader: ClaudeCodeSessionReader(home: tool.directory, securityTool: tool.file),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            transport: transport,
            clock: ManualClock(Samples.readingMoment),
            log: RecordingLog()
        )
    }

    func claudeContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .claude })?.content
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @Test func queriesWithTheAccessTokenClaudeCodeKeeps() async throws {
        try tool.answer(output: #"{"claudeAiOauth":{"accessToken":"sample-token","refreshToken":"sample-refresh"}}"#)

        await openPanel()

        #expect(await transport.requests(to: .claude).first?.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token")
    }

    @Test func asksForTheItemPasswordOfClaudeCodesService() async throws {
        try tool.answer(output: #"{"claudeAiOauth":{"accessToken":"sample-token"}}"#)

        await openPanel()

        #expect(try tool.arguments() == ["find-generic-password", "-s", "Claude Code-credentials", "-w"])
    }

    @Test func withoutTheKeychainItemThereIsNoSessionAndNoQuery() async throws {
        try tool.answer(exitStatus: 44)

        await openPanel()

        #expect(claudeContent() == .failed(.noSession))
        #expect(await transport.requests(to: .claude).isEmpty)
    }

    @Test(arguments: [Int32(128), 51])
    func aDeniedPromptIsAccessDenied(exitStatus: Int32) async throws {
        try tool.answer(exitStatus: exitStatus)

        await openPanel()

        #expect(claudeContent() == .failed(.sessionAccessDenied))
        #expect(await transport.requests(to: .claude).isEmpty)
    }

    @Test func anotherKeychainErrorIsAnUnavailableStore() async throws {
        try tool.answer(exitStatus: 1)

        await openPanel()

        #expect(claudeContent() == .failed(.sessionStoreUnavailable))
        #expect(await transport.requests(to: .claude).isEmpty)
    }

    /// The tool is never written, so it cannot run.
    @Test func aMissingToolIsAnUnavailableStore() async {
        await openPanel()

        #expect(claudeContent() == .failed(.sessionStoreUnavailable))
    }

    @Test func anItemThatIsNotJSONIsAnIncompatibleSession() async throws {
        try tool.answer(output: "not json")

        await openPanel()

        #expect(claudeContent() == .failed(.incompatibleSession))
    }

    @Test(arguments: [#"{}"#, #"{"claudeAiOauth":{"accessToken":""}}"#])
    func withoutAnAccessTokenThereIsNoSessionAndNoQuery(item: String) async throws {
        try tool.answer(output: item)

        await openPanel()

        #expect(claudeContent() == .failed(.noSession))
        #expect(await transport.requests(to: .claude).isEmpty)
    }
}

/// A fictional `security` in a temporary directory: it records its
/// arguments, prints the item and exits with the given status.
struct SampleSecurityTool {
    let directory: URL
    let file: URL
    private let argumentsFile: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "uzzy-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "security")
        argumentsFile = directory.appending(path: "arguments")
    }

    func answer(output: String = "", exitStatus: Int32 = 0) throws {
        let script = """
        #!/bin/sh
        printf '%s\\n' "$@" > '\(argumentsFile.path(percentEncoded: false))'
        cat <<'ITEM'
        \(output)
        ITEM
        exit \(exitStatus)
        """
        try Data(script.utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
    }

    func arguments() throws -> [String] {
        try String(contentsOf: argumentsFile, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}
