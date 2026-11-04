import Foundation
import Testing
import UzzyCore

struct CreditTextTests {
    @Test func creditQuantityUsesTheLocaleWithoutACurrency() {
        let value = CreditValue.credits(Decimal(string: "123.45")!)
        #expect(Format.english.creditBalance(value) == "123.45 credits left")
        #expect(Format.spanish.creditBalance(value) == "123,45 créditos restantes")
    }

    @Test func cloudAmountsAreDollarsAndTheTotalIsOptional() {
        let remaining = Money(amount: 90, currency: "USD")
        let total = Money(amount: 120, currency: "USD")
        #expect(Format.english.cloudCredit(remaining, total: total) == "$90 of $120 left")
        #expect(Format.english.cloudCredit(remaining, total: nil) == "$90")
        #expect(Format.spanish.cloudCredit(remaining, total: total).contains("restantes"))
    }

    @Test func expiryIncludesTheExactLocalDateAndMinute() {
        let date = Date(timeIntervalSince1970: 1_893_585_600)
        let format = Format.english
        #expect(format.creditExpiry(date).hasPrefix("Expires "))
        #expect(format.creditExpiry(date).contains(format.time(date)))
        #expect(Format.spanish.creditExpiry(date).hasPrefix("Vence "))
    }
}
