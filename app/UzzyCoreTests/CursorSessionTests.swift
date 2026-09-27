import Foundation
import SQLite3
import Testing
import UzzyCore

/// Cursor's session as the panel sees it: the access token Cursor keeps in
/// its `state.vscdb`, read-only, and the account in the token's `sub`. Each
/// test builds its own database with fictional tokens.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CursorSessionTests {
    let clock = ManualClock(Samples.readingMoment)
    let transport = ControlledTransport()
    let database: SampleCursorDatabase
    let core: UsageCore

    init() throws {
        database = try SampleCursorDatabase()
        core = UsageCore(
            claudeSessionReader: NoSessionReader(),
            codexSessionReader: NoSessionReader(),
            cursorSessionReader: CursorSessionReader(databaseFile: database.file),
            transport: transport,
            clock: clock,
            log: RecordingLog()
        )
    }

    func cursorContent() -> CardContent? {
        core.state.cards.first(where: { $0.provider == .cursor })?.content
    }

    func openPanel() async {
        core.panelOpened()
        await core.queriesFinished()
    }

    func showsQuotas() -> Bool {
        if case .quotas = cursorContent() { true } else { false }
    }

    @Test func queriesWithTheAccessTokenCursorKeeps() async throws {
        let token = SampleCursorDatabase.token(subject: "auth0|sample-user")
        try database.store(accessToken: token)

        await openPanel()

        #expect(showsQuotas())
        #expect(await transport.requests(to: .cursor).first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }

    @Test func withoutCursorsDatabaseThereIsNoSessionAndNoQuery() async throws {
        try FileManager.default.removeItem(at: database.file)

        await openPanel()

        #expect(cursorContent() == .failed(.noSession))
        #expect(await transport.requests(to: .cursor).isEmpty)
    }

    @Test(arguments: [nil, ""])
    func withoutAnAccessTokenThereIsNoSessionAndNoQuery(token: String?) async throws {
        try database.store(accessToken: token)

        await openPanel()

        #expect(cursorContent() == .failed(.noSession))
        #expect(await transport.requests(to: .cursor).isEmpty)
    }

    @Test func aDatabaseWithoutItsTableIsAnIncompatibleSession() async throws {
        try database.dropTable()

        await openPanel()

        #expect(cursorContent() == .failed(.incompatibleSession))
        #expect(await transport.requests(to: .cursor).isEmpty)
    }

    @Test func anUnreadableDatabaseIsNotCalledAnIncompatibleSession() async throws {
        try FileManager.default.removeItem(at: database.file)
        try FileManager.default.createDirectory(at: database.file, withIntermediateDirectories: false)

        await openPanel()

        #expect(cursorContent() == .failed(.sessionStoreUnavailable))
        #expect(await transport.requests(to: .cursor).isEmpty)
    }

    @Test func aLockedDatabaseExplainsThatTheSessionIsBusy() async throws {
        var lock: OpaquePointer?
        guard sqlite3_open(database.file.path(percentEncoded: false), &lock) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer {
            sqlite3_exec(lock, "ROLLBACK", nil, nil, nil)
            sqlite3_close(lock)
        }
        guard sqlite3_exec(lock, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }

        await openPanel()

        #expect(cursorContent() == .failed(.sessionStoreBusy))
        #expect(await transport.requests(to: .cursor).isEmpty)
    }

    /// Cursor renews its token often; the account behind it stays the same.
    @Test func aRenewedTokenOfTheSameAccountKeepsItsQuotas() async throws {
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"))
        await openPanel()

        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user", issuedAt: 2))
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(showsQuotas())
        await transport.release()
        await core.queriesFinished()
    }

    @Test func aTokenOfAnotherAccountClearsThePreviousReading() async throws {
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"))
        await openPanel()

        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|other-user"))
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(cursorContent() == .loadingNewAccount)
        await transport.release()
        await core.queriesFinished()
    }

    /// A token whose account cannot be read may be anyone's.
    @Test(arguments: ["not-a-jwt", "e30.e30.c2lnbmF0dXJl", "e30.bm90IGpzb24.c2lnbmF0dXJl"])
    func aTokenWithoutAReadableSubjectHidesThePreviousReading(token: String) async throws {
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"))
        await openPanel()

        try database.store(accessToken: token)
        await transport.hold()
        core.refresh()
        await transport.waitForRequests(2)

        #expect(cursorContent() == .loading)
        await transport.release()
        await core.queriesFinished()
    }

    @Test(arguments: [false, true])
    func readingTheSessionNeverChangesCursorsDatabase(writeAheadLog: Bool) async throws {
        try database.store(accessToken: SampleCursorDatabase.token(subject: "auth0|sample-user"), writeAheadLog: writeAheadLog)
        let before = try database.snapshot()

        await openPanel()
        core.refresh()
        await core.queriesFinished()

        #expect(showsQuotas())
        #expect(try database.snapshot() == before)
    }
}

/// A fictional `state.vscdb` in a temporary directory, shaped like Cursor's.
struct SampleCursorDatabase {
    struct Snapshot: Equatable {
        let contents: Data
        let modified: Date?
    }

    let file: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "uzzy-cursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appending(path: "state.vscdb")
        try execute("CREATE TABLE ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
    }

    /// A fictional JWT with the given `sub`. Its signature is not valid.
    static func token(subject: String, issuedAt: Int = 1) -> String {
        func encoded(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        let header = encoded(#"{"alg":"HS256","typ":"JWT"}"#)
        let payload = encoded(#"{"sub":"\#(subject)","time":"\#(issuedAt)","type":"session","scope":"openid"}"#)
        return "\(header).\(payload).c2FtcGxlLXNpZ25hdHVyZQ"
    }

    /// Stores the access token, with the neighbouring keys Cursor keeps, or
    /// removes it when `nil`.
    func store(accessToken: String?, writeAheadLog: Bool = false) throws {
        if writeAheadLog {
            try execute("PRAGMA journal_mode=WAL")
        }
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/refreshToken', 'sample-refresh-token')")
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/cachedEmail', 'sample@example.com')")
        if let accessToken {
            try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '\(accessToken)')")
        } else {
            try execute("DELETE FROM ItemTable WHERE key = 'cursorAuth/accessToken'")
        }
    }

    /// Stores the plan Cursor keeps next to the session, given as an SQL
    /// literal (`'pro_plus'`, `X'FF'`…), or removes it when `nil`.
    func store(membershipType literal: String?) throws {
        if let literal {
            try execute("INSERT INTO ItemTable VALUES ('cursorAuth/stripeMembershipType', \(literal))")
        } else {
            try execute("DELETE FROM ItemTable WHERE key = 'cursorAuth/stripeMembershipType'")
        }
    }

    func dropTable() throws {
        try execute("DROP TABLE ItemTable")
    }

    func snapshot() throws -> Snapshot {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))
        return Snapshot(contents: try Data(contentsOf: file), modified: attributes[.modificationDate] as? Date)
    }

    private func execute(_ sql: String) throws {
        var database: OpaquePointer?
        defer { sqlite3_close_v2(database) }
        guard sqlite3_open(file.path(percentEncoded: false), &database) == SQLITE_OK,
              sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK
        else { throw CocoaError(.fileWriteUnknown) }
    }
}
