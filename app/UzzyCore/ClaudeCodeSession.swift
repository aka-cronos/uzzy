import Foundation

/// Reads, read-only, the session Claude Code keeps on this Mac: the access
/// token and the plan from the Keychain, and the account identity from
/// `~/.claude.json`. It keeps only the access token and the plan, never the
/// refresh token, and never refreshes tokens or writes credentials. It never
/// falls back on another source, such as a `.credentials.json` file, when
/// the Keychain has no usable session.
///
/// It reads the Keychain item through `/usr/bin/security`, which Claude Code
/// uses to write it: the item trusts that tool, so the read shows no prompt.
/// Read directly, the item would ask for the keychain password again after
/// every token refresh, because Claude Code's rewrite resets the item's
/// partition list to the tool alone.
///
/// Reading the Keychain could still show the system access prompt if the
/// item stopped trusting the tool, so this must only run after a user action
/// (opening the panel or pressing Actualizar).
public struct ClaudeCodeSessionReader: SessionReader {
    private let keychainService = "Claude Code-credentials"
    private let configFile: URL
    private let securityTool: URL

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        securityTool: URL = URL(filePath: "/usr/bin/security")
    ) {
        configFile = home.appending(path: ".claude.json")
        self.securityTool = securityTool
    }

    // Off the main actor: the tool blocks while a prompt is shown.
    @concurrent
    public func read() async -> SessionReading {
        let credentials: Data
        switch keychainItem() {
        case .found(let data): credentials = data
        case .notFound: return .noSession
        case .denied: return .accessDenied
        case .failed: return .storeUnavailable
        }
        // Decodes only the access token and the plan; the rest of the item
        // is discarded.
        guard let stored = try? JSONDecoder().decode(StoredCredentials.self, from: credentials) else {
            return .unknownFormat
        }
        guard let oauth = stored.claudeAiOauth, let token = oauth.accessToken, !token.isEmpty else { return .noSession }
        return .session(Session(accessToken: token, accountID: accountID(), plan: oauth.subscriptionType))
    }

    private enum KeychainItem {
        case found(Data)
        case notFound
        case denied
        case failed
    }

    /// `security` exits with the low byte of the Keychain error it got.
    private enum ExitStatus {
        static let itemNotFound: Int32 = 44 // errSecItemNotFound
        static let authFailed: Int32 = 51 // errSecAuthFailed
        static let userCanceled: Int32 = 128 // errSecUserCanceled
    }

    private func keychainItem() -> KeychainItem {
        let tool = Process()
        tool.executableURL = securityTool
        tool.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        tool.standardOutput = output
        tool.standardError = FileHandle.nullDevice
        do {
            try tool.run()
        } catch {
            return .failed
        }
        // Reads before waiting, so a full pipe never blocks the tool.
        let data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
        tool.waitUntilExit()
        guard tool.terminationReason == .exit else { return .failed }
        switch tool.terminationStatus {
        case 0: return .found(data)
        case ExitStatus.itemNotFound: return .notFound
        // The user denied the prompt. If the prompt could not be shown, the
        // Keychain is unavailable rather than denied or malformed.
        case ExitStatus.userCanceled, ExitStatus.authFailed: return .denied
        default: return .failed
        }
    }

    /// `nil` when the identity cannot be verified: missing file, field or format.
    private func accountID() -> String? {
        guard let data = try? Data(contentsOf: configFile),
              let config = try? JSONDecoder().decode(ClaudeConfig.self, from: data),
              let id = config.oauthAccount?.accountUuid, !id.isEmpty
        else { return nil }
        return id
    }

    private struct StoredCredentials: Decodable {
        let claudeAiOauth: OAuth?

        struct OAuth: Decodable {
            let accessToken: String?
            /// The plan, e.g. `"max"`. Read leniently: a value that is not
            /// text gives no plan, and never loses the session.
            let subscriptionType: String?

            private enum CodingKeys: String, CodingKey {
                case accessToken, subscriptionType
            }

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                accessToken = try values.decodeIfPresent(String.self, forKey: .accessToken)
                subscriptionType = (try? values.decodeIfPresent(String.self, forKey: .subscriptionType)).flatMap { $0 }
            }
        }
    }

    private struct ClaudeConfig: Decodable {
        let oauthAccount: Account?

        struct Account: Decodable {
            let accountUuid: String?
        }
    }
}
