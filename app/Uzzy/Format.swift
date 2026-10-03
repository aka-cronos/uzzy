import Foundation
import UzzyCore

/// The app's user-facing text: panel figures in local time, window titles and
/// command names, in English or Spanish from `Localizable.xcstrings`.
struct Format {
    /// Its language picks the copy's language, and its region formats dates,
    /// times and money.
    let locale: Locale

    /// By default, the current locale: the language the app runs in plus the
    /// system region, e.g. "en_ES", with the person's 12/24-hour choice. It
    /// follows a change of region while the app runs.
    init(locale: Locale = .autoupdatingCurrent) {
        self.locale = locale
    }

    /// The text in the app's language and the system region.
    static let current = Format()

    /// The bundle that holds the catalog: the app's, or the tests' when they
    /// compile this file.
    private static let bundle = #bundle

    /// The product name, from the bundle's display name so a rename touches only the build settings.
    static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? ProcessInfo.processInfo.processName
    /// The quit command, in the panel and in the main menu (⌘Q).
    var quitApp: String { text("Quit \(Self.appName)") }
    /// The Settings window's title and the panel's settings button label.
    var settings: String { text("Settings") }
    /// The main menu command that opens Settings (⌘,).
    var openSettings: String { "\(settings)…" }
    /// The main menu's File menu.
    var fileMenu: String { text("File") }
    /// The main menu command that closes the front window or the panel (⌘W).
    var closeWindow: String { text("Close Window") }

    /// The line at the bottom of Settings, e.g. "Version 0.1.1 (3)". The
    /// caller passes `CFBundleShortVersionString` and `CFBundleVersion`.
    /// `nil` when either is missing or only whitespace, so the line never
    /// invents a version.
    func appVersion(version: String?, build: String?) -> String? {
        let version = version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let build = build?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !version.isEmpty, !build.isEmpty else { return nil }
        return text("Version \(version) (\(build))")
    }

    /// E.g. "20.5%" in every language: a decimal point and no space before
    /// the sign, unlike the Spanish convention.
    func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))))%"
    }

    /// Usage credits spent this month, as Claude shows them: e.g. "$53.06 of
    /// $40 this month", or "$53.06 this month" without a monthly limit.
    func usageCredits(_ spent: Money, limit: Money?) -> String {
        guard let limit else { return text("\(money(spent)) this month") }
        return text("\(money(spent)) of \(money(limit)) this month")
    }

    /// In the currency's own format for the region; a whole amount drops its
    /// decimals, e.g. "$40".
    func money(_ money: Money) -> String {
        let style = Decimal.FormatStyle.Currency(code: money.currency, locale: locale)
        var amount = money.amount
        var whole = Decimal()
        NSDecimalRound(&whole, &amount, 0, .plain)
        return money.amount.formatted(whole == money.amount ? style.precision(.fractionLength(0)) : style)
    }

    /// In the region's hour cycle: e.g. "2:42 PM" in the US; a 24-hour clock
    /// pads the hour, e.g. "09:05".
    func time(_ date: Date) -> String {
        let hour: Date.FormatStyle.Symbol.Hour = switch locale.hourCycle {
        case .zeroToEleven, .oneToTwelve: .defaultDigits(amPM: .abbreviated)
        case .zeroToTwentyThree, .oneToTwentyFour: .twoDigits(amPM: .omitted)
        @unknown default: .defaultDigits(amPM: .abbreviated)
        }
        return date.formatted(.dateTime.hour(hour).minute(.twoDigits).locale(locale))
    }

    func reset(_ reset: Reset, now: Date) -> String {
        switch reset {
        case .unknown:
            text("Reset unknown")
        case .pendingConfirmation:
            text("Reset pending confirmation")
        case .at(let date):
            text("Resets \(dayAndTime(date, now: now)) · in \(countdown(date.timeIntervalSince(now)))")
        }
    }

    /// A quota's name, by its period: e.g. "Weekly", or "Weekly · Sonnet" for
    /// a limit the provider names. A limit over the billing cycle, e.g.
    /// "Cursor Models", goes by its name alone.
    func name(of period: QuotaPeriod) -> String {
        switch period {
        case .fiveHours: text("5 hours")
        case .weekly: text("Weekly")
        case .lasting(let seconds): duration(seconds: seconds)
        case .billingCycle: text("Billing cycle")
        case .usageCredits: text("Usage credits")
        case .limit(let name, .billingCycle): name
        case .limit(let name, let period): "\(self.name(of: period)) · \(name)"
        }
    }

    /// The word after a card's percentage, and the Settings choice between
    /// them.
    func name(of magnitude: QuotaMagnitude) -> String {
        switch magnitude {
        case .used: text("used")
        case .remaining: text("left")
        }
    }

    /// A card's title as VoiceOver reads it, e.g. "Claude, Max plan", so the
    /// separator the card shows is not read out.
    func cardTitle(_ provider: String, plan: String?) -> String {
        plan.map { text("\(provider), \($0) plan") } ?? provider
    }

    /// The banked resets of an account, spelled out, e.g. "3 resets
    /// available". The Spanish «disponible» is allowed here only: it matches
    /// Codex's own "N available".
    func bankedResets(_ count: Int) -> String {
        text("\(count) resets available")
    }

    /// Where banked resets are used. Uzzy only shows them. Two strings, not a
    /// plural variation: the catalog allows one only when the text shows the
    /// number.
    func bankedResetsNote(_ count: Int) -> String {
        count == 1 ? text("Use it in Codex.") : text("Use them in Codex.")
    }

    /// E.g. "today, 14:42", so a moment on another day is not mistaken for
    /// today. It always follows other words, so English starts in lowercase.
    func dayAndTime(_ date: Date, now: Date) -> String {
        "\(day(date, now: now)), \(time(date))"
    }

    private func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return text("today") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return text("tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    /// The length of a quota period, in its largest whole unit: e.g.
    /// "24 hours" is shown as "1 day", and 5400 s as "90 min".
    func duration(seconds: Int) -> String {
        if seconds > 0, seconds % 86_400 == 0 { return text("\(seconds / 86_400) days") }
        if seconds > 0, seconds % 3_600 == 0 { return text("\(seconds / 3_600) hours") }
        if seconds > 0, seconds % 60 == 0 { return text("\(seconds / 60) min") }
        return text("\(seconds) s")
    }

    /// The longest countdown shown, in minutes. Converting a longer interval
    /// to `Int` could trap.
    private static let longestCountdownMinutes = Double(Int32.max)

    /// An interval that is not ahead counts as zero, and a longer one is cut
    /// to `longestCountdownMinutes`, so invalid data never traps.
    private func countdown(_ seconds: TimeInterval) -> String {
        let minutes = seconds > 0 ? Int(min(seconds / 60, Self.longestCountdownMinutes)) : 0
        let (days, hours, restMinutes) = (minutes / 1440, minutes / 60 % 24, minutes % 60)
        if days > 0 { return text("\(days) d \(hours) h") }
        if hours > 0 { return text("\(hours) h \(restMinutes) min") }
        return text("\(restMinutes) min")
    }

    /// `value` from the catalog, in the language of `locale`. A language
    /// the catalog lacks falls back to English.
    private func text(_ value: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(value, locale: locale, bundle: .atURL(Self.bundle.bundleURL)))
    }
}
