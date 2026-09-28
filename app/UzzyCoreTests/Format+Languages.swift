import Foundation

/// The formatters the text tests use, so they set the language instead of
/// taking the one of the Mac that runs them.
extension Format {
    /// Spanish text and the Spanish region's 24-hour clock.
    static let spanish = Format(locale: Locale(identifier: "es_ES"))
    /// English text and the US region's 12-hour clock.
    static let english = Format(locale: Locale(identifier: "en_US"))
}
