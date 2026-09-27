import Foundation

/// Claude adapter: builds the usage query and translates its response into
/// normalized quotas.
enum Claude: ProviderAdapter {
    static let provider = Provider.claude

    static func request(for session: Session) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Returns an error when the response does not have the expected format.
    ///
    /// `limits[]` repeats the windows (`session`, `weekly_all`) and carries the
    /// per-model limits (`weekly_scoped`), so a quota can arrive more than once.
    /// Every copy goes into the reading, which decides whether they agree.
    /// `extra_usage` adds the usage credits spent after them; nothing else in
    /// the response about spend or amounts is read.
    static func quotas(from body: Data, readAt moment: Date) -> Result<[QuotaReading], Failure> {
        guard let response = try? JSONDecoder().decode(Response.self, from: body) else { return .failure(.incompatibleResponse) }
        let limits = response.limits ?? []
        // One pass groups the entries, so reading each quota does not scan
        // `limits[]` again.
        var entries: [Limit.Key: [Window]] = [:]
        for limit in limits {
            entries[limit.key, default: []].append(limit.window)
        }
        func copies(_ window: Window?, kind: String, model: String? = nil) -> [Window] {
            [window].compactMap { $0 } + entries[Limit.Key(kind: kind, model: model), default: []]
        }

        // A missing window is still a quota: it shows as unavailable.
        let base = [
            reading(.fiveHours, copies(response.five_hour, kind: "session"), at: moment),
            reading(.weekly, copies(response.seven_day, kind: "weekly_all"), at: moment),
        ]
        // Per-model limits only count when sent explicitly and with data.
        let legacy = ["Sonnet": response.seven_day_sonnet, "Opus": response.seven_day_opus]
        let models = ["Sonnet", "Opus"] + limits.compactMap { $0.kind == "weekly_scoped" ? $0.scope?.model?.display_name : nil }
        let perModel = models.uniqued().compactMap { model in
            let windows = copies(legacy[model] ?? nil, kind: "weekly_scoped", model: model)
            return windows.contains { $0.utilization != nil } ? reading(.limit(model, .weekly), windows, at: moment) : nil
        }
        var quotas = base + perModel
        if let extraUsage = response.extra_usage, let spent = extraUsage.spent {
            quotas.append(QuotaReading(usageCreditsSpent: spent, limit: extraUsage.limit, readAt: moment))
        }
        return .success(quotas)
    }

    /// The plan Claude Code keeps with the session (`subscriptionType`), by
    /// Claude's name. The response names no plan.
    static func plan(of session: Session, response body: Data) -> String? {
        session.plan.flatMap { planNames[$0] }
    }

    /// Every `subscriptionType` Uzzy knows. Any other value shows no plan.
    private static let planNames = ["pro": "Pro", "max": "Max", "team": "Team", "enterprise": "Enterprise"]

    private static func reading(_ period: QuotaPeriod, _ windows: [Window], at moment: Date) -> QuotaReading {
        QuotaReading(
            period: period,
            usedPercents: windows.compactMap(\.utilization),
            resets: windows.compactMap { reset($0.resets_at) },
            readAt: moment
        )
    }

    private static func reset(_ text: String?) -> Date? {
        guard let text else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    private struct Response: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_sonnet: Window?
        let seven_day_opus: Window?
        let limits: [Limit]?
        let extra_usage: ExtraUsage?
    }

    /// `extra_usage`, the usage-credit meter. It is read leniently: no value
    /// in it can make the response incompatible. `utilization` is never read.
    private struct ExtraUsage: Decodable {
        /// The usage credits spent this month. Nil unless usage credits are
        /// enabled and every amount sent, and its currency, is valid.
        let spent: Money?
        /// The monthly spend limit, above zero; nil when there is none.
        let limit: Money?

        private enum CodingKeys: String, CodingKey {
            case is_enabled, monthly_limit, used_credits, currency
        }

        init(from decoder: any Decoder) {
            (spent, limit) = Self.amounts(decoder) ?? (nil, nil)
        }

        /// Both amounts are whole minor units of `currency`, e.g. cents. A
        /// limit that is sent but malformed is not taken as no limit, and a
        /// zero limit shows no row.
        private static func amounts(_ decoder: any Decoder) -> (Money, Money?)? {
            guard let values = try? decoder.container(keyedBy: CodingKeys.self),
                  (try? values.decodeIfPresent(Bool.self, forKey: .is_enabled)) == true,
                  let currency = try? values.decodeIfPresent(String.self, forKey: .currency),
                  let used = try? values.decodeIfPresent(Int.self, forKey: .used_credits),
                  let spent = Money(minorUnits: used, currency: currency)
            else { return nil }
            let limitUnits: Int?
            do {
                limitUnits = try values.decodeIfPresent(Int.self, forKey: .monthly_limit)
            } catch {
                return nil
            }
            guard let limitUnits else { return (spent, nil) }
            guard limitUnits > 0, let limit = Money(minorUnits: limitUnits, currency: currency) else { return nil }
            return (spent, limit)
        }
    }

    private struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    /// An entry of `limits[]`. Its `percent` is 0–100, like `utilization`.
    private struct Limit: Decodable {
        let kind: String?
        let percent: Double?
        let resets_at: String?
        let scope: Scope?

        var window: Window { Window(utilization: percent, resets_at: resets_at) }
        var key: Key { Key(kind: kind, model: scope?.model?.display_name) }

        /// The quota an entry is a copy of: its kind and, if scoped, its model.
        struct Key: Hashable {
            let kind: String?
            let model: String?
        }

        struct Scope: Decodable {
            let model: Model?
        }

        struct Model: Decodable {
            let display_name: String?
        }
    }
}
