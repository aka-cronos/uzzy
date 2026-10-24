import CommonCrypto
import Foundation
import Synchronization
import Testing
import UzzyCore

/// Cursor's session encrypted with its safeStorage key, as Cursor 3.27
/// stores it. The key also protects Cursor's other secrets, so the Keychain
/// is read only after the user consents, and only on a user action. Each
/// test encrypts a fictional token with a fictional password.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CursorEncryptedSessionTests {
    nonisolated static let password = "fictional-safe-storage-password"
    nonisolated static let token = SampleCursorDatabase.token(subject: "auth0|sample-user")

    let clock = ManualClock(Samples.readingMoment)
    let transport = ControlledTransport()
    let keychain = FakeSafeStorageKeychain(.found(Data(Self.password.utf8)))
    let consent = MemoryAccessConsent()
    let database: SampleCursorDatabase
    let core: UsageCore

    init() throws {
        database = try SampleCursorDatabase()
        core = Self.core(database: database, consent: consent, keychain: keychain, transport: transport, clock: clock)
    }

    static func core(
        database: SampleCursorDatabase,
        consent: any AccessConsent,
        keychain: FakeSafeStorageKeychain,
        transport: ControlledTransport,
        clock: ManualClock,
        enabled: Set<Provider> = Set(Provider.allCases)
    ) -> UsageCore {
        UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: CursorSessionReader(databaseFile: database.file, consent: consent, keychain: keychain),
            cursorAccess: consent,
            transport: transport,
            clock: clock,
            log: RecordingLog(),
            initialEnabledProviders: enabled
        )
    }

    func cursorContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .cursor })?.content
    }

    func showsQuotas() -> Bool {
        if case .quotas = cursorContent() { true } else { false }
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    func allowAccess() async {
        core.allowCursorAccess()
        await core.queriesFinished()
    }

    func cursorRequests() async -> [URLRequest] {
        await transport.requests(to: .cursor)
    }

    // MARK: Consent

    @Test func withoutConsentTheCardAsksAndNothingIsReadOrSent() async throws {
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))

        await openPanel()
        core.refresh()
        await core.queriesFinished()

        #expect(cursorContent() == .failed(.sessionNeedsAccess))
        #expect(keychain.reads == 0)
        #expect(await cursorRequests().isEmpty)
    }

    @Test func allowingAccessDecryptsTheTokenAndQueriesWithIt() async throws {
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))
        await openPanel()

        await allowAccess()

        #expect(showsQuotas())
        #expect(core.isCursorAccessGranted)
        #expect(keychain.reads == 1)
        #expect(await cursorRequests().map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer \(Self.token)"])
    }

    /// Only a user action reads the session; the cadence and waking from
    /// sleep reuse the token already decrypted.
    @Test func automaticQueriesNeverReadTheKeychain() async throws {
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))
        await openPanel()
        await allowAccess()

        clock.advance(by: 5 * 60)
        await core.queriesFinished()
        core.systemWoke()
        await core.queriesFinished()

        #expect(keychain.reads == 1)
        #expect(await cursorRequests().count == 3)
    }

    @Test func turningCursorOffWithdrawsConsentAndTurningItOnAsksAgain() async throws {
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))
        await openPanel()
        await allowAccess()

        core.setEnabled(false, for: .cursor)
        #expect(!core.isCursorAccessGranted)
        #expect(!consent.isGranted())
        core.setEnabled(true, for: .cursor)
        await core.queriesFinished()

        #expect(cursorContent() == .failed(.sessionNeedsAccess))
        #expect(keychain.reads == 1)
        #expect(await cursorRequests().count == 1)
    }

    @Test func revokingForgetsTheSessionAndAsksAgain() async throws {
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))
        await openPanel()
        await allowAccess()

        core.revokeCursorAccess()
        await core.queriesFinished()
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        #expect(!consent.isGranted())
        #expect(cursorContent() == .failed(.sessionNeedsAccess))
        #expect(keychain.reads == 1)
        #expect(await cursorRequests().count == 1)
    }

    /// Cursor turned off in an earlier run keeps no consent saved.
    @Test func startingWithCursorOffClearsASavedConsent() async throws {
        let saved = MemoryAccessConsent(granted: true)

        let core = Self.core(database: database, consent: saved, keychain: keychain, transport: transport, clock: clock,
                             enabled: [.claude, .codex])

        #expect(!saved.isGranted())
        #expect(!core.isCursorAccessGranted)
    }

    @Test func aPlaintextTokenNeverReadsTheKeychainEvenWithConsent() async throws {
        consent.setGranted(true)
        try database.store(accessToken: Self.token)

        await openPanel()

        #expect(showsQuotas())
        #expect(keychain.reads == 0)
    }

    // MARK: Strict decoding

    /// A value Uzzy cannot decrypt is never worth a Keychain prompt, never
    /// read as plaintext and never sent.
    @Test(arguments: [
        "cursor-safe-storage:v2:\(SampleEncryption.sealed(CursorEncryptedSessionTests.token, password: CursorEncryptedSessionTests.password))",
        "cursor-safe-storage:",
        "cursor-safe-storage:v1:",
        "cursor-safe-storage:v1:not base64!",
        "cursor-safe-storage:v1:\(Data(Array("v11".utf8) + [UInt8](repeating: 1, count: 16)).base64EncodedString())",
        "cursor-safe-storage:v1:\(Data(Array("v10".utf8) + [UInt8](repeating: 1, count: 15)).base64EncodedString())",
        "cursor-safe-storage:v1:\(Data("v10".utf8).base64EncodedString())",
        "cursor-safe-storage:v1:\(String(repeating: "A", count: 20_000))",
    ])
    func aValueThatCannotBeDecryptedIsIncompatible(stored: String) async throws {
        consent.setGranted(true)
        try database.store(accessToken: stored)

        await openPanel()

        #expect(cursorContent() == .failed(.incompatibleSession))
        #expect(keychain.reads == 0)
        #expect(await cursorRequests().isEmpty)
    }

    /// CBC is not authenticated: whatever a wrong key gives is never sent.
    @Test func aWrongKeyIsIncompatibleAndSendsNothing() async throws {
        consent.setGranted(true)
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: "another-password"))

        await openPanel()

        #expect(cursorContent() == .failed(.incompatibleSession))
        #expect(keychain.reads == 1)
        #expect(await cursorRequests().isEmpty)
    }

    @Test(arguments: ["not-a-jwt", "a.b", "a..c", "a.b.c d", ""])
    func aDecryptedValueThatIsNotAJWTIsIncompatible(plaintext: String) async throws {
        consent.setGranted(true)
        try database.store(accessToken: SampleEncryption.stored(plaintext, password: Self.password))

        await openPanel()

        #expect(cursorContent() == .failed(.incompatibleSession))
        #expect(await cursorRequests().isEmpty)
    }

    // MARK: Keychain failures

    @Test func aDeniedPromptAsksAgainOnlyOnRefresh() async throws {
        keychain.answer(with: .denied)
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))
        await openPanel()
        await allowAccess()
        #expect(cursorContent() == .failed(.sessionAccessDenied))

        core.panelClosed()
        await openPanel()
        #expect(keychain.reads == 1)

        keychain.answer(with: .found(Data(Self.password.utf8)))
        core.refresh()
        await core.queriesFinished()

        #expect(keychain.reads == 2)
        #expect(showsQuotas())
    }

    @Test(arguments: [SafeStoragePassword.notFound, .unavailable])
    func aKeyThatCannotBeReadIsAnUnavailableStore(answer: SafeStoragePassword) async throws {
        keychain.answer(with: answer)
        try database.store(accessToken: SampleEncryption.stored(Self.token, password: Self.password))

        await openPanel()
        await allowAccess()

        #expect(cursorContent() == .failed(.sessionStoreUnavailable))
        #expect(await cursorRequests().isEmpty)
    }
}

