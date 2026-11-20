import Foundation

/// Reads, read-only, the session Antigravity keeps on this Mac: the Google
/// access token in the Keychain item it writes (service `gemini`, account
/// `antigravity`), shared by the app and the `agy` CLI. The account identity
/// is the email the item names. It keeps only the access token and that
/// email, never the refresh token, and never refreshes tokens or writes
/// credentials: Antigravity renews the token while it runs.
///
/// Antigravity writes the item as `go-keyring-base64:` followed by the
/// base64 of its JSON; plain JSON is read too.
///
/// Reading the Keychain could show the system access prompt, so this must
/// only run after a user action (opening the panel or pressing Actualizar).
public struct AntigravitySessionReader: SessionReader {
    private let securityTool: URL

    public init(securityTool: URL = URL(filePath: "/usr/bin/security")) {
        self.securityTool = securityTool
    }

    // Off the main actor: the tool blocks while a prompt is shown.
    @concurrent
    public func read() async -> SessionReading {
        let item: Data
        switch KeychainItem.read(service: "gemini", account: "antigravity", with: securityTool) {
        case .found(let data): item = data
        case .notFound: return .noSession
        case .denied: return .accessDenied
        case .failed: return .storeUnavailable
        }
        guard let json = Self.json(in: item),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: json)
        else { return .unknownFormat }
        guard let token = stored.token?.access_token, !token.isEmpty else { return .noSession }
        let email = stored.id_token_email.flatMap { $0.isEmpty ? nil : $0 }
        return .session(Session(accessToken: token, accountID: email))
    }

    private static let encodedPrefix = "go-keyring-base64:"

    /// The item's JSON, decoded from base64 when Antigravity encoded it.
    private static func json(in item: Data) -> Data? {
        let text = String(decoding: item, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(encodedPrefix) else { return Data(text.utf8) }
        return Data(base64Encoded: String(text.dropFirst(encodedPrefix.count)))
    }

    /// Decodes only the access token and the email; the rest of the item is
    /// discarded. A field of another shape gives no value, and never loses
    /// the rest.
    private struct StoredCredentials: Decodable {
        let id_token_email: String?
        let token: Token?

        struct Token: Decodable {
            let access_token: String?

            private enum CodingKeys: String, CodingKey {
                case access_token
            }

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                access_token = (try? values.decodeIfPresent(String.self, forKey: .access_token)).flatMap { $0 }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case id_token_email, token
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id_token_email = (try? values.decodeIfPresent(String.self, forKey: .id_token_email)).flatMap { $0 }
            token = (try? values.decodeIfPresent(Token.self, forKey: .token)).flatMap { $0 }
        }
    }
}
