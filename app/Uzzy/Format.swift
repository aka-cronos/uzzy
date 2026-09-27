import Foundation
import UzzyCore

/// The app's user-facing text: panel figures in local time, window titles and
/// command names. The UI copy is Spanish.
enum Format {
    private static let locale = Locale(identifier: "es_ES")

    /// The product name, from the bundle's display name so a rename touches only the build settings.
    static let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? ProcessInfo.processInfo.processName
    /// The quit command, in the panel and in the main menu (⌘Q).
    static let quitApp = "Salir de \(appName)"
    /// The Settings window's title and the panel's settings button label.
    static let settings = "Ajustes"
    /// The main menu command that opens Settings (⌘,).
    static let openSettings = "\(settings)…"
    /// The main menu command that closes the front window or the panel (⌘W).
    static let closeWindow = "Cerrar ventana"

    /// E.g. "20.5%": a decimal point and no space before the sign, unlike
    /// the Spanish convention the rest of the copy follows.
    static func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(Locale(identifier: "en_US_POSIX"))))%"
    }

    /// Usage credits spent this month, as Claude shows them: e.g. "53,06 US$
    /// de 40 US$ este mes", or "53,06 US$ este mes" without a monthly limit.
    static func usageCredits(_ spent: Money, limit: Money?) -> String {
        let limitText = limit.map { " de \(money($0))" } ?? ""
        return "\(money(spent))\(limitText) este mes"
    }

    /// In the currency's own format for Spanish; a whole amount drops its
    /// decimals, e.g. "40 US$".
    static func money(_ money: Money) -> String {
        let style = Decimal.FormatStyle.Currency(code: money.currency, locale: locale)
        var amount = money.amount
        var whole = Decimal()
        NSDecimalRound(&whole, &amount, 0, .plain)
        return money.amount.formatted(whole == money.amount ? style.precision(.fractionLength(0)) : style)
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
    }

    static func reset(_ reset: Reset, now: Date) -> String {
        switch reset {
        case .unknown:
            return "Reinicio desconocido"
        case .pendingConfirmation:
            return "Reinicio pendiente de confirmar"
        case .at(let date):
            return "Reinicio: \(dayAndTime(date, now: now)) · en \(countdown(date.timeIntervalSince(now)))"
        }
    }

    /// A card's title as VoiceOver reads it, e.g. "Claude, plan Max", so the
    /// separator the card shows is not read out.
    static func cardTitle(_ provider: String, plan: String?) -> String {
        plan.map { "\(provider), plan \($0)" } ?? provider
    }

    /// The banked resets of an account, spelled out, e.g. "3 restablecimientos
    /// disponibles". «disponible» is allowed here only: it matches Codex's
    /// own "N available".
    static func bankedResets(_ count: Int) -> String {
        count == 1 ? "1 restablecimiento disponible" : "\(count) restablecimientos disponibles"
    }

    /// Where banked resets are used. Uzzy only shows them.
    static func bankedResetsNote(_ count: Int) -> String {
        count == 1 ? "Se usa desde Codex." : "Se usan desde Codex."
    }

    /// E.g. "Hoy, 14:42", so a moment on another day is not mistaken for today.
    static func dayAndTime(_ date: Date, now: Date) -> String {
        "\(day(date, now: now)), \(time(date))"
    }

    private static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Hoy" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Mañana" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    /// The length of a quota period, in its largest whole unit: e.g.
    /// "24 horas" is shown as "1 día", and 5400 s as "90 min".
    static func duration(seconds: Int) -> String {
        func plural(_ count: Int, _ one: String, _ many: String) -> String {
            "\(count) \(count == 1 ? one : many)"
        }
        if seconds > 0, seconds % 86_400 == 0 { return plural(seconds / 86_400, "día", "días") }
        if seconds > 0, seconds % 3_600 == 0 { return plural(seconds / 3_600, "hora", "horas") }
        if seconds > 0, seconds % 60 == 0 { return "\(seconds / 60) min" }
        return "\(seconds) s"
    }

    /// The longest countdown shown, in minutes. Converting a longer interval
    /// to `Int` could trap.
    private static let longestCountdownMinutes = Double(Int32.max)

    /// An interval that is not ahead counts as zero, and a longer one is cut
    /// to `longestCountdownMinutes`, so invalid data never traps.
    private static func countdown(_ seconds: TimeInterval) -> String {
        let minutes = seconds > 0 ? Int(min(seconds / 60, longestCountdownMinutes)) : 0
        let (days, hours, restMinutes) = (minutes / 1440, minutes / 60 % 24, minutes % 60)
        if days > 0 { return "\(days) d \(hours) h" }
        if hours > 0 { return "\(hours) h \(restMinutes) min" }
        return "\(restMinutes) min"
    }
}
