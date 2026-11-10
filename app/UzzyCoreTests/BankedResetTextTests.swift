import Testing

/// The banked-reset copy of the Codex card in each language, from the app's
/// formatter, which this target compiles from `Uzzy/Format.swift`.
struct BankedResetTextTests {
    @Test func oneBankedResetIsSpelledOutInTheSingular() {
        #expect(Format.spanish.bankedResets(1) == "1 restablecimiento disponible")
        #expect(Format.spanish.bankedResetsNote(1, provider: .codex) == "Se usa desde Codex.")

        #expect(Format.english.bankedResets(1) == "1 reset available")
        #expect(Format.english.bankedResetsNote(1, provider: .codex) == "Use it in Codex.")
    }

    @Test func claudeNamesItsOwnAppInBothLanguages() {
        #expect(Format.spanish.bankedResetsNote(1, provider: .claude) == "Se usa desde Claude.")
        #expect(Format.spanish.bankedResetsNote(3, provider: .claude) == "Se usan desde Claude.")
        #expect(Format.english.bankedResetsNote(1, provider: .claude) == "Use it in Claude.")
        #expect(Format.english.bankedResetsNote(3, provider: .claude) == "Use them in Claude.")
    }

    @Test(arguments: [3, 12])
    func severalBankedResetsAreSpelledOutInThePlural(count: Int) {
        #expect(Format.spanish.bankedResets(count) == "\(count) restablecimientos disponibles")
        #expect(Format.spanish.bankedResetsNote(count, provider: .codex) == "Se usan desde Codex.")

        #expect(Format.english.bankedResets(count) == "\(count) resets available")
        #expect(Format.english.bankedResetsNote(count, provider: .codex) == "Use them in Codex.")
    }
}
