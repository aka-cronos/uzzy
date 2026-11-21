import Darwin
import Foundation

/// Reads, read-only, an Antigravity session on this Mac, in order:
///
/// 1. The Keychain item Antigravity writes (service `gemini`, account
///    `antigravity`), shared by the app and the `agy` CLI, whenever its token
///    is still fresh (or carries no expiry).
/// 2. T3 Code's Antigravity token files under
///    `~/.t3/userdata/providers/antigravity/<profile>/antigravity-acp/antigravity-oauth-token`,
///    picking the one whose `expiry` is latest and still ahead of the margin.
/// 3. A running Antigravity app's local service (stable or Insiders),
///    discovered from `~/.gemini/antigravity/daemon/hub_*.json` or
///    `~/.gemini/antigravity-insiders/daemon/hub_*.json` and probed over
///    `127.0.0.1` with its local CSRF token.
///
/// It decodes only `access_token`, `expiry` and `id_token_email` (never the
/// refresh token), and never refreshes tokens or writes credentials. When no
/// source has a fresh session, it returns an expired token session if one
/// exists so Cloud Code rejects it and the card keeps its stale readings while
/// watching for renewal.
///
/// Reading the Keychain could show the system access prompt, so this must
/// only run after a user action (opening the panel or pressing Actualizar).
public struct AntigravitySessionReader: SessionReader {
    private let securityTool: URL
    private let home: URL
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private let isAlive: @Sendable (Int32) -> Bool

    /// Margin before `expiry` within which a token is treated as expired, so
    /// it does not expire between the account and quota queries.
    static let freshnessMargin: TimeInterval = 60

    private static let encodedPrefix = "go-keyring-base64:"
    private static let maxTokenFileBytes = 64 * 1024
    private static let maxHubFileBytes = 16 * 1024
    /// Go's zero time (`0001-01-01T00:00:00Z`) in any timezone offset falls
    /// before `0001-01-02T00:00:00Z`.
    private static let goZeroTimeCutoff: TimeInterval = -62_135_510_400

    public init(
        securityTool: URL = URL(filePath: "/usr/bin/security"),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        isAlive: @escaping @Sendable (Int32) -> Bool = { $0 > 1 && kill($0, 0) == 0 }
    ) {
        self.securityTool = securityTool
        self.home = home
        self.transport = transport
        self.now = now
        self.isAlive = isAlive
    }

    // Off the main actor: `security` blocks while a prompt is shown, and
    // fallback discovery reads local files and may probe loopback.
    @concurrent
    public func read() async -> SessionReading {
        let cutoff = now().addingTimeInterval(Self.freshnessMargin)
        let keychain = readKeychain(cutoff: cutoff)
        switch keychain {
        case .fresh(let session):
            return .session(session)
        case .error(.accessDenied):
            // The user denied the Keychain prompt; stop here so the card enters
            // `.sessionAccessDenied` and never prompts again until Refresh.
            return .accessDenied
        case .expired, .noSession, .error:
            break
        }

        let files = readTokenFiles(cutoff: cutoff)
        if let fresh = files.freshest {
            return .session(fresh.session)
        }

        if let daemon = await probeDaemons() {
            return .session(daemon)
        }

        switch keychain {
        case .fresh(let session), .expired(let session):
            return .session(session)
        case .error(let failure):
            return failure
        case .noSession:
            if let expired = files.latestExpired {
                return .session(expired.session)
            }
            return .noSession
        }
    }

    // MARK: Source 1 — Keychain

    private enum KeychainOutcome {
        case fresh(Session)
        case expired(Session)
        case noSession
        case error(SessionReading)
    }

    private func readKeychain(cutoff: Date) -> KeychainOutcome {
        let item: Data
        switch KeychainItem.read(service: "gemini", account: "antigravity", with: securityTool) {
        case .found(let data): item = data
        case .notFound: return .noSession
        case .denied: return .error(.accessDenied)
        case .failed: return .error(.storeUnavailable)
        }
        guard let credentials = Self.parseCredentials(in: item) else { return .error(.unknownFormat) }
        guard let token = credentials.accessToken else { return .noSession }
        let session = Session(accessToken: token, accountID: credentials.email)
        if let expiry = credentials.expiry, expiry <= cutoff {
            return .expired(session)
        }
        return .fresh(session)
    }

