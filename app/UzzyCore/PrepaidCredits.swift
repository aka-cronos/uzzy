import Foundation

extension Cursor {
    static func prepaidRequest(for session: Session, refreshing: Bool) -> URLRequest {
        var request = request(for: session)
        request.url = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetUserPrepaidBilling")!
        request.httpBody = Data((refreshing ? #"{"limit":1,"skipBalanceCache":true}"# : #"{"limit":1}"#).utf8)
        return request
    }

    static func prepaidBalance(from body: Data, accountID: String, at now: Date) -> CreditState {
        struct Response: Decodable {
            let billingMode: Mode
            let eligible: Bool?
            let availableCents: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: body) else { return .invalid(keeping: nil) }
        guard response.eligible == true else { return .ineligible }
        guard let cents = CreditDecimal.parse(response.availableCents ?? "0", integer: true), cents <= Decimal(Int64.max) else { return .invalid(keeping: nil) }
        guard cents > 0 else { return .zero }
        return .reading(CreditReading(
            value: .money(Money(amount: cents / 100, currency: "USD")), total: nil, expiresAt: nil,
            accountID: accountID, organizationID: nil, source: .cursorPrepaid, readAt: now
        ))
    }

    private enum Mode: Decodable {
        case onDemand, prepaid
        init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let name = try? value.decode(String.self) {
                switch name {
                case "PREPAID_BILLING_MODE_ON_DEMAND": self = .onDemand
                case "PREPAID_BILLING_MODE_PREPAID": self = .prepaid
                default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown billing mode")
                }
            } else {
                switch try value.decode(Int.self) {
                case 1: self = .onDemand
                case 2: self = .prepaid
                default: throw DecodingError.dataCorruptedError(in: value, debugDescription: "Unknown billing mode")
                }
            }
        }
    }
}

extension Claude {
    static func profileRequest(for session: Session) -> URLRequest {
        var request = request(for: session)
        request.url = URL(string: "https://api.anthropic.com/api/oauth/profile")!
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("claude_code_cli", forHTTPHeaderField: "anthropic-client-platform")
        return request
    }

    static func organization(from body: Data, accountID: String) -> String? {
        struct Profile: Decodable {
            struct Identity: Decodable { let uuid: String }
            let account: Identity
            let organization: Identity
        }
        guard let profile = try? JSONDecoder().decode(Profile.self, from: body),
              profile.account.uuid == accountID,
              UUID(uuidString: profile.organization.uuid) != nil else { return nil }
        return profile.organization.uuid
    }

    static func prepaidRequest(for session: Session, organizationID: String) -> URLRequest {
        var request = profileRequest(for: session)
        request.url = URL(string: "https://api.anthropic.com/api/oauth/organizations/\(organizationID)/prepaid/credits")!
        request.setValue(organizationID, forHTTPHeaderField: "x-organization-uuid")
        return request
    }

    static func prepaidBalance(from body: Data, accountID: String, organizationID: String, at now: Date) -> CreditState {
        struct Response: Decodable {
            let amount: Decimal
            let currency: String
            let hasPositiveScopedCredit: Bool

            enum CodingKeys: String, CodingKey { case amount, amount_without_scoped_credits, currency, tranches }
            struct Tranche: Decodable {
                let remaining_amount_minor_units: Decimal
                let scope: Scope?
                enum Scope: Decodable {
                    case restricted
                    init(from decoder: any Decoder) { self = .restricted }
                }
            }

            init(from decoder: any Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                currency = try values.decode(String.self, forKey: .currency)
                if let unscoped = try values.decodeIfPresent(Decimal.self, forKey: .amount_without_scoped_credits) {
                    amount = unscoped
                    hasPositiveScopedCredit = false
                } else {
                    amount = try values.decode(Decimal.self, forKey: .amount)
                    let tranches = try values.decodeIfPresent([Tranche].self, forKey: .tranches) ?? []
                    hasPositiveScopedCredit = tranches.contains {
                        $0.scope != nil && ($0.remaining_amount_minor_units.isNaN || $0.remaining_amount_minor_units > 0)
                    }
                }
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: body), !response.hasPositiveScopedCredit
        else { return .invalid(keeping: nil) }
        let amount = response.amount
        guard let money = Money(exactMinorUnits: amount, currency: response.currency) else { return .invalid(keeping: nil) }
        guard amount > 0 else { return .zero }
        return .reading(CreditReading(value: .money(money), total: nil, expiresAt: nil,
                                      accountID: accountID, organizationID: organizationID, source: .claudePrepaid, readAt: now))
    }
}

extension Money {
    init?(exactMinorUnits amount: Decimal, currency: String) {
        guard !amount.isNaN, amount >= 0, Locale.commonISOCurrencyCodes.contains(currency) else { return nil }
        var original = amount
        var whole = Decimal()
        NSDecimalRound(&whole, &original, 0, .plain)
        guard whole == amount else { return nil }
        self.init(minorUnits: amount, currency: currency)
    }
}
