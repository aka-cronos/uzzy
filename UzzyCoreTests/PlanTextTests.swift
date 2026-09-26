import Testing

/// A card's title as VoiceOver reads it, from the app's formatter, which
/// this target compiles from `Uzzy/Format.swift`.
struct PlanTextTests {
    @Test func theTitleNamesThePlanWithoutTheSeparatorTheCardShows() {
        #expect(Format.cardTitle("Claude", plan: "Max") == "Claude, plan Max")
        #expect(Format.cardTitle("Cursor", plan: "Pro+") == "Cursor, plan Pro+")
    }

    @Test func withoutAPlanTheTitleIsTheProviderAlone() {
        #expect(Format.cardTitle("Codex", plan: nil) == "Codex")
    }
}
