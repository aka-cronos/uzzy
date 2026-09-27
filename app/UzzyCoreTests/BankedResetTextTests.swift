import Testing

/// The banked-reset copy of the Codex card in each language, from the app's
/// formatter, which this target compiles from `Uzzy/Format.swift`.
struct BankedResetTextTests {
    @Test func oneBankedResetIsSpelledOutInTheSingular() {
        #expect(Format.spanish.bankedResets(1) == "1 restablecimiento disponible")
        #expect(Format.spanish.bankedResetsNote(1) == "Se usa desde Codex.")

        #expect(Format.english.bankedResets(1) == "1 reset available")
        #expect(Format.english.bankedResetsNote(1) == "Use it in Codex.")
    }

    @Test(arguments: [3, 12])
    func severalBankedResetsAreSpelledOutInThePlural(count: Int) {
        #expect(Format.spanish.bankedResets(count) == "\(count) restablecimientos disponibles")
        #expect(Format.spanish.bankedResetsNote(count) == "Se usan desde Codex.")

        #expect(Format.english.bankedResets(count) == "\(count) resets available")
        #expect(Format.english.bankedResetsNote(count) == "Use them in Codex.")
    }
}
