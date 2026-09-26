import Foundation

/// Codex adapter: builds the usage query of a ChatGPT session and translates
/// its response into normalized quotas.
enum Codex: ProviderAdapter {
    static let provider = Provider.codex

    static func request(for session: Session) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        // The session reader always gives the account (`tokens.account_id`).
        if let accountID = session.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        return request
    }

    /// Returns an error when the response does not have the expected format.
    ///
    /// Each window is named by its length, never by its position: the
    /// provider may send the weekly window first. Windows of the same length
    /// and limit name are copies of one quota, wherever they appear in the
    /// response, and the reading decides whether they agree. Credits, spend
    /// control, model usage and every identifier are ignored; the plan is
    /// read apart.
    static func quotas(from body: Data, readAt moment: Date) -> Result<[QuotaReading], Failure> {
        guard let response = try? JSONDecoder().decode(Response.self, from: body) else { return .failure(.incompatibleResponse) }
        // A named limit may arrive in several entries, so its windows are
        // gathered by name before they are read. Names keep the order in
        // which they first appear.
        var names: [String] = []
        var namedWindows: [String: [Window]] = [:]
        for limit in response.additional_rate_limits ?? [] {
            guard let name = limit.limit_name else { continue }
            if namedWindows[name] == nil { names.append(name) }
            namedWindows[name, default: []].append(contentsOf: windows(of: limit.rate_limit))
        }
        let limits = names.flatMap { name in
            readings(of: namedWindows[name, default: []], at: moment) { .limit(name, $0) }
        }
        let quotas = readings(of: windows(of: response.rate_limit), at: moment) { $0 } + limits
        // Nothing says the plan has no quotas, so a response without any
        // window is not understood.
        return quotas.isEmpty ? .failure(.incompatibleResponse) : .success(quotas)
    }

    /// `rate_limit_reset_credits.available_count`, the total the account
    /// holds. Read on its own, so a bad value hides the count and never the
    /// quotas. `applicable_available_count` and every other field are ignored.
    static func bankedResets(from body: Data) -> Int? {
        guard let count = (try? JSONDecoder().decode(BankedResets.self, from: body))?.availableCount, count > 0
        else { return nil }
        return count
    }

    /// `plan_type`, by ChatGPT's name. Read on its own, like the banked
    /// resets, so a bad value hides the plan and never the quotas.
    static func plan(of session: Session, response body: Data) -> String? {
        (try? JSONDecoder().decode(Plan.self, from: body))?.plan_type.flatMap { planNames[$0] }
    }

    /// Every `plan_type` Uzzy knows. Any other value shows no plan.
    private static let planNames = [
        "free": "Free", "go": "Go", "plus": "Plus", "pro": "Pro",
        "team": "Team", "business": "Business", "enterprise": "Enterprise", "edu": "Edu",
    ]

    private static func windows(of rateLimit: RateLimit?) -> [Window] {
        [rateLimit?.primary_window, rateLimit?.secondary_window].compactMap { $0 }
    }

    /// One reading per window length, the shortest first.
    private static func readings(
        of windows: [Window],
        at moment: Date,
        named name: (QuotaPeriod) -> QuotaPeriod
    ) -> [QuotaReading] {
        let byLength = Dictionary(grouping: windows, by: \.limit_window_seconds)
        return byLength.keys.sorted().map { length in
            let copies = byLength[length, default: []]
            return QuotaReading(
                period: name(period(lasting: length)),
                usedPercents: copies.compactMap(\.used_percent),
                resets: copies.compactMap(\.reset_at).map { Date(timeIntervalSince1970: $0) },
                readAt: moment
            )
        }
    }

    private static func period(lasting seconds: Int) -> QuotaPeriod {
        switch seconds {
        case 18_000: .fiveHours
        case 604_800: .weekly
        default: .lasting(seconds: seconds)
        }
    }

    /// Only an integer count is kept: fractional, overflowing or non-numeric
    /// values, and a `rate_limit_reset_credits` that is not an object, give
    /// none.
    private struct BankedResets: Decodable {
        let availableCount: Int?

        private enum CodingKeys: String, CodingKey {
            case rate_limit_reset_credits
        }

        private enum CreditKeys: String, CodingKey {
            case available_count
        }

        init(from decoder: any Decoder) throws {
            let credits = try? decoder.container(keyedBy: CodingKeys.self)
                .nestedContainer(keyedBy: CreditKeys.self, forKey: .rate_limit_reset_credits)
            availableCount = try? credits?.decodeIfPresent(Int.self, forKey: .available_count)
        }
    }

    private struct Plan: Decodable {
        let plan_type: String?
    }

    private struct Response: Decodable {
        let rate_limit: RateLimit?
        let additional_rate_limits: [AdditionalLimit]?
    }

    private struct RateLimit: Decodable {
        let primary_window: Window?
        let secondary_window: Window?
    }

    /// A limit the provider sends apart from the main windows, e.g. for a
    /// single model. Without a name it cannot be told apart, so it is left out.
    private struct AdditionalLimit: Decodable {
        let limit_name: String?
        let rate_limit: RateLimit?
    }

    private struct Window: Decodable {
        let used_percent: Double?
        let limit_window_seconds: Int
        let reset_at: Double?

        private enum CodingKeys: String, CodingKey {
            case used_percent, limit_window_seconds, reset_at
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            used_percent = try values.decodeIfPresent(Double.self, forKey: .used_percent)
            limit_window_seconds = try values.decode(Int.self, forKey: .limit_window_seconds)
            // A bad reset must not discard a valid percentage. Keep an
            // invalid value so another copy cannot supply a trusted reset.
            do {
                reset_at = try values.decodeIfPresent(Double.self, forKey: .reset_at)
            } catch {
                reset_at = .nan
            }
        }
    }
}
