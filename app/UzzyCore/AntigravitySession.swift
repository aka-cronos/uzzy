import Darwin
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
/// Builds such as Antigravity Insiders (`~/.gemini/antigravity-insiders`) do
/// not update that Keychain item while they run. When the Keychain item is
/// missing, has no access token, or holds an expired token, this reader falls
/// back to a live local daemon discovery file (`hub_*.json`) under
/// `~/.gemini/antigravity-insiders/daemon/` or `~/.gemini/antigravity/daemon/`.
///
/// Reading the Keychain could show the system access prompt, so this must
/// only run after a user action (opening the panel or pressing Actualizar).
public struct AntigravitySessionReader: SessionReader {
    private let securityTool: URL
    private let daemonDirectories: [URL]

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        securityTool: URL = URL(filePath: "/usr/bin/security")
    ) {
        self.securityTool = securityTool
        daemonDirectories = [
            home.appending(path: ".gemini/antigravity-insiders/daemon", directoryHint: .isDirectory),
            home.appending(path: ".gemini/antigravity/daemon", directoryHint: .isDirectory),
        ]
    }

    // Off the main actor: the tool blocks while a prompt is shown.
    @concurrent
    public func read() async -> SessionReading {
        let item: Data
        switch KeychainItem.read(service: "gemini", account: "antigravity", with: securityTool) {
        case .found(let data): item = data
        case .notFound:
            if let daemon = localDaemonSession() { return .session(daemon) }
            return .noSession
        case .denied: return .accessDenied
        case .failed: return .storeUnavailable
        }
        guard let json = Self.json(in: item),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: json)
        else { return .unknownFormat }
        let email = stored.id_token_email.flatMap { $0.isEmpty ? nil : $0 }
        guard let token = stored.token?.access_token, !token.isEmpty else {
            if let daemon = localDaemonSession() { return .session(daemon) }
            return .noSession
        }
        let isExpired = stored.token?.expiryDate.map { $0 <= Date() } ?? false
        if isExpired, let daemon = localDaemonSession() {
            return .session(daemon)
        }
        return .session(Session(accessToken: token, accountID: email))
    }

    /// Reads the newest live local daemon discovery file (`hub_*.json`),
    /// preferring Antigravity Insiders over stable Antigravity.
    private func localDaemonSession() -> Session? {
        for directory in daemonDirectories {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let candidates = urls
                .filter {
                    let name = $0.lastPathComponent
                    return name.hasPrefix("hub_") && name.hasSuffix(".json")
                }
                .sorted { lhs, rhs in
                    let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    if leftDate != rightDate { return leftDate > rightDate }
                    return lhs.lastPathComponent > rhs.lastPathComponent
                }
            for url in candidates {
                guard let data = try? Data(contentsOf: url),
                      let discovery = try? JSONDecoder().decode(DaemonDiscovery.self, from: data),
                      let pid = discovery.pid, Self.processIsAlive(pid),
                      let port = discovery.httpPort, (1...65535).contains(port),
                      let csrf = discovery.csrfToken, !csrf.isEmpty,
                      let endpoint = URL(string: "http://127.0.0.1:\(port)")
                else { continue }
                return Session(accessToken: csrf, accountID: nil, localEndpoint: endpoint)
            }
        }
        return nil
    }

    private static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    private static let encodedPrefix = "go-keyring-base64:"

    /// The item's JSON, decoded from base64 when Antigravity encoded it.
    private static func json(in item: Data) -> Data? {
        let text = String(decoding: item, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(encodedPrefix) else { return Data(text.utf8) }
        return Data(base64Encoded: String(text.dropFirst(encodedPrefix.count)))
    }

    private struct DaemonDiscovery: Decodable {
        let pid: Int32?
        let httpPort: Int?
        let csrfToken: String?

        private enum CodingKeys: String, CodingKey {
            case pid, httpPort, csrfToken
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            pid = (try? values.decodeIfPresent(Int32.self, forKey: .pid)).flatMap { $0 }
            httpPort = (try? values.decodeIfPresent(Int.self, forKey: .httpPort)).flatMap { $0 }
            csrfToken = (try? values.decodeIfPresent(String.self, forKey: .csrfToken)).flatMap { $0 }
        }
    }

    /// Decodes only the access token, expiry and email; the rest of the item is
    /// discarded. A field of another shape gives no value, and never loses
    /// the rest.
    private struct StoredCredentials: Decodable {
        let id_token_email: String?
        let token: Token?

        struct Token: Decodable {
            let access_token: String?
            let expiry: String?

            var expiryDate: Date? {
                guard let expiry else { return nil }
                return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(expiry))
                    ?? (try? Date.ISO8601FormatStyle().parse(expiry))
            }

            private enum CodingKeys: String, CodingKey {
                case access_token, expiry
            }

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                access_token = (try? values.decodeIfPresent(String.self, forKey: .access_token)).flatMap { $0 }
                expiry = (try? values.decodeIfPresent(String.self, forKey: .expiry)).flatMap { $0 }
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
