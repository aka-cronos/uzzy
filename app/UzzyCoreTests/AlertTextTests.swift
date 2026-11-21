import Foundation
import Testing
import UzzyCore

/// The two lines of each alert's notification, and the Settings thresholds,
/// in each language, from `Uzzy/Format.swift`, which this target compiles.
struct AlertTextTests {
    let now = FormatTextTests.moment(day: 24, hour: 12, minute: 24)
    let reset = FormatTextTests.moment(day: 24, hour: 14, minute: 42)

    var nearLimit: UsageAlert { .nearLimit(.claude, period: .fiveHours, usedPercent: 85, reset: reset) }
    var limitReached: UsageAlert { .limitReached(.claude, period: .fiveHours, reset: reset) }
    let limitReset = UsageAlert.limitReset(.claude, period: .fiveHours)

    @Test func nearALimitShowsTheReadingsPercentageInTheChosenMagnitude() {
        #expect(Format.english.alertTitle(nearLimit, provider: "Claude", magnitude: .used) == "85% used on Claude (5-hour)")
        #expect(Format.english.alertTitle(nearLimit, provider: "Claude", magnitude: .remaining) == "15% left on Claude (5-hour)")
        #expect(Format.spanish.alertTitle(nearLimit, provider: "Claude", magnitude: .used) == "85% usado en Claude (5 horas)")
        #expect(Format.spanish.alertTitle(nearLimit, provider: "Claude", magnitude: .remaining) == "15% restante en Claude (5 horas)")
    }

    @Test func theBodySaysWhenTheLimitResetsInTheChosenCountdown() {
        #expect(Format.english.alertBody(nearLimit, now: now, countdown: .detailed) == "Resets today, 2:42\u{202F}PM · in 2 h 18 min")
        #expect(Format.english.alertBody(nearLimit, now: now) == "Resets today, 2:42\u{202F}PM · in 2 h")
        #expect(Format.spanish.alertBody(limitReached, now: now, countdown: .detailed) == "Reinicio: Hoy, 14:42 · en 2 h 18 min")
    }

    @Test func withoutAKnownResetTheBodyIsEmpty() {
        let alert = UsageAlert.nearLimit(.claude, period: .fiveHours, usedPercent: 85, reset: nil)

        #expect(Format.english.alertBody(alert, now: now) == "")
        #expect(Format.english.alertBody(.limitReached(.claude, period: .fiveHours, reset: now.addingTimeInterval(-60)), now: now) == "")
    }

    @Test func aLimitReached() {
        #expect(Format.english.alertTitle(limitReached, provider: "Claude", magnitude: .used) == "Claude (5-hour) limit reached")
        #expect(Format.spanish.alertTitle(limitReached, provider: "Claude", magnitude: .remaining) == "Claude (5 horas) llegó al límite")
    }

    @Test func aConfirmedReset() {
        #expect(Format.english.alertTitle(limitReset, provider: "Claude", magnitude: .used) == "Claude ready to use again")
        #expect(Format.english.alertBody(limitReset, now: now) == "5-hour limit reset")
        #expect(Format.spanish.alertTitle(limitReset, provider: "Claude", magnitude: .used) == "Claude listo para volver a usarse")
        #expect(Format.spanish.alertBody(limitReset, now: now) == "Límite de 5 horas reiniciado")

        #expect(Format.english.alertBody(.limitReset(.codex, period: .weekly), now: now) == "Weekly limit reset")
        #expect(Format.spanish.alertBody(.limitReset(.codex, period: .weekly), now: now) == "Límite semanal reiniciado")
    }

    /// A limit the provider names goes in the period's place.
    @Test func aNamedLimitShowsItsName() {
        let sonnet = UsageAlert.limitReached(.claude, period: .limit("Sonnet", .weekly), reset: nil)
        let bag = UsageAlert.limitReached(.cursor, period: .limit("Cursor Models", .billingCycle), reset: nil)

        #expect(Format.english.alertTitle(sonnet, provider: "Claude", magnitude: .used) == "Claude (Sonnet · weekly) limit reached")
        #expect(Format.spanish.alertTitle(sonnet, provider: "Claude", magnitude: .used) == "Claude (Sonnet · semanal) llegó al límite")
        #expect(Format.english.alertTitle(bag, provider: "Cursor", magnitude: .used) == "Cursor (Cursor Models) limit reached")
        #expect(Format.english.alertBody(.limitReset(.cursor, period: .limit("Cursor Models", .billingCycle)), now: now) == "Cursor Models limit reset")
        #expect(Format.spanish.alertBody(.limitReset(.claude, period: .limit("Sonnet", .weekly)), now: now) == "Límite de Sonnet · semanal reiniciado")
    }

    @Test func theThresholdFollowsTheChosenMagnitude() {
        #expect(Format.english.threshold(80, in: .used) == "80% used")
        #expect(Format.english.threshold(80, in: .remaining) == "20% left")
        #expect(Format.spanish.threshold(85, in: .used) == "85% usado")
        #expect(Format.spanish.threshold(85, in: .remaining) == "15% restante")
    }
}