/// Answers with the password set, and counts the reads.
final class FakeSafeStorageKeychain: SafeStorageKeychain {
    private let state: Mutex<(answer: SafeStoragePassword, reads: Int)>

    init(_ answer: SafeStoragePassword) {
        state = Mutex((answer, 0))
    }

    var reads: Int {
        state.withLock { $0.reads }
    }

    func answer(with answer: SafeStoragePassword) {
        state.withLock { $0.answer = answer }
    }

    func password() -> SafeStoragePassword {
        state.withLock { state in
            state.reads += 1
            return state.answer
        }
    }
}

/// Encrypts like Electron's safeStorage on macOS, for fictional values only.
enum SampleEncryption {
    /// The value as Cursor stores it in `state.vscdb`.
    static func stored(_ plaintext: String, password: String) -> String {
        "cursor-safe-storage:v1:\(sealed(plaintext, password: password))"
    }

    /// The base64 of `v10` and the AES-128-CBC ciphertext.
    static func sealed(_ plaintext: String, password: String) -> String {
        var key = [UInt8](repeating: 0, count: kCCKeySizeAES128)
        let salt = Array("saltysalt".utf8)
        _ = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2), password, password.utf8.count, salt, salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count
        )
        let input = Array(plaintext.utf8)
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var length = 0
        _ = CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
            key, key.count, [UInt8](repeating: 0x20, count: kCCBlockSizeAES128),
            input, input.count, &output, output.count, &length
        )
        return Data(Array("v10".utf8) + output.prefix(length)).base64EncodedString()
    }
}
