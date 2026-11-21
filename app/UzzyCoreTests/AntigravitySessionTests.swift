import Foundation
import Synchronization
import Testing
import UzzyCore

/// Antigravity's session as the panel sees it: the Keychain item (service
/// `gemini`, account `antigravity`), other Antigravity clients' token files
/// under `~/.t3/userdata/providers/antigravity/<profile>/antigravity-acp/antigravity-oauth-token`,
/// and a running Antigravity app's local service (`hub_*.json` over `127.0.0.1`).
/// Each test uses a temporary home folder, a fictional `security` and a fake
/// transport, so no real Keychain, file or network is touched.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AntigravitySessionTests {
    let clock = ManualClock(Samples.readingMoment)
    let transport = ControlledTransport()
    let tool: SampleSecurityTool
    let alive = AliveProcesses([4242])
    let core: UsageCore

    init() throws {
        tool = try SampleSecurityTool()
        let clock = clock
        let alive = alive
        core = UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: NoSessionReader(),
            antigravitySessionReader: AntigravitySessionReader(
                securityTool: tool.file,
                home: tool.directory,
                transport: transport,
                now: { clock.now() },
                isAlive: { pid in alive.contains(pid) }
            ),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    /// The item as Antigravity writes it: `go-keyring-base64:` and the
    /// base64 of its JSON. Fictional values.
    nonisolated static func item(_ json: String) -> String {
        "go-keyring-base64:" + Data(json.utf8).base64EncodedString()
    }

    /// Fresh at `Samples.readingMoment` (2026-09-23T14:32:00Z): expires at
    /// 2026-09-23T21:30:00Z.
    nonisolated static let sampleItem = item("""
        {"auth_method":"consumer","id_token_email":"sample@example.com",\
        "token":{"access_token":"sample-token","token_type":"Bearer","refresh_token":"sample-refresh",\
        "expiry":"2026-09-23T15:30:00-06:00","expires_in":3599},"writer_id":"sample-writer"}
        """)

    /// Expired at `Samples.readingMoment` (2026-09-23T14:32:00Z): expired at
    /// 2026-09-23T14:00:00Z.
    nonisolated static let expiredItem = item("""
        {"auth_method":"consumer","id_token_email":"sample@example.com",\
        "token":{"access_token":"expired-keychain-token","token_type":"Bearer","refresh_token":"sample-refresh",\
        "expiry":"2026-09-23T14:00:00Z","expires_in":3599}}
        """)

    func antigravityCard() -> Card? {
        core.state.cards.first(where: { $0.provider == .antigravity })
    }

    func antigravityContent() -> CardContent? {
        antigravityCard()?.content
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    @discardableResult
    func writeT3TokenFile(profile: String, content: String) throws -> URL {
        let directory = tool.directory
            .appending(path: ".t3/userdata/providers/antigravity/\(profile)/antigravity-acp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "antigravity-oauth-token")
        try Data(content.utf8).write(to: file)
        return file
    }

    @discardableResult
    func writeHubFile(
        variant: String = "antigravity-insiders",
        name: String = "hub_50001.json",
        content: String,
        modifiedAt: Date? = nil
    ) throws -> URL {
        let directory = tool.directory
            .appending(path: ".gemini/\(variant)/daemon", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name)
        try Data(content.utf8).write(to: file)
        if let modifiedAt {
            try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path(percentEncoded: false))
        }
        return file
    }

    // MARK: Source 1 — Keychain

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

    /// With a fresh Keychain token nothing changes, whatever T3 Code files or
    /// running daemons exist on disk.
    @Test func aFreshKeychainTokenWinsOverTokenFilesAndDaemons() async throws {
        try tool.answer(output: Self.sampleItem)
        try writeT3TokenFile(profile: "profile-a", content: """
            {"auth_method":"consumer","id_token_email":"other@example.com",\
            "token":{"access_token":"t3-token","expiry":"2026-09-24T00:00:00Z"}}
            """)
        try writeHubFile(content: #"{"pid":4242,"httpPort":50001,"csrfToken":"sample-csrf"}"#)

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "daily-cloudcode-pa.sandbox.googleapis.com" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer sample-token" })
    }

    /// A Keychain item without an expiry, with an unparseable one, or with Go's
    /// zero time is treated as fresh so existing Keychain sessions keep working.
    @Test(arguments: [
        #"{"id_token_email":"sample@example.com","token":{"access_token":"keychain-token"}}"#,
        #"{"id_token_email":"sample@example.com","token":{"access_token":"keychain-token","expiry":"not-a-date"}}"#,
        #"{"id_token_email":"sample@example.com","token":{"access_token":"keychain-token","expiry":"0001-01-01T00:00:00Z"}}"#,
    ])
    func aKeychainItemWithoutUsableExpiryCountsAsFresh(keychainJSON: String) async throws {
        try tool.answer(output: Self.item(keychainJSON))
        try writeT3TokenFile(profile: "profile-a", content: """
            {"id_token_email":"sample@example.com","token":{"access_token":"t3-token","expiry":"2026-09-24T00:00:00Z"}}
            """)

        await openPanel()

        #expect(await transport.quotaRequests(to: .antigravity).first?.value(forHTTPHeaderField: "Authorization") == "Bearer keychain-token")
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

    // MARK: Source 2 — Other clients' token files

    /// When the Keychain token is expired (or within the 60-second margin),
    /// Uzzy uses the freshest T3 Code token file and its account.
    @Test(arguments: ["2026-09-23T14:00:00Z", "2026-09-23T14:32:30Z"])
    func anExpiredOrNearlyExpiredKeychainFallsBackToAFreshTokenFile(keychainExpiry: String) async throws {
        try tool.answer(output: Self.item("""
            {"id_token_email":"sample@example.com",\
            "token":{"access_token":"expired-keychain-token","expiry":"\(keychainExpiry)"}}
            """))
        // Includes Go's 9-digit fractional RFC 3339 timestamp with an offset.
        try writeT3TokenFile(profile: "profile-a", content: """
            {"auth_method":"consumer","id_token_email":"t3@example.com",\
            "token":{"access_token":"t3-fresh-token","refresh_token":"ignored-refresh",\
            "expiry":"2026-09-23T10:30:00.123456789-05:00"}}
            """)

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer t3-fresh-token" })
        guard case .quotas = antigravityContent() else {
            Issue.record("The Antigravity card does not show its quotas")
            return
        }
    }

    @Test func aMissingKeychainFallsBackToTheFreshestValidTokenFile() async throws {
        try tool.answer(exitStatus: 44)
        // Older fresh file
        try writeT3TokenFile(profile: "profile-older", content: """
            {"id_token_email":"older@example.com",\
            "token":{"access_token":"older-token","expiry":"2026-09-23T15:00:00Z"}}
            """)
        // Freshest valid file
        try writeT3TokenFile(profile: "profile-freshest", content: """
            {"id_token_email":"freshest@example.com",\
            "token":{"access_token":"freshest-token","expiry":"2026-09-23T16:00:00.654321-00:00"}}
            """)
        // Missing expiry, zero time, and malformed files are silently ignored.
        try writeT3TokenFile(profile: "profile-no-expiry", content: """
            {"id_token_email":"noexpiry@example.com","token":{"access_token":"no-expiry-token"}}
            """)
        try writeT3TokenFile(profile: "profile-zero", content: """
            {"id_token_email":"zero@example.com","token":{"access_token":"zero-token","expiry":"0001-01-01T00:00:00Z"}}
            """)
        try writeT3TokenFile(profile: "profile-bad", content: "not json")

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer freshest-token" })
    }

    @Test func aFreshTokenFileWinsOverALiveDaemon() async throws {
        try tool.answer(output: Self.expiredItem)
        try writeT3TokenFile(profile: "profile-a", content: """
            {"auth_method":"consumer","id_token_email":"t3@example.com",\
            "token":{"access_token":"t3-fresh-token","expiry":"2026-09-23T16:00:00Z"}}
            """)
        try writeHubFile(content: #"{"pid":4242,"httpPort":50001,"csrfToken":"local-csrf"}"#)

        await openPanel()

        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "daily-cloudcode-pa.sandbox.googleapis.com" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer t3-fresh-token" })
        #expect(requests.allSatisfy { $0.url?.host != "127.0.0.1" })
    }

    /// Denying the Keychain prompt stops immediately rather than falling back,
    /// so reopening the panel does not prompt again.
    @Test func aDeniedKeychainPromptNeverFallsBackToTokenFilesOrDaemons() async throws {
        try tool.answer(exitStatus: 128)
        try writeT3TokenFile(profile: "profile-fresh", content: """
            {"id_token_email":"t3@example.com",\
            "token":{"access_token":"fresh-t3-token","expiry":"2026-09-23T16:00:00Z"}}
            """)
        try writeHubFile(content: #"{"pid":4242,"httpPort":50001,"csrfToken":"local-csrf"}"#)

        await openPanel()

        #expect(antigravityContent() == .failed(.sessionAccessDenied))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    @Test func aFreshTokenFileBeatsAnIncompatibleKeychainAndAnExpiredOneDoesNotMaskIt() async throws {
        try tool.answer(output: "not json")
        try writeT3TokenFile(profile: "profile-expired", content: """
            {"id_token_email":"t3@example.com",\
            "token":{"access_token":"expired-t3-token","expiry":"2026-09-23T14:00:00Z"}}
            """)

        await openPanel()
        #expect(antigravityContent() == .failed(.incompatibleSession))

        try writeT3TokenFile(profile: "profile-fresh", content: """
            {"id_token_email":"t3@example.com",\
            "token":{"access_token":"fresh-t3-token","expiry":"2026-09-23T16:00:00Z"}}
            """)
        core.refresh()
        await core.queriesFinished()

        #expect(await transport.quotaRequests(to: .antigravity).last?.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-t3-token")
    }

    /// Symlinks and oversized token files are skipped silently.
    @Test func symlinksAndOversizedTokenFilesAreIgnored() async throws {
        try tool.answer(exitStatus: 44)
        let target = tool.directory.appending(path: "real-token")
        try Data("""
            {"id_token_email":"sym@example.com","token":{"access_token":"sym-token","expiry":"2026-09-24T00:00:00Z"}}
            """.utf8).write(to: target)
        let symDir = tool.directory.appending(path: ".t3/userdata/providers/antigravity/profile-sym/antigravity-acp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: symDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symDir.appending(path: "antigravity-oauth-token"), withDestinationURL: target)

        let padding = String(repeating: " ", count: 70_000)
        try writeT3TokenFile(profile: "profile-huge", content: """
            {"id_token_email":"huge@example.com","token":{"access_token":"huge-token","expiry":"2026-09-24T00:00:00Z"},"pad":"\(padding)"}
            """)

        await openPanel()

        #expect(antigravityContent() == .failed(.noSession))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    /// When every source is expired, the card keeps its last reading as out of
    /// date with «Session expired», and the 30-second recheck picks up a fresh
    /// file as soon as T3 Code writes one.
    @Test func anExpiredTokenFileWithoutKeychainKeepsStaleReadingAndRecoversOnRenewal() async throws {
        try tool.answer(exitStatus: 44)
        try writeT3TokenFile(profile: "profile-a", content: """
            {"id_token_email":"t3@example.com",\
            "token":{"access_token":"t3-token-1","expiry":"2026-09-23T15:00:00Z"}}
            """)
        await openPanel()
        guard case .quotas = antigravityContent() else {
            Issue.record("Expected initial quotas from T3 Code token file")
            return
        }

        // Close the panel, advance past expiry, and reopen with Cloud Code rejecting the expired token.
        core.panelClosed()
        clock.advance(by: 60 * 60)
        await transport.answerAntigravityAccount(with: .status(401))
        await openPanel()

        guard case .stale(_, failure: .sessionExpired) = antigravityContent() else {
            Issue.record("Expected stale reading with sessionExpired, got \(String(describing: antigravityContent()))")
            return
        }

        // T3 Code writes a new token; the 30s recheck picks it up automatically.
        try writeT3TokenFile(profile: "profile-a", content: """
            {"id_token_email":"t3@example.com",\
            "token":{"access_token":"t3-token-2","expiry":"2026-09-23T17:00:00Z"}}
            """)
        await transport.answerAntigravityAccount(with: .antigravityAccountSample)
        clock.advance(by: 30)
        await core.queriesFinished()

        guard case .quotas = antigravityContent() else {
            Issue.record("Expected automatic recovery after T3 Code renewed its token")
            return
        }
        #expect(await transport.quotaRequests(to: .antigravity).last?.value(forHTTPHeaderField: "Authorization") == "Bearer t3-token-2")
    }

    /// With both Keychain and T3 Code expired, the expired Keychain session
    /// still runs so Cloud Code returns 401 and the card keeps its stale reading.
    @Test func allExpiredSourcesFallBackToTheExpiredKeychainSession() async throws {
        try tool.answer(output: Self.sampleItem)
        await openPanel()

        try tool.answer(output: Self.expiredItem)
        try writeT3TokenFile(profile: "profile-a", content: """
            {"id_token_email":"other@example.com",\
            "token":{"access_token":"expired-t3-token","expiry":"2026-09-23T14:15:00Z"}}
            """)
        await transport.answerAntigravityAccount(with: .status(401))

        core.refresh()
        await core.queriesFinished()

        guard case .stale(_, failure: .sessionExpired) = antigravityContent() else {
            Issue.record("Expected stale reading with sessionExpired, got \(String(describing: antigravityContent()))")
            return
        }
        #expect(await transport.quotaRequests(to: .antigravity).last?.value(forHTTPHeaderField: "Authorization") == "Bearer expired-keychain-token")
    }

    // MARK: Source 3 — Local daemon (stable and Insiders)

    @Test(arguments: ["antigravity", "antigravity-insiders"])
    func fallsBackToRunningLocalDaemonWhenNoFreshTokenExists(variant: String) async throws {
        try tool.answer(output: Self.expiredItem)
        try writeHubFile(
            variant: variant,
            name: "hub_50001.json",
            content: #"{"pid":4242,"httpPort":50001,"httpsPort":50002,"lsVersion":"1.0","csrfToken":"local-csrf"}"#
        )

        await openPanel()

        guard case .quotas = antigravityContent() else {
            Issue.record("Expected quotas from local daemon (\(variant))")
            return
        }
        #expect(antigravityCard()?.plan == "Google AI Pro")
        let requests = await transport.quotaRequests(to: .antigravity)
        #expect(requests.allSatisfy { $0.url?.host == "127.0.0.1" && $0.url?.port == 50001 })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "x-codeium-csrf-token") == "local-csrf" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    /// Newer hub files are tried first; a dead PID, invalid port, or failing
    /// probe falls through to the next live daemon.
    @Test func probesLiveHubFilesNewestFirstAndSkipsDeadOrUnreachableOnes() async throws {
        try tool.answer(exitStatus: 44)
        alive.set([4242, 4243])

        // Dead PID, pid 0, invalid port, and malformed JSON are skipped before any probe.
        try writeHubFile(name: "hub_1.json", content: #"{"pid":9999,"httpPort":50001,"csrfToken":"dead"}"#,
                         modifiedAt: Samples.readingMoment.addingTimeInterval(100))
        try writeHubFile(name: "hub_2.json", content: #"{"pid":0,"httpPort":50002,"csrfToken":"zero-pid"}"#,
                         modifiedAt: Samples.readingMoment.addingTimeInterval(90))
        try writeHubFile(name: "hub_3.json", content: #"{"pid":4242,"httpPort":70000,"csrfToken":"bad-port"}"#,
                         modifiedAt: Samples.readingMoment.addingTimeInterval(80))
        try writeHubFile(name: "hub_4.json", content: "not json",
                         modifiedAt: Samples.readingMoment.addingTimeInterval(70))

        // Newest live hub fails probe (unreachable); older live hub answers 200.
        try writeHubFile(variant: "antigravity-insiders", name: "hub_50010.json",
                         content: #"{"pid":4242,"httpPort":50010,"csrfToken":"csrf-new"}"#,
                         modifiedAt: Samples.readingMoment.addingTimeInterval(50))
        try writeHubFile(variant: "antigravity", name: "hub_50020.json",
                         content: #"{"pid":4243,"httpPort":50020,"csrfToken":"csrf-old"}"#,
                         modifiedAt: Samples.readingMoment.addingTimeInterval(10))
        await transport.answerAntigravityDaemonStatus(with: .networkError, port: 50010)

        await openPanel()

        guard case .quotas = antigravityContent() else {
            Issue.record("Expected quotas from the live fallback hub")
            return
        }
        let ports = await transport.quotaRequests(to: .antigravity).compactMap { $0.url?.port }
        // Probe on 50010 failed, then probe + GetUserStatus + RetrieveUserQuotaSummary on 50020.
        #expect(ports == [50010, 50020, 50020, 50020])
    }

    /// A daemon that answers 200 without a `userStatus` payload (e.g. signed out)
    /// is skipped rather than treated as a live session.
    @Test func aDaemonWithoutUserStatusIsSkipped() async throws {
        try tool.answer(exitStatus: 44)
        try writeHubFile(name: "hub_50001.json", content: #"{"pid":4242,"httpPort":50001,"csrfToken":"local-csrf"}"#)
        await transport.answerAntigravityDaemonStatus(with: .json("{}"))

        await openPanel()

        #expect(antigravityContent() == .failed(.noSession))
    }

    /// Symlinks and oversized `hub_*.json` files are ignored without probing.
    @Test func symlinksAndOversizedHubFilesAreIgnored() async throws {
        try tool.answer(exitStatus: 44)
        let target = tool.directory.appending(path: "real-hub.json")
        try Data(#"{"pid":4242,"httpPort":50001,"csrfToken":"sym-csrf"}"#.utf8).write(to: target)
        let daemonDir = tool.directory.appending(path: ".gemini/antigravity-insiders/daemon", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: daemonDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: daemonDir.appending(path: "hub_50001.json"), withDestinationURL: target)

        let padding = String(repeating: " ", count: 20_000)
        try writeHubFile(
            variant: "antigravity",
            name: "hub_50002.json",
            content: #"{"pid":4242,"httpPort":50002,"csrfToken":"huge-csrf","pad":"\#(padding)"}"#
        )

        await openPanel()

        #expect(antigravityContent() == .failed(.noSession))
        #expect(await transport.quotaRequests(to: .antigravity).isEmpty)
    }

    /// A daemon whose `userStatus` omits `email` has an uncertain identity:
    /// previous account readings are dropped rather than kept as stale.
    @Test func aDaemonWithoutAnEmailDropsPreviousAccountReadings() async throws {
        try tool.answer(output: Self.sampleItem)
        await openPanel()
        guard case .quotas = antigravityContent() else {
            Issue.record("Expected initial Keychain quotas")
            return
        }

        try tool.answer(output: Self.expiredItem)
        try writeHubFile(name: "hub_50001.json", content: #"{"pid":4242,"httpPort":50001,"csrfToken":"local-csrf"}"#)
        await transport.answerAntigravityDaemonStatus(with: .json(#"{"userStatus":{"userTier":{"id":"g1-pro-tier"}}}"#))
        await transport.answerAntigravityDaemonQuota(with: .status(500))

        core.refresh()
        await core.queriesFinished()

        #expect(antigravityContent() == .failed(.serverError(status: 500)))
    }

    /// Daemon email is case-normalized to match the Keychain `id_token_email`,
    /// so stale readings survive switching between Keychain and daemon for the
    /// same account, and clear for a different account.
    @Test func daemonIdentityMatchesKeychainAccountAcrossSwitches() async throws {
        try tool.answer(output: Self.expiredItem)
        try writeHubFile(name: "hub_50001.json", content: #"{"pid":4242,"httpPort":50001,"csrfToken":"local-csrf"}"#)
        await transport.answerAntigravityDaemonStatus(with: .json("""
            {"userStatus":{"email":"Sample@Example.COM","userTier":{"id":"g1-ultra-tier"}}}
            """))

        await openPanel()
        #expect(antigravityCard()?.plan == "Google AI Ultra")

        // Daemon stops; Keychain is still expired for the same email -> stale kept!
        alive.set([])
        await transport.answerAntigravityAccount(with: .status(401))
        core.refresh()
        await core.queriesFinished()

        guard case .stale(_, failure: .sessionExpired) = antigravityContent() else {
            Issue.record("Expected stale reading to survive daemon -> expired Keychain switch, got \(String(describing: antigravityContent()))")
            return
        }
        #expect(antigravityCard()?.plan == "Google AI Ultra")
    }

    /// An Insiders-only user (no Keychain item, no T3 Code file) keeps stale
    /// readings with «Session expired» after closing the app, and the 30-second
    /// recheck recovers automatically once Antigravity relaunches.
    @Test func aDaemonOnlySessionKeepsStaleReadingsWhenAppClosesAndRecoversOnRelaunch() async throws {
        try tool.answer(exitStatus: 44)
        let hub1 = try writeHubFile(
            variant: "antigravity-insiders",
            name: "hub_50001.json",
            content: #"{"pid":4242,"httpPort":50001,"csrfToken":"csrf-1"}"#
        )
        await openPanel()
        guard case .quotas = antigravityContent() else {
            Issue.record("Expected initial quotas from local daemon")
            return
        }

        // App closes and removes its hub file before the 5-minute refresh.
        alive.set([])
        try FileManager.default.removeItem(at: hub1)
        await transport.answerAntigravityDaemonStatus(with: .networkError, port: 50001)
        clock.advance(by: 5 * 60)
        await core.queriesFinished()

        guard case .stale(_, failure: .reusedSessionRejected) = antigravityContent() else {
            Issue.record("Expected stale reusedSessionRejected, got \(String(describing: antigravityContent()))")
            return
        }

        // First 30-second recheck while the app is still closed: stale readings
        // stay visible as `.sessionExpired` instead of dropping to `.noSession`,
        // and the recheck stays scheduled.
        clock.advance(by: 30)
        await core.queriesFinished()

        guard case .stale(_, failure: .sessionExpired) = antigravityContent() else {
            Issue.record("Expected stale sessionExpired while app is closed, got \(String(describing: antigravityContent()))")
            return
        }

        // App relaunches on a new port while the panel is still open: the next
        // 30-second recheck picks it up automatically without clicking Refresh.
        alive.set([4243])
        try writeHubFile(
            variant: "antigravity-insiders",
            name: "hub_50002.json",
            content: #"{"pid":4243,"httpPort":50002,"csrfToken":"csrf-2"}"#
        )
        clock.advance(by: 30)
        await core.queriesFinished()

        guard case .quotas = antigravityContent() else {
            Issue.record("Expected automatic recovery after app relaunched, got \(String(describing: antigravityContent()))")
            return
        }
        #expect(await transport.quotaRequests(to: .antigravity).last?.url?.port == 50002)
    }

    /// Turning Antigravity off drops the remembered daemon session, so turning
    /// it back on while the app is closed reports `.noSession`.
    @Test func disablingAntigravityClearsTheRememberedDaemonSession() async throws {
        try tool.answer(exitStatus: 44)
        let hub = try writeHubFile(
            variant: "antigravity-insiders",
            name: "hub_50001.json",
            content: #"{"pid":4242,"httpPort":50001,"csrfToken":"csrf-1"}"#
        )
        await openPanel()
        guard case .quotas = antigravityContent() else {
            Issue.record("Expected initial quotas from local daemon")
            return
        }

        alive.set([])
        try FileManager.default.removeItem(at: hub)
        core.setEnabled(false, for: .antigravity)
        core.setEnabled(true, for: .antigravity)
        await core.queriesFinished()

        #expect(antigravityContent() == .failed(.noSession))
    }
}

final class AliveProcesses: Sendable {
    private let pids: Mutex<Set<Int32>>

    init(_ pids: Set<Int32>) {
        self.pids = Mutex(pids)
    }

    func contains(_ pid: Int32) -> Bool {
        pids.withLock { $0.contains(pid) }
    }

    func set(_ pids: Set<Int32>) {
        self.pids.withLock { $0 = pids }
    }
}
