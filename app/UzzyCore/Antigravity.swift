import Foundation

/// Antigravity adapter: asks Google's Cloud Code service—or, when the session
/// points at a running Antigravity app on loopback, its local service—for the
/// account, which names its plan and project, then for its quota summary, and
/// translates each model group's limits into quotas.
enum Antigravity: ProviderAdapter {
    static let provider = Provider.antigravity

    /// Antigravity renews its token only while it runs, so the session is
    /// often expired; reading it through `security` shows no prompt.
    static let rereadsRejectedSession = true

    /// Antigravity's local service caches its quota summary for several
    /// minutes, so an untouched window's moving reset can lag behind `now +
    /// window` past the shared 5-minute margin. Applies to both Cloud Code
    /// and local-service readings.
    static let unstartedWindowAgreement: TimeInterval = 15 * 60

    /// Cloud Code leaves the plan out and refuses the quota summary (403)
    /// unless the client presents itself as Antigravity, and leaves out the
    /// groups a plan keeps apart (Gemini 4 Argon on Google AI Pro) unless it
    /// presents itself as Antigravity's app, the "hub".
    static let userAgent = "antigravity/hub/2.33.0 darwin/arm64"

    /// A local service that stopped answering means the app closed and that
    /// session is gone, not that the Mac is offline.
    static func failure(whenUnreachable session: Session) -> Failure? {
        session.endpoint != nil ? .sessionExpired : nil
    }

