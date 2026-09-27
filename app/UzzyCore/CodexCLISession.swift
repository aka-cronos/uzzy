import Foundation

/// Reads, read-only, the ChatGPT session Codex CLI keeps on this Mac in
/// `auth.json`, under `$CODEX_HOME` or `~/.codex`. It keeps only the access
/// token and the account identity, never the refresh token, and never
/// refreshes tokens, writes credentials or launches the Codex app-server.
///
/// Sessions Codex CLI keeps elsewhere (the Keychain, an encrypted or an
/// ephemeral store) have no `auth.json`, so they read as no session.
public struct CodexCLISessionReader: SessionReader {
    private let authFile: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        let codexHome = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory) }
        authFile = (codexHome ?? home.appending(path: ".codex", directoryHint: .isDirectory)).appending(path: "auth.json")
    }

    public func read() async -> SessionReading {
        let data: Data
        do {
            data = try Data(contentsOf: authFile)
        } catch CocoaError.fileReadNoSuchFile {
            return .noSession
        } catch {
            return .unknownFormat
        }
        return Self.session(from: data)
    }

    /// Decodes only the mode, the access token and the account; the rest of
    /// the file is discarded.
    private static func session(from data: Data) -> SessionReading {
        guard let stored = try? JSONDecoder().decode(StoredAuth.self, from: data) else { return .unknownFormat }
        switch stored.auth_mode {
        case "chatgpt":
            guard let token = stored.tokens?.access_token, !token.isEmpty else { return .noSession }
            // The query names the account, so the provider never picks one.
            // Without it the session is not one this reader knows.
            guard let accountID = stored.tokens?.account_id, !accountID.isEmpty else { return .unknownFormat }
            return .session(Session(accessToken: token, accountID: accountID))
        // Without its mode, the session cannot be told to be a ChatGPT one.
        case nil:
            return .unknownFormat
        // An API key or another mode: no ChatGPT subscription behind it.
        default:
            return .withoutSubscriptionQuotas
        }
    }

    private struct StoredAuth: Decodable {
        let auth_mode: String?
        let tokens: Tokens?

        struct Tokens: Decodable {
            let access_token: String?
            let account_id: String?
        }
    }
}
