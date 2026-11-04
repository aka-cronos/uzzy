import Foundation

/// Cursor adapter: builds the usage query of Cursor's session and translates
/// its response into weekly unified usage or legacy billing-cycle bags.
enum Cursor: ProviderAdapter {
    static let provider = Provider.cursor

    /// A Connect call with an empty JSON message. There is no REST fallback.
    static func request(for session: Session) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)
        return request
    }

    static func metadataRequest(for session: Session) -> URLRequest? {
        var request = request(for: session)
        request.url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetPlanInfo")!
        return request
    }

    static func quotas(from body: Data, metadata: Data?, readAt moment: Date) -> Result<[QuotaReading], Failure> {
        let response: Response
        let plan: PlanResponse
        do {
            response = try JSONDecoder().decode(Response.self, from: body)
            guard let metadata else { return .failure(.incompatibleResponse) }
            plan = try JSONDecoder().decode(PlanResponse.self, from: metadata)
        } catch DecodingError.typeMismatch(_, let context)
            where ["billingCycleEnd", "includedUsageResetsAt"].contains(context.codingPath.last?.stringValue) {
            return .failure(.incompatibleResetFormat)
        } catch {
            return .failure(.incompatibleResponse)
        }
        guard let info = plan.planInfo, let usage = response.planUsage else { return .failure(.incompatibleResponse) }
        if plan.isMerged == true || info.includedUsagePeriod == .weekly {
            guard info.includedUsagePeriod == .weekly else {
                return .failure(.incompatibleResponse)
            }
            return .success([QuotaReading(
                period: .weekly,
                usedPercents: [usage.totalPercentUsed].compactMap { $0 },
                resets: [info.includedUsageResetsAt.flatMap(date(fromMilliseconds:))].compactMap { $0 },
                readAt: moment
            )])
        }
        let resets = [response.billingCycleEnd.flatMap(date(fromMilliseconds:))].compactMap { $0 }
        func reading(_ bag: String, _ usedPercent: Double?) -> QuotaReading {
            QuotaReading(
                period: .limit(bag, .billingCycle),
                usedPercents: [usedPercent].compactMap { $0 },
                resets: resets,
                readAt: moment
            )
        }
        return .success([
            reading("Cursor Models", usage.autoPercentUsed),
            reading("Other Models", usage.apiPercentUsed),
        ])
    }

    /// The plan Cursor keeps with the session (`stripeMembershipType`), by
    /// Cursor's name. The usage response names no plan.
    static func plan(of session: Session, response body: Data) -> String? {
        session.plan.flatMap { planNames[$0] }
    }

    /// Every `stripeMembershipType` Uzzy knows, by the name Cursor's own app
    /// shows: the plans from before and those of accounts unified with xAI.
    /// Any other value, such as a trial, shows no plan.
    private static let planNames = [
        "free": "Hobby", "pro": "Pro", "pro_plus": "Pro+", "ultra": "Ultra",
        "plus": "Plus", "premium": "Premium", "super": "Super", "unified_ultra": "Ultra",
    ]

    /// `billingCycleEnd` is a string of epoch milliseconds.
    private static func date(fromMilliseconds text: String) -> Date? {
        guard let milliseconds = Int64(text), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    private struct PlanResponse: Decodable {
        let isMerged: Bool?
        let planInfo: PlanInfo?
    }

    private struct PlanInfo: Decodable {
        let includedUsagePeriod: UsagePeriod?
        let includedUsageResetsAt: String?
    }

    private enum UsagePeriod: Decodable {
        case weekly
        case monthly

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let name = try? value.decode(String.self) {
                switch name {
                case "INCLUDED_USAGE_PERIOD_WEEKLY": self = .weekly
                case "INCLUDED_USAGE_PERIOD_MONTHLY", "INCLUDED_USAGE_PERIOD_UNSPECIFIED": self = .monthly
                default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown included usage period")
                }
            } else {
                switch try value.decode(Int.self) {
                case 2: self = .weekly
                case 0, 1: self = .monthly
                default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown included usage period")
                }
            }
        }
    }

    private struct Response: Decodable {
        let billingCycleEnd: String?
        let planUsage: PlanUsage?
    }

    private struct PlanUsage: Decodable {
        let autoPercentUsed: Double?
        let apiPercentUsed: Double?
        let totalPercentUsed: Double?
    }
}
