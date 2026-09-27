import Testing

/// The banked-reset copy of the Codex card, from the app's formatter, which
/// this target compiles from `Uzzy/Format.swift`.
struct BankedResetTextTests {
    @Test func oneBankedResetIsSpelledOutInTheSingular() {
        #expect(Format.bankedResets(1) == "1 restablecimiento disponible")
        #expect(Format.bankedResetsNote(1) == "Se usa desde Codex.")
    }

    @Test(arguments: [3, 12])
    func severalBankedResetsAreSpelledOutInThePlural(count: Int) {
        #expect(Format.bankedResets(count) == "\(count) restablecimientos disponibles")
        #expect(Format.bankedResetsNote(count) == "Se usan desde Codex.")
    }
}
