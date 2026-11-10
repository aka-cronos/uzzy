import Foundation

/// A successful account reading, evaluated again as its grants expire.
struct BankedResets {
    struct Grant {
        let count: Int
        let expiresAt: Date?
    }

    let grants: [Grant]
    var nextExpiresAt: Date? = nil

    func count(at now: Date) -> Int? {
        guard nextExpiresAt.map({ $0 > now }) ?? true else { return nil }
        var total = 0
        for grant in grants where grant.expiresAt.map({ $0 > now }) ?? true {
            let (sum, overflow) = total.addingReportingOverflow(grant.count)
            guard !overflow else { return nil }
            total = sum
        }
        return total > 0 ? total : nil
    }
}
