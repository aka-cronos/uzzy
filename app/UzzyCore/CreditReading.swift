import Foundation

public enum CreditValue: Sendable, Equatable {
    case money(Money)
    case credits(Decimal)
}

public enum CreditSource: Sendable, Equatable {
    case codexUsage, cursorPrepaid, claudePrepaid, claudeCloudUsage
}

public struct CreditReading: Sendable, Equatable {
    public let value: CreditValue
    public let total: Money?
    public let expiresAt: Date?
    public let accountID: String
    public let organizationID: String?
    public let source: CreditSource
    public let readAt: Date
    public var isStale: Bool = false
}

public enum CreditState: Sendable, Equatable {
    case absent, zero, unlimited, ineligible
    case reading(CreditReading)
    case invalid(keeping: CreditReading?)
    case failed(keeping: CreditReading?)

    public func visible(at now: Date) -> CreditReading? {
        let reading: CreditReading?
        switch self {
        case .reading(let value): reading = value
        case .invalid(let kept), .failed(let kept): reading = kept
        default: reading = nil
        }
        guard let reading, reading.expiresAt.map({ $0 > now }) ?? true else { return nil }
        return reading
    }

    func retaining(_ previous: CreditState, at now: Date) -> CreditState {
        var kept = previous.visible(at: now)
        kept?.isStale = true
        switch self {
        case .invalid: return .invalid(keeping: kept)
        case .failed: return .failed(keeping: kept)
        default: return self
        }
    }
}

/// Decimal text is checked before Foundation parses it, which otherwise accepts
/// numeric prefixes and can silently round amounts beyond Decimal's precision.
enum CreditDecimal {
    static func parse(_ text: String, integer: Bool = false) -> Decimal? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || (!integer && parts.count == 2),
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        let digits = parts.joined().drop(while: { $0 == "0" })
        let significant = digits.reversed().drop(while: { $0 == "0" })
        guard significant.count <= 38, let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0, value > 0 || digits.isEmpty else { return nil }
        return value
    }
}

extension Codex {
    static func creditBalance(from body: Data, accountID: String, at now: Date) -> CreditState {
        struct Envelope: Decodable {
            let credits: Balance?
            struct Balance: Decodable {
                let balance: String?
                let unlimited: Bool?
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return .invalid(keeping: nil) }
        guard let credits = envelope.credits else { return .absent }
        if credits.unlimited == true { return .unlimited }
        guard let text = credits.balance else { return .absent }
        guard let amount = CreditDecimal.parse(text) else { return .invalid(keeping: nil) }
        guard amount > 0 else { return .zero }
        return .reading(CreditReading(value: .credits(amount), total: nil, expiresAt: nil,
                                      accountID: accountID, organizationID: nil, source: .codexUsage, readAt: now))
    }
}

extension Claude {
    static func cloudCredit(from body: Data, accountID: String, at now: Date) -> CreditState {
        struct Envelope: Decodable {
            let iguana_necktie: Grant?
            struct Grant: Decodable {
                let remaining_dollars: Decimal
                let resets_at: String
                let limit_dollars: Decimal?

                enum CodingKeys: String, CodingKey { case remaining_dollars, resets_at, limit_dollars }

                init(from decoder: any Decoder) throws {
                    let values = try decoder.container(keyedBy: CodingKeys.self)
                    remaining_dollars = try values.decode(Decimal.self, forKey: .remaining_dollars)
                    resets_at = try values.decode(String.self, forKey: .resets_at)
                    limit_dollars = try? values.decode(Decimal.self, forKey: .limit_dollars)
                }
            }
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return .invalid(keeping: nil) }
        guard let grant = envelope.iguana_necktie else { return .absent }
        guard !grant.remaining_dollars.isNaN, grant.remaining_dollars >= 0,
              let expiry = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(grant.resets_at))
                ?? (try? Date.ISO8601FormatStyle().parse(grant.resets_at))
        else { return .invalid(keeping: nil) }
        guard grant.remaining_dollars > 0, expiry > now else { return .zero }
        let total = grant.limit_dollars.flatMap { amount -> Money? in
            guard !amount.isNaN, amount >= grant.remaining_dollars else { return nil }
            return Money(amount: amount, currency: "USD")
        }
        return .reading(CreditReading(
            value: .money(Money(amount: grant.remaining_dollars, currency: "USD")), total: total, expiresAt: expiry,
            accountID: accountID, organizationID: nil, source: .claudeCloudUsage, readAt: now
        ))
    }
}
