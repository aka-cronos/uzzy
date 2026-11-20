import Foundation

/// Antigravity adapter: asks Google's Cloud Code service for the account,
/// which names its plan and project, then for that project's quota summary,
/// and translates each model group's limits into quotas.
enum Antigravity: ProviderAdapter {
    static let provider = Provider.antigravity

    /// Antigravity renews its token only while it runs, so the session is
    /// often expired; reading it through `security` shows no prompt.
    static let rereadsRejectedSession = true

    /// Cloud Code leaves the plan out and refuses the quota summary (403)
    /// unless the client presents itself as Antigravity, and leaves out the
    /// groups a plan keeps apart (Gemini 4 Argon on Google AI Pro) unless it
    /// presents itself as Antigravity's app, the "hub".
    static let userAgent = "antigravity/hub/2.33.0 darwin/arm64"

    /// The account query: its plan and the project its quotas belong to.
    static func request(for session: Session) -> URLRequest {
        cloudCodeRequest(
            "loadCodeAssist",
            session: session,
            body: Data(#"{"metadata":{"ideType":"ANTIGRAVITY","platform":"PLATFORM_UNSPECIFIED","pluginType":"GEMINI"}}"#.utf8)
        )
    }

    /// The quota summary of the account's project. Without the project the
    /// summary leaves out the groups a plan keeps apart, e.g. Gemini 4 Argon
    /// on Google AI Pro, so it is only asked without one when the account
    /// names none.
    static func metadataRequest(for session: Session, after response: Data) -> URLRequest? {
        let project = (try? JSONDecoder().decode(Account.self, from: response))?.cloudaicompanionProject
        let body = (try? JSONEncoder().encode(project.map { ["project": $0] } ?? [:])) ?? Data("{}".utf8)
        return cloudCodeRequest("retrieveUserQuotaSummary", session: session, body: body)
    }

    /// One quota per group and window, in the summary's group order, each
    /// group's 5-hour limit before its weekly one. Buckets of a window
    /// Uzzy does not know are left out; a summary without any known one is
    /// not understood.
    static func quotas(from body: Data, metadata: Data?, readAt moment: Date) -> Result<[QuotaReading], Failure> {
        guard let metadata, let summary = try? JSONDecoder().decode(Summary.self, from: metadata) else {
            return .failure(.incompatibleResponse)
        }
        var periods: [QuotaPeriod] = []
        var copies: [QuotaPeriod: [Bucket]] = [:]
        for group in summary.groups ?? [] {
            guard let name = name(of: group) else { continue }
            let buckets = (group.buckets ?? []).compactMap { bucket in
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
                startsOnFirstUse: true
            )
        })
    }

    /// The paid tier of the account query, by Google's name. The current
    /// tier is generic («Antigravity») and names no plan.
    static func plan(of session: Session, response body: Data) -> String? {
        (try? JSONDecoder().decode(Account.self, from: body))?.paidTier?.id.flatMap { planNames[$0] }
    }

    /// Every paid tier Uzzy knows. Any other value shows no plan.
    private static let planNames = ["g1-pro-tier": "Google AI Pro"]

    /// The groups Antigravity's own quota screen shows go by a short name;
    /// any other group by the name the summary gives it.
    private static func name(of group: Group) -> String? {
        let ids = Set((group.buckets ?? []).compactMap(\.bucketId))
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
        var request = URLRequest(url: URL(string: "https://daily-cloudcode-pa.sandbox.googleapis.com/v1internal:\(method)")!)
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

        struct Tier: Decodable {
            let id: String?
        }

        private enum CodingKeys: String, CodingKey {
            case cloudaicompanionProject, paidTier
        }

        /// Read leniently: a field of another shape is left out, and never
        /// loses the quotas.
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            cloudaicompanionProject = (try? values.decodeIfPresent(String.self, forKey: .cloudaicompanionProject))
                .flatMap { $0 }.flatMap { $0.isEmpty ? nil : $0 }
            paidTier = (try? values.decodeIfPresent(Tier.self, forKey: .paidTier)).flatMap { $0 }
        }
    }

    private struct Summary: Decodable {
        let groups: [Group]?
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
