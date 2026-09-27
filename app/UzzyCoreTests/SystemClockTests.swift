import Foundation
import Testing
import UzzyCore

/// The real clock's scheduled work, which the panel cancels once it is no
/// longer needed.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SystemClockTests {
    let clock = SystemClock()

    @Test func workDueNowRuns() async throws {
        let ran = Flag()

        _ = clock.schedule(at: clock.now()) { ran.isSet = true }

        for _ in 0..<100 where !ran.isSet {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(ran.isSet)
    }

    @Test func cancellingNeverRunsTheWorkEarly() async throws {
        let ran = Flag()

        clock.schedule(at: clock.now().addingTimeInterval(60 * 60)) { ran.isSet = true }.cancel()

        try await Task.sleep(for: .milliseconds(200))
        #expect(!ran.isSet)
    }

    @Test func cancellingWorkAlreadyDueStillStopsIt() async throws {
        let ran = Flag()

        clock.schedule(at: clock.now()) { ran.isSet = true }.cancel()

        try await Task.sleep(for: .milliseconds(200))
        #expect(!ran.isSet)
    }
}

@MainActor
private final class Flag {
    var isSet = false
}
