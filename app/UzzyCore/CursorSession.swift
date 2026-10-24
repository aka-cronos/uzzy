import Foundation
import SQLite3

/// Reads, read-only, the session Cursor keeps on this Mac: the access token
/// under `cursorAuth/accessToken` in the `ItemTable` of its `state.vscdb`,
/// and the plan under `cursorAuth/stripeMembershipType` next to it.
/// The account identity is the `sub` claim of that token.
///
/// Since Cursor 3.27 the token is encrypted with a key Cursor keeps in the
/// Keychain (`CursorSafeStorage`). That key also protects Cursor's other
/// secrets, so the Keychain is only read once the user consents, and only
/// to decrypt the access token. A token stored as plaintext never touches
/// the Keychain. It never reads the refresh token, never refreshes tokens,
/// never writes to the database or the Keychain, and never reads the stale
/// `cursor-access-token` item Cursor left in the Keychain.
public struct CursorSessionReader: SessionReader {
    private let databaseFile: URL
    private let consent: any AccessConsent
    private let keychain: any SafeStorageKeychain

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        consent: any AccessConsent,
        keychain: any SafeStorageKeychain = CursorSafeStorageKeychain()
    ) {
        self.init(
            databaseFile: home.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb"),
            consent: consent,
            keychain: keychain
        )
    }

    public init(
        databaseFile: URL,
        consent: any AccessConsent = MemoryAccessConsent(),
        keychain: any SafeStorageKeychain = CursorSafeStorageKeychain()
    ) {
        self.databaseFile = databaseFile
        self.consent = consent
        self.keychain = keychain
    }

    // Off the main actor: the database may be busy while Cursor writes to it.
    @concurrent
    public func read() async -> SessionReading {
        guard FileManager.default.fileExists(atPath: databaseFile.path(percentEncoded: false)) else { return .noSession }
        let (token, plan) = stored()
        switch token {
        case .found(let value) where value.hasPrefix(CursorSafeStorage.prefix):
            return decrypting(value, plan: plan)
        case .found(let token) where !token.isEmpty:
            return .session(Session(accessToken: token, accountID: Self.subject(of: token), plan: plan))
        case .found, .missing:
            return .noSession
        case .incompatible:
            return .unknownFormat
        case .busy:
            return .storeBusy
        case .unavailable:
            return .storeUnavailable
        }
    }

    /// Checks the format before asking for anything: a value Uzzy cannot
    /// decrypt is never worth a Keychain prompt.
    private func decrypting(_ value: String, plan: String?) -> SessionReading {
        guard let ciphertext = CursorSafeStorage.ciphertext(of: value) else { return .unknownFormat }
        guard consent.isGranted() else { return .needsAccess }
        switch keychain.password() {
        case .found(var password):
            defer { CursorSafeStorage.wipe(&password) }
            guard let token = CursorSafeStorage.token(decrypting: ciphertext, password: password) else {
                return .unknownFormat
            }
            return .session(Session(accessToken: token, accountID: Self.subject(of: token), plan: plan))
        case .denied:
            return .accessDenied
        case .notFound, .unavailable:
            return .storeUnavailable
        }
    }

    private enum StoredValue {
        case found(String)
        case missing
        case incompatible
        case busy
        case unavailable
    }

    /// The access token, and the plan when there is one to read.
    private func stored() -> (token: StoredValue, plan: String?) {
        var database: OpaquePointer?
        defer { sqlite3_close_v2(database) }
        // `mode=ro` on top of the read-only flag: SQLite never writes to the
        // file, and never creates it.
        var address = URLComponents()
        address.scheme = "file"
        address.path = databaseFile.path(percentEncoded: false)
        address.queryItems = [URLQueryItem(name: "mode", value: "ro")]
        guard let uri = address.string else { return (.unavailable, nil) }
        let openStatus = sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard openStatus == SQLITE_OK else { return (Self.failure(for: openStatus), nil) }
        sqlite3_busy_timeout(database, 2_000)

        let token = Self.value(of: "cursorAuth/accessToken", in: database)
        guard case .found = token else { return (token, nil) }
        // Read on its own: whatever happens to the plan, the session stands.
        guard case .found(let plan) = Self.value(of: "cursorAuth/stripeMembershipType", in: database), !plan.isEmpty
        else { return (token, nil) }
        return (token, plan)
    }

    private static func value(of key: String, in database: OpaquePointer?) -> StoredValue {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let prepareStatus = sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = ?", -1, &statement, nil)
        guard prepareStatus == SQLITE_OK else {
            // A missing ItemTable means Cursor's storage no longer has the
            // expected schema. Other failures may be temporary.
            return prepareStatus == SQLITE_ERROR ? .incompatible : failure(for: prepareStatus)
        }
        // SQLITE_TRANSIENT: SQLite copies the key before the call returns.
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            // The value may be stored as text or as a blob of text.
            guard let bytes = sqlite3_column_blob(statement, 0) else { return .found("") }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
            guard let text = String(data: data, encoding: .utf8) else { return .incompatible }
            return .found(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case SQLITE_DONE:
            return .missing
        case let status:
            return failure(for: status)
        }
    }

    private static func failure(for status: Int32) -> StoredValue {
        switch status & 0xff {
        case SQLITE_BUSY, SQLITE_LOCKED: .busy
        case SQLITE_NOTADB, SQLITE_CORRUPT: .incompatible
        default: .unavailable
        }
    }

    /// The `sub` claim of a JWT, without verifying its signature: it only
    /// tells accounts apart. `nil` when it cannot be read, so the identity is
    /// uncertain.
    private static func subject(of token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONDecoder().decode(Claims.self, from: data),
              let subject = claims.sub, !subject.isEmpty
        else { return nil }
        return subject
    }

    private struct Claims: Decodable {
        let sub: String?
    }
}
