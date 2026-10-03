import Foundation
import Testing
import UzzyCore

/// The app's formatted copy in each language, from `Uzzy/Format.swift`, which
/// this target compiles. Each test sets the language, so none depends on the
/// language of the Mac that runs it.
struct FormatTextTests {
    /// A Thursday morning in the time zone the tests run in.
    let now = moment(day: 24, hour: 10, minute: 0)

    /// A moment in September 2026, in the time zone the tests run in.
    static func moment(day: Int, hour: Int, minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// Usage credits spent this month.
    let spent = Money(amount: Decimal(string: "53.06")!, currency: "USD")
    /// The monthly spend limit of those usage credits.
    let limit = Money(amount: 40, currency: "USD")

    @Test func commandNames() {
        #expect(Format.spanish.quitApp == "Salir de \(Format.appName)")
        #expect(Format.spanish.settings == "Ajustes")
        #expect(Format.spanish.openSettings == "Ajustes…")
        #expect(Format.spanish.fileMenu == "Archivo")
        #expect(Format.spanish.closeWindow == "Cerrar ventana")

        #expect(Format.english.quitApp == "Quit \(Format.appName)")
        #expect(Format.english.settings == "Settings")
        #expect(Format.english.openSettings == "Settings…")
        #expect(Format.english.fileMenu == "File")
        #expect(Format.english.closeWindow == "Close Window")
    }

    /// A language the catalog lacks gets English, with its own region's formats.
    @Test func anotherLanguageFallsBackToEnglish() {
        let french = Format(locale: Locale(identifier: "fr_FR"))

        #expect(french.settings == "Settings")
        #expect(french.reset(.at(Self.moment(day: 24, hour: 12, minute: 5)), now: now) == "Resets today, 12:05 · in 2 h 5 min")
    }

    @Test func aPercentageKeepsItsDecimalPointInEveryLanguage() {
        #expect(Format.spanish.percent(20.5) == "20.5%")
        #expect(Format.english.percent(20.5) == "20.5%")
        #expect(Format.spanish.percent(20) == "20%")
        #expect(Format.english.percent(20) == "20%")
    }

    @Test func aTimeFollowsTheRegionsHourCycle() {
        let (morning, afternoon) = (Self.moment(day: 24, hour: 9, minute: 5), Self.moment(day: 24, hour: 14, minute: 42))

        #expect(Format.spanish.time(morning) == "09:05")
        #expect(Format.spanish.time(afternoon) == "14:42")
        #expect(Format.english.time(morning) == "9:05\u{202F}AM")
        #expect(Format.english.time(afternoon) == "2:42\u{202F}PM")
        // English text in a region with a 24-hour clock.
        let englishInSpain = Format(locale: Locale(identifier: "en_ES"))
        #expect(englishInSpain.time(morning) == "09:05")
        #expect(englishInSpain.time(afternoon) == "14:42")
    }

    @Test func aMomentNamesItsDay() {
        let today = Self.moment(day: 24, hour: 14, minute: 42)
        let tomorrow = Self.moment(day: 25, hour: 9, minute: 5)
        let sunday = Self.moment(day: 27, hour: 14, minute: 42)

        #expect(Format.spanish.dayAndTime(today, now: now) == "Hoy, 14:42")
        #expect(Format.spanish.dayAndTime(tomorrow, now: now) == "Mañana, 09:05")
        #expect(Format.spanish.dayAndTime(sunday, now: now) == "dom, 27 sept, 14:42")

        #expect(Format.english.dayAndTime(today, now: now) == "today, 2:42\u{202F}PM")
        #expect(Format.english.dayAndTime(tomorrow, now: now) == "tomorrow, 9:05\u{202F}AM")
        #expect(Format.english.dayAndTime(sunday, now: now) == "Sun, Sep 27, 2:42\u{202F}PM")
    }

    @Test func aResetReadsAsItsMomentAndCountdown() {
        let soon = Self.moment(day: 24, hour: 10, minute: 30)
        let later = Self.moment(day: 24, hour: 12, minute: 5)
        let sunday = Self.moment(day: 27, hour: 14, minute: 42)

        #expect(Format.spanish.reset(.unknown, now: now) == "Reinicio desconocido")
        #expect(Format.spanish.reset(.pendingConfirmation, now: now) == "Reinicio pendiente de confirmar")
        #expect(Format.spanish.reset(.at(soon), now: now) == "Reinicio: Hoy, 10:30 · en 30 min")
        #expect(Format.spanish.reset(.at(later), now: now) == "Reinicio: Hoy, 12:05 · en 2 h 5 min")
        #expect(Format.spanish.reset(.at(sunday), now: now) == "Reinicio: dom, 27 sept, 14:42 · en 3 d 4 h")

        #expect(Format.english.reset(.unknown, now: now) == "Reset unknown")
        #expect(Format.english.reset(.pendingConfirmation, now: now) == "Reset pending confirmation")
        #expect(Format.english.reset(.at(soon), now: now) == "Resets today, 10:30\u{202F}AM · in 30 min")
        #expect(Format.english.reset(.at(later), now: now) == "Resets today, 12:05\u{202F}PM · in 2 h 5 min")
        #expect(Format.english.reset(.at(sunday), now: now) == "Resets Sun, Sep 27, 2:42\u{202F}PM · in 3 d 4 h")
    }

    @Test func usageCreditsReadAsTheAmountSpentThisMonth() {
        #expect(Format.spanish.money(spent) == "53,06\u{00A0}US$")
        #expect(Format.spanish.usageCredits(spent, limit: limit) == "53,06\u{00A0}US$ de 40\u{00A0}US$ este mes")
        #expect(Format.spanish.usageCredits(spent, limit: nil) == "53,06\u{00A0}US$ este mes")

        #expect(Format.english.money(spent) == "$53.06")
        #expect(Format.english.usageCredits(spent, limit: limit) == "$53.06 of $40 this month")
        #expect(Format.english.usageCredits(spent, limit: nil) == "$53.06 this month")
    }

    @Test func aQuotaPeriodReadsInItsLargestWholeUnit() {
        #expect(Format.spanish.duration(seconds: 86_400) == "1 día")
        #expect(Format.spanish.duration(seconds: 2 * 86_400) == "2 días")
        #expect(Format.spanish.duration(seconds: 3_600) == "1 hora")
        #expect(Format.spanish.duration(seconds: 5 * 3_600) == "5 horas")
        #expect(Format.spanish.duration(seconds: 5_400) == "90 min")
        #expect(Format.spanish.duration(seconds: 45) == "45 s")

        #expect(Format.english.duration(seconds: 86_400) == "1 day")
        #expect(Format.english.duration(seconds: 2 * 86_400) == "2 days")
        #expect(Format.english.duration(seconds: 3_600) == "1 hour")
        #expect(Format.english.duration(seconds: 5 * 3_600) == "5 hours")
        #expect(Format.english.duration(seconds: 5_400) == "90 min")
        #expect(Format.english.duration(seconds: 45) == "45 s")
    }

    @Test func aQuotaIsNamedByItsPeriod() {
        let periods: [QuotaPeriod] = [
            .fiveHours, .weekly, .billingCycle, .usageCredits, .lasting(seconds: 86_400),
            .limit("Sonnet", .weekly), .limit("Cursor Models", .billingCycle),
        ]

        #expect(periods.map(Format.spanish.name(of:)) == [
            "5 horas", "Semanal", "Ciclo de facturación", "Créditos de uso", "1 día", "Semanal · Sonnet", "Cursor Models",
        ])
        #expect(periods.map(Format.english.name(of:)) == [
            "5 hours", "Weekly", "Billing cycle", "Usage credits", "1 day", "Weekly · Sonnet", "Cursor Models",
        ])
    }

    @Test func aPercentageNamesItsMagnitude() {
        #expect(Format.spanish.name(of: QuotaMagnitude.used) == "usado")
        #expect(Format.spanish.name(of: QuotaMagnitude.remaining) == "restante")
        #expect(Format.english.name(of: QuotaMagnitude.used) == "used")
        #expect(Format.english.name(of: QuotaMagnitude.remaining) == "left")
    }

    /// The Settings line a bug report can paste, from the marketing version
    /// and the build. The literals are the 0.1.1 (3) release, not a formula.
    @Test func theSettingsLineNamesTheVersionAndBuild() {
        #expect(Format.english.appVersion(version: "0.1.1", build: "3") == "Version 0.1.1 (3)")
        #expect(Format.spanish.appVersion(version: "0.1.1", build: "3") == "Versión 0.1.1 (3)")
    }

    /// A missing or blank bundle value is not a version, so the line is left
    /// out instead of showing a placeholder.
    @Test func theSettingsLineIsAbsentWhenABundleValueIsMissing() {
        #expect(Format.english.appVersion(version: nil, build: "3") == nil)
        #expect(Format.english.appVersion(version: "0.1.1", build: nil) == nil)
        #expect(Format.english.appVersion(version: nil, build: nil) == nil)
        #expect(Format.english.appVersion(version: "", build: "3") == nil)
        #expect(Format.english.appVersion(version: "0.1.1", build: "") == nil)
        #expect(Format.english.appVersion(version: "   ", build: "3") == nil)
        #expect(Format.english.appVersion(version: "0.1.1", build: "\n") == nil)
    }

    /// «Cuota» reads as a fee in Spanish, so the Spanish copy says «límite de
    /// uso» instead, as the glossary in `CONTEXT.md` records.
    @Test func theSpanishCopyCallsUsageLimitsLimitesDeUso() throws {
        let path = try #require(#bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "es"))
        let catalog = try #require(NSDictionary(contentsOfFile: path) as? [String: String])

        #expect(!catalog.isEmpty)
        #expect(catalog.filter { $0.value.localizedCaseInsensitiveContains("cuota") }.isEmpty)
        #expect(catalog["Usage limits"] == "Límites de uso")
        #expect(catalog["Usage limit unavailable"] == "Límite no disponible")
    }
}