    /// The account query: its plan and, on Cloud Code, the project its quotas
    /// belong to.
    static func request(for session: Session) -> URLRequest {
        if let endpoint = session.endpoint {
            return daemonRequest("GetUserStatus", endpoint: endpoint, csrfToken: session.accessToken)
        }
        return cloudCodeRequest(
            "loadCodeAssist",
            session: session,
            body: Data(#"{"metadata":{"ideType":"ANTIGRAVITY","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}"#.utf8)
        )
    }

    /// The quota summary of the account's project. Without the project the
    /// Cloud Code summary leaves out the groups a plan keeps apart, e.g.
    /// Gemini 4 Argon on Google AI Pro, so it is only asked without one when
    /// the account names none.
    static func metadataRequest(for session: Session, after response: Data) -> URLRequest? {
        if let endpoint = session.endpoint {
            return daemonRequest("RetrieveUserQuotaSummary", endpoint: endpoint, csrfToken: session.accessToken)
        }
        let project = (try? JSONDecoder().decode(Account.self, from: response))?.cloudaicompanionProject
        let body = (try? JSONEncoder().encode(project.map { ["project": $0] } ?? [:])) ?? Data("{}".utf8)
        return cloudCodeRequest("retrieveUserQuotaSummary", session: session, body: body)
    }

    /// A Connect JSON request to a running Antigravity daemon on loopback.
    /// Sends only the daemon's local CSRF token and never a Google token.
    static func daemonRequest(_ method: String, endpoint: URL, csrfToken: String) -> URLRequest {
        var request = URLRequest(url: endpoint.appending(path: "exa.language_server_pb.LanguageServerService/\(method)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)
        return request
    }

    /// The signed-in status reported by a local daemon's `GetUserStatus`.
    struct DaemonUserStatus: Sendable, Equatable {
        /// Normalized email when present; `nil` leaves the identity uncertain.
        let email: String?
    }

    /// Decodes a local daemon's `GetUserStatus` payload; `nil` when the
    /// response has no `userStatus` object.
    static func daemonUserStatus(from body: Data) -> DaemonUserStatus? {
        guard let account = try? JSONDecoder().decode(Account.self, from: body),
              let status = account.userStatus
        else { return nil }
        return DaemonUserStatus(email: normalizeEmail(status.email))
    }

    static func normalizeEmail(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// One quota per group and window, in the summary's group order, each
    /// group's 5-hour limit before its weekly one. Disabled buckets and
    /// buckets of a window Uzzy does not know are left out; a summary
    /// without any known one is not understood.
    static func quotas(from body: Data, metadata: Data?, readAt moment: Date) -> Result<[QuotaReading], Failure> {
        guard let metadata, let summary = try? JSONDecoder().decode(Summary.self, from: metadata) else {
            return .failure(.incompatibleResponse)
        }
        var periods: [QuotaPeriod] = []
        var copies: [QuotaPeriod: [Bucket]] = [:]
        for group in summary.resolvedGroups ?? [] {
            // A plan may list limits it turns off; a group left with none
            // shows nothing.
            let active = (group.buckets ?? []).filter { !$0.disabled }
            guard let name = name(of: group, buckets: active) else { continue }
            let buckets = active.compactMap { bucket in
                window(bucket.window).map { (window: $0, bucket: bucket) }
            }
            for window in [QuotaPeriod.fiveHours, .weekly] {
                for entry in buckets where entry.window == window {
                    let period = QuotaPeriod.limit(name, window)
                    if copies[period] == nil { periods.append(period) }
                    copies[period, default: []].append(entry.bucket)
                }
            }
        }
        guard !periods.isEmpty else { return .failure(.incompatibleResponse) }
        return .success(periods.map { period in
            let buckets = copies[period, default: []]
            return QuotaReading(
                period: period,
                usedPercents: buckets.compactMap(\.usedPercent),
                resets: buckets.compactMap { reset($0.resetTime) },
                readAt: moment,
                // An untouched bucket's reset is the reading plus its window.
                startsOnFirstUse: true,
                unstartedWindowAgreement: Self.unstartedWindowAgreement
            )
        })
    }

    /// The paid tier of the account query (`paidTier.id` on Cloud Code,
    /// `userStatus.userTier.id` on the local service), by Google's name. The
    /// current tier is generic («Antigravity») and names no plan, and
    /// `planStatus.planInfo.planName` reports `"Pro"` on Ultra accounts.
    static func plan(of session: Session, response body: Data) -> String? {
        guard let account = try? JSONDecoder().decode(Account.self, from: body) else { return nil }
        return (account.paidTier?.id ?? account.userStatus?.userTier?.id).flatMap { planNames[$0] }
    }

    /// Every paid tier Uzzy knows. Any other value shows no plan.
    private static let planNames = [
        "g1-pro-tier": "Google AI Pro",
        "g1-ultra-tier": "Google AI Ultra",
    ]

    /// The groups Antigravity's own quota screen shows go by a short name;
    /// any other group by the name the summary gives it.
    private static func name(of group: Group, buckets: [Bucket]) -> String? {
        let ids = Set(buckets.compactMap(\.bucketId))
        if !ids.isDisjoint(with: ["gemini-5h", "gemini-weekly"]) { return "Gemini" }
        if !ids.isDisjoint(with: ["3p-5h", "3p-weekly"]) { return "Claude and GPT" }
        let name = group.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    private static func window(_ window: String?) -> QuotaPeriod? {
        switch window {
        case "5h": .fiveHours
        case "weekly": .weekly
        default: nil
        }
    }

    private static func reset(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    /// Antigravity tracks usage on Cloud Code's daily host; `cloudcode-pa.googleapis.com`
    /// answers with 200 and unused (`remainingFraction: 1`) buckets.
    private static func cloudCodeRequest(_ method: String, session: Session, body: Data) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        return request
    }

    private struct Account: Decodable {
        let cloudaicompanionProject: String?
        let paidTier: Tier?
        let userStatus: UserStatus?

        struct Tier: Decodable {
            let id: String?
        }

        struct UserStatus: Decodable {
            let email: String?
            let userTier: Tier?

            private enum CodingKeys: String, CodingKey {
                case email, userTier
            }

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                email = (try? values.decodeIfPresent(String.self, forKey: .email)).flatMap { $0 }
                userTier = (try? values.decodeIfPresent(Tier.self, forKey: .userTier)).flatMap { $0 }
            }
        }

        private enum CodingKeys: String, CodingKey {
            case cloudaicompanionProject, paidTier, userStatus
        }

        /// Read leniently: a field of another shape is left out, and never
        /// loses the quotas.
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            cloudaicompanionProject = (try? values.decodeIfPresent(String.self, forKey: .cloudaicompanionProject))
                .flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
            paidTier = (try? values.decodeIfPresent(Tier.self, forKey: .paidTier)).flatMap { $0 }
            userStatus = (try? values.decodeIfPresent(UserStatus.self, forKey: .userStatus)).flatMap { $0 }
        }
    }

    private struct Summary: Decodable {
        let groups: [Group]?
        let response: Payload?

        struct Payload: Decodable {
            let groups: [Group]?
        }

        var resolvedGroups: [Group]? {
            groups ?? response?.groups
        }
    }

    private struct Group: Decodable {
        let displayName: String?
        let buckets: [Bucket]?
    }

    private struct Bucket: Decodable {
        let bucketId: String?
        let window: String?
        let resetTime: String?
        let remainingFraction: Double?
        /// A limit the plan turns off. Only `true` turns it off: a value of
        /// another shape is left out, and never loses the summary.
        let disabled: Bool

        private enum CodingKeys: String, CodingKey {
            case bucketId, window, resetTime, remainingFraction, disabled
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            bucketId = try values.decodeIfPresent(String.self, forKey: .bucketId)
            window = try values.decodeIfPresent(String.self, forKey: .window)
            resetTime = try values.decodeIfPresent(String.self, forKey: .resetTime)
            remainingFraction = try values.decodeIfPresent(Double.self, forKey: .remainingFraction)
            disabled = (try? values.decodeIfPresent(Bool.self, forKey: .disabled)) == true
        }

        /// The used share, as a percentage to two decimals so a fraction such
        /// as 0.96 reads 4%. Nil when the summary leaves the fraction out:
        /// never taken as zero.
        var usedPercent: Double? {
            guard let remainingFraction else { return nil }
            let used = (1 - remainingFraction) * 100
            return used.isFinite ? (used * 100).rounded() / 100 : used
        }
    }
}