    // MARK: Source 2 — Other clients' token files

    private struct TimedSession {
        let session: Session
        let expiry: Date
        let path: String
    }

    private func readTokenFiles(cutoff: Date) -> (freshest: TimedSession?, latestExpired: TimedSession?) {
        let root = home
            .appending(path: ".t3", directoryHint: .isDirectory)
            .appending(path: "userdata", directoryHint: .isDirectory)
            .appending(path: "providers", directoryHint: .isDirectory)
            .appending(path: "antigravity", directoryHint: .isDirectory)
        let manager = FileManager.default
        guard let profiles = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (nil, nil)
        }

        var freshest: TimedSession?
        var latestExpired: TimedSession?
        for profile in profiles {
            guard let values = try? profile.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true,
                  values.isDirectory == true
            else { continue }

            let tokenFile = profile
                .appending(path: "antigravity-acp", directoryHint: .isDirectory)
                .appending(path: "antigravity-oauth-token")
            guard let data = Self.readRegularFile(at: tokenFile, maxBytes: Self.maxTokenFileBytes),
                  let credentials = Self.parseCredentials(in: data),
                  let token = credentials.accessToken,
                  let expiry = credentials.expiry
            else { continue }

            let candidate = TimedSession(
                session: Session(accessToken: token, accountID: credentials.email),
                expiry: expiry,
                path: tokenFile.path
            )
            if expiry > cutoff {
                if Self.isNewer(candidate, than: freshest) { freshest = candidate }
            } else {
                if Self.isNewer(candidate, than: latestExpired) { latestExpired = candidate }
            }
        }
        return (freshest, latestExpired)
    }

    private static func isNewer(_ candidate: TimedSession, than current: TimedSession?) -> Bool {
        guard let current else { return true }
        if candidate.expiry != current.expiry { return candidate.expiry > current.expiry }
        return candidate.path < current.path
    }

    // MARK: Source 3 — Local daemon

    private struct HubCandidate {
        let url: URL
        let modifiedAt: Date
    }

    private struct HubInfo: Decodable {
        let pid: Int32
        let httpPort: Int
        let csrfToken: String
    }

    private func probeDaemons() async -> Session? {
        let candidates = discoverHubFiles()
        for candidate in candidates {
            guard let data = Self.readRegularFile(at: candidate.url, maxBytes: Self.maxHubFileBytes),
                  let hub = try? JSONDecoder().decode(HubInfo.self, from: data),
                  hub.pid > 1,
                  isAlive(hub.pid),
                  (1...65_535).contains(hub.httpPort),
                  !hub.csrfToken.isEmpty,
                  let endpoint = URL(string: "http://127.0.0.1:\(hub.httpPort)")
            else { continue }

            // Intentionally probes `GetUserStatus` before `Antigravity.request(for:)`
            // calls it again: probing verifies the port is live and retrieves
            // the account email so per-account stale retention works from the
            // first read.
            let probe = Antigravity.daemonRequest("GetUserStatus", endpoint: endpoint, csrfToken: hub.csrfToken)
            let result = await transport.send(probe)
            guard case .response(let response) = result,
                  response.status == 200,
                  let status = Antigravity.daemonUserStatus(from: response.body)
            else { continue }

            return Session(accessToken: hub.csrfToken, accountID: status.email, endpoint: endpoint)
        }
        return nil
    }

    private func discoverHubFiles() -> [HubCandidate] {
        let gemini = home.appending(path: ".gemini", directoryHint: .isDirectory)
        let directories = [
            gemini.appending(path: "antigravity/daemon", directoryHint: .isDirectory),
            gemini.appending(path: "antigravity-insiders/daemon", directoryHint: .isDirectory),
        ]
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        var candidates: [HubCandidate] = []
        for directory in directories {
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in entries {
                let name = url.lastPathComponent
                guard name.hasPrefix("hub_"), name.hasSuffix(".json"),
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isSymbolicLink != true,
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) <= Self.maxHubFileBytes
                else { continue }
                candidates.append(HubCandidate(url: url, modifiedAt: values.contentModificationDate ?? .distantPast))
            }
        }
        return candidates.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            return lhs.url.path < rhs.url.path
        }
    }

    // MARK: Shared parsing

    /// Opens `url` without following a symlink on the final path component,
    /// requires a regular file, and reads at most `maxBytes`.
    private static func readRegularFile(at url: URL, maxBytes: Int) -> Data? {
        let path = url.path(percentEncoded: false)
        let fd = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var info = stat()
        guard fstat(fd, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0,
              info.st_size <= maxBytes
        else { return nil }

        var data = Data()
        data.reserveCapacity(Int(info.st_size))
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if data.count + count > maxBytes { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
    }

    private struct ParsedCredentials {
        let accessToken: String?
        let email: String?
        let expiry: Date?
    }

    private static func parseCredentials(in item: Data) -> ParsedCredentials? {
        guard let json = json(in: item),
              let stored = try? JSONDecoder().decode(StoredCredentials.self, from: json)
        else { return nil }
        let token = stored.token?.access_token.flatMap { $0.isEmpty ? nil : $0 }
        let email = Antigravity.normalizeEmail(stored.id_token_email)
        let expiry = parseExpiry(stored.token?.expiry)
        return ParsedCredentials(accessToken: token, email: email, expiry: expiry)
    }

    /// The item's JSON, decoded from base64 when Antigravity encoded it.
    private static func json(in item: Data) -> Data? {
        let text = String(decoding: item, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(encodedPrefix) else { return Data(text.utf8) }
        return Data(base64Encoded: String(text.dropFirst(encodedPrefix.count)))
    }

    /// Parses Go RFC 3339 timestamps (including up to 9 fractional digits and
    /// timezone offsets). Missing, unparseable or Go zero-time values return
    /// `nil`.
    private static func parseExpiry(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parsed = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? normalizeFractionalSeconds(in: text).flatMap {
                try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse($0)
            }
            ?? (try? Date.ISO8601FormatStyle().parse(text))
        guard let parsed, parsed.timeIntervalSince1970 > goZeroTimeCutoff else { return nil }
        return parsed
    }

    /// Truncates or pads fractional seconds to 3 digits so `ISO8601FormatStyle`
    /// accepts Go's nanosecond RFC 3339 timestamps.
    private static func normalizeFractionalSeconds(in text: String) -> String? {
        guard let tIndex = text.firstIndex(where: { $0 == "T" || $0 == "t" }),
              let dotIndex = text[tIndex...].firstIndex(of: ".")
        else { return nil }
        let fractionStart = text.index(after: dotIndex)
        var fractionEnd = fractionStart
        while fractionEnd < text.endIndex, text[fractionEnd].isASCII, text[fractionEnd].isNumber {
            fractionEnd = text.index(after: fractionEnd)
        }
        guard fractionEnd > fractionStart else { return nil }
        let digits = text[fractionStart..<fractionEnd]
        let threeDigits: String
        if digits.count >= 3 {
            threeDigits = String(digits.prefix(3))
        } else {
            threeDigits = digits + String(repeating: "0", count: 3 - digits.count)
        }
        return String(text[..<fractionStart]) + threeDigits + String(text[fractionEnd...])
    }

    /// Decodes only the access token, expiry and email; the rest of the item
    /// (including `refresh_token`) is discarded. A field of another shape
    /// gives no value, and never loses the rest.
    private struct StoredCredentials: Decodable {
        let id_token_email: String?
        let token: Token?

        struct Token: Decodable {
            let access_token: String?
            let expiry: String?

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
