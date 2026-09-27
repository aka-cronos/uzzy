import Testing

/// A card's title as VoiceOver reads it in each language, from the app's
/// formatter, which this target compiles from `Uzzy/Format.swift`.
struct PlanTextTests {
    @Test func theTitleNamesThePlanWithoutTheSeparatorTheCardShows() {
        #expect(Format.spanish.cardTitle("Claude", plan: "Max") == "Claude, plan Max")
        #expect(Format.spanish.cardTitle("Cursor", plan: "Pro+") == "Cursor, plan Pro+")

        #expect(Format.english.cardTitle("Claude", plan: "Max") == "Claude, Max plan")
        #expect(Format.english.cardTitle("Cursor", plan: "Pro+") == "Cursor, Pro+ plan")
    }

    @Test func withoutAPlanTheTitleIsTheProviderAlone() {
        #expect(Format.spanish.cardTitle("Codex", plan: nil) == "Codex")
        #expect(Format.english.cardTitle("Codex", plan: nil) == "Codex")
    }
}
