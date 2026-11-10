import Foundation

extension Claude {
    static func bankedResets(from body: Data, readAt moment: Date) -> BankedResets? {
        guard let response = try? JSONDecoder().decode(ResetResponse.self, from: body),
              let program = response.cedar_ember, program.eligible else { return nil }
        let grants = (program.grants ?? []).compactMap(\.value).filter { grant in
            guard grant.paused != true, grant.usable_now == true else { return false }
            guard let expiry = grant.ends_at else { return true }
            return resetExpiry(expiry).map { $0 > moment } ?? false
        }
        guard let next = grants.first(where: { $0.id == program.next_grant_id }) else {
            return BankedResets(grants: [])
        }
        return BankedResets(
            grants: grants.map { .init(count: $0.resets_left, expiresAt: $0.ends_at.flatMap(resetExpiry)) },
            nextExpiresAt: next.ends_at.flatMap(resetExpiry)
        )
    }

    private static func resetExpiry(_ text: String) -> Date? {
        guard text.wholeMatch(of: #/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})/#) != nil else { return nil }
        let fields = text.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard fields.count == 6 else { return nil }
        let components = DateComponents(
            calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0),
            year: fields[0], month: fields[1], day: fields[2],
            hour: fields[3], minute: fields[4], second: fields[5]
        )
        guard fields[0] > 0, components.isValidDate else { return nil }
        return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    private struct ResetResponse: Decodable {
        let cedar_ember: Program?
    }

    private struct Program: Decodable {
        let eligible: Bool
        let grants: [OptionalGrant]?
        let next_grant_id: String?
    }

    private struct OptionalGrant: Decodable {
        let value: Grant?

        init(from decoder: any Decoder) {
            value = try? Grant(from: decoder)
        }
    }

    private struct Grant: Decodable {
        let id: String
        let resets_left: Int
        let ends_at: String?
        let paused: Bool?
        let usable_now: Bool?

        enum CodingKeys: String, CodingKey { case id, resets_left, ends_at, paused, usable_now }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            resets_left = try values.decode(Int.self, forKey: .resets_left)
            ends_at = try values.decodeIfPresent(String.self, forKey: .ends_at)
            paused = try values.decodeIfPresent(Bool.self, forKey: .paused)
            usable_now = try values.decodeIfPresent(Bool.self, forKey: .usable_now)
            guard id.wholeMatch(of: #/[a-z0-9_-]{1,40}/#) != nil, resets_left >= 0 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid reset grant"))
            }
        }
    }
}
