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
    @Test func positiveSubcentCloudAmountsRemainVisibleInBothLanguages() {
        let remaining = Money(amount: Decimal(string: "0.004")!, currency: "USD")
        let total = Money(amount: Decimal(string: "0.008")!, currency: "USD")
        #expect(Format.english.cloudCredit(remaining, total: nil) == "$0.004")
        #expect(Format.english.cloudCredit(remaining, total: total) == "$0.004 of $0.008 left")
        #expect(Format.spanish.cloudCredit(remaining, total: nil) == "0,004 US$")
        #expect(Format.spanish.cloudCredit(remaining, total: total) == "0,004 US$ de 0,008 US$ restantes")
    }
    @Test func expiryUsesTheSelectedLocalCalendarDayAndHourAcrossMidnight() {
        let date = Date(timeIntervalSince1970: 1_893_459_600) // 2030-01-01 01:00 UTC
        let utc = TimeZone(identifier: "UTC")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        #expect(Format.english.creditExpiry(date, timeZone: utc) == "Expires Jan 1, 2030, 1:00\u{202F}AM")
        #expect(Format.english.creditExpiry(date, timeZone: losAngeles) == "Expires Dec 31, 2029, 5:00\u{202F}PM")
        #expect(Format.spanish.creditExpiry(date, timeZone: utc) == "Vence 1 ene 2030, 01:00")
        #expect(Format.spanish.creditExpiry(date, timeZone: losAngeles) == "Vence 31 dic 2029, 17:00")
    }
    @Test func cloudWholeAndCentsAndMonthlySpendingKeepTheirExistingFormats() {
        let remaining = Money(amount: Decimal(string: "7.50")!, currency: "USD")
        let total = Money(amount: 120, currency: "USD")
        #expect(Format.english.cloudCredit(remaining, total: total) == "$7.50 of $120 left")
        #expect(Format.spanish.cloudCredit(remaining, total: total) == "7,50 US$ de 120 US$ restantes")
        #expect(Format.english.cloudCredit(total, total: nil) == "$120")
        #expect(Format.spanish.cloudCredit(total, total: nil) == "120 US$")
        #expect(Format.english.usageCredits(remaining, limit: total) == "$7.50 of $120 this month")
        #expect(Format.spanish.usageCredits(remaining, limit: total) == "7,50 US$ de 120 US$ este mes")
        let subcent = Money(amount: Decimal(string: "0.004")!, currency: "USD")
        #expect(Format.english.money(subcent) == "$0.00")
        #expect(Format.spanish.money(subcent) == "0,00 US$")
    }
    @Test func cloudPrecisionIncludesSmallPositiveDecimalExponents() {
        let value = Money(amount: Decimal(string: "0.0000000000000000000000000000000000000001")!, currency: "USD")
        #expect(Format.english.cloudCredit(value, total: nil) == "$0.0000000000000000000000000000000000000001")
        #expect(Format.spanish.cloudCredit(value, total: nil) == "0,0000000000000000000000000000000000000001 US$")
    }
}
