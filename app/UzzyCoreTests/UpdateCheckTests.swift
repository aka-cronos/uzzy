import Foundation
import Testing
import UzzyCore

/// When Uzzy asks GitHub for the latest release, and which answers make it
/// offer an update.
@MainActor
struct UpdateCheckTests {
    let clock = ManualClock(Samples.readingMoment)
    let transport = SingleAnswerTransport(.latestRelease(tag: "v0.1.2"))
    let checkInterval: TimeInterval = 24 * 60 * 60

    func checker(currentVersion: String? = "0.1.1", isEnabled: Bool = true) -> UpdateChecker {
        UpdateChecker(currentVersion: currentVersion, transport: transport, clock: clock, isEnabled: isEnabled)
    }

    func requestCount() async -> Int {
        await transport.requests.count
    }

    @Test func aNewerReleaseIsOffered() async {
        let updates = checker()

        updates.start()
        await updates.checkFinished()

        #expect(updates.availableVersion == "0.1.2")
    }

    @Test(arguments: ["v0.1.1", "v0.1.0", "v0.1"])
    func aReleaseThatIsNotNewerIsNotOffered(tag: String) async {
        await transport.answer(with: .latestRelease(tag: tag))
        let updates = checker()

        updates.start()
        await updates.checkFinished()

        #expect(updates.availableVersion == nil)
    }

    @Test(arguments: ["v0.2.0-rc.1", "latest", "", "v0..2", "v0.2.x"])
    func aTagThatIsNotAVersionIsNotOffered(tag: String) async {
        await transport.answer(with: .latestRelease(tag: tag))
        let updates = checker()

        updates.start()
        await updates.checkFinished()

        #expect(updates.availableVersion == nil)
    }

    @Test(arguments: [HTTPResult.networkError, .timeout, .responseTooLarge, .status(403), .status(404), .json("{}"), .json("not json")])
    func aFailedCheckOffersNothing(result: HTTPResult) async {
        await transport.answer(with: result)
        let updates = checker()

        updates.start()
        await updates.checkFinished()

        #expect(updates.availableVersion == nil)
    }

    @Test func aFailedCheckKeepsTheUpdateAlreadyFound() async {
        let updates = checker()
        updates.start()
        await updates.checkFinished()

        await transport.answer(with: .networkError)
        clock.advance(by: checkInterval)
        await updates.checkFinished()

        #expect(await requestCount() == 2)
        #expect(updates.availableVersion == "0.1.2")
    }

    @Test func itChecksAgainEveryDay() async {
        await transport.answer(with: .latestRelease(tag: "v0.1.1"))
        let updates = checker()
        updates.start()
        await updates.checkFinished()

        clock.advance(by: checkInterval - 1)
        await updates.checkFinished()
        #expect(await requestCount() == 1)

        await transport.answer(with: .latestRelease(tag: "v0.2.0"))
        clock.advance(by: 1)
        await updates.checkFinished()
        #expect(await requestCount() == 2)
        #expect(updates.availableVersion == "0.2.0")

        clock.advance(by: checkInterval)
        await updates.checkFinished()
        #expect(await requestCount() == 3)
    }

    @Test func turnedOffItNeverAsks() async {
        let updates = checker(isEnabled: false)

        updates.start()
        await updates.checkFinished()
        clock.advance(by: checkInterval)
        await updates.checkFinished()

        #expect(await requestCount() == 0)
        #expect(updates.availableVersion == nil)
    }

    @Test func turningItOffStopsCheckingAndWithdrawsTheUpdate() async {
        let updates = checker()
        updates.start()
        await updates.checkFinished()

        updates.setEnabled(false)
        clock.advance(by: checkInterval)
        await updates.checkFinished()

        #expect(await requestCount() == 1)
        #expect(updates.availableVersion == nil)
        #expect(clock.scheduledDeadlines.isEmpty)
    }

    @Test func turningItOnChecksAtOnce() async {
        let updates = checker(isEnabled: false)
        updates.start()

        updates.setEnabled(true)
        await updates.checkFinished()

        #expect(await requestCount() == 1)
        #expect(updates.availableVersion == "0.1.2")
    }

    @Test(arguments: [String?.none, "", "dev"])
    func withoutAVersionOfItsOwnItNeverAsks(currentVersion: String?) async {
        let updates = checker(currentVersion: currentVersion)

        updates.start()
        await updates.checkFinished()

        #expect(await requestCount() == 0)
        #expect(clock.scheduledDeadlines.isEmpty)
    }

    /// The request is what fetching the release needs and nothing else: no
    /// token, no cookie and no identifier.
    @Test func theRequestCarriesNothingAboutThePerson() async throws {
        let updates = checker()

        updates.start()
        await updates.checkFinished()

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/aka-cronos/uzzy/releases/latest")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.allHTTPHeaderFields == ["Accept": "application/vnd.github+json", "User-Agent": "Uzzy"])
    }

    @Test func versionsCompareNumberByNumber() throws {
        let version = { (text: String) in try #require(AppVersion(text)) }

        #expect(try version("0.10.0") > version("0.9.1"))
        #expect(try version("1.0") == version("1.0.0"))
        #expect(try version("v1.2.3") == version("1.2.3"))
        #expect(try version("1.0.1") > version("1"))
        #expect(try version("v0.1.2").description == "0.1.2")
    }
}
