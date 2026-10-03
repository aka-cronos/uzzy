import Foundation
import Observation

/// A release version such as "0.1.2", compared number by number, so 0.10.0
/// comes after 0.9.1. A tag's leading "v" is dropped. Anything else that is
/// not dot-separated numbers, e.g. the release candidate "0.2.0-rc.1", is
/// not a version.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    private let numbers: [Int]

    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = (text.hasPrefix("v") ? text.dropFirst() : Substring(text))
            .split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in part.allSatisfy(\.isASCII) ? UInt32(part).map(Int.init) : nil }
        guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
        self.numbers = numbers
    }

    public var description: String {
        numbers.map(String.init).joined(separator: ".")
    }

    /// Missing numbers count as zero: 1.0 equals 1.0.0.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let (left, right) = (lhs.number(at: index), rhs.number(at: index))
            if left != right { return left < right }
        }
        return false
    }

    private func number(at index: Int) -> Int {
        index < numbers.count ? numbers[index] : 0
    }
}

/// Asks GitHub once a day for the latest published release and says when it
/// is newer than this copy. It only notifies: the person downloads and
/// installs the new version by hand. The request carries no token and no
/// identifier, and a failed check is silent until the next one.
@MainActor
@Observable
public final class UpdateChecker {
    /// The newer version to offer, e.g. "0.1.2"; `nil` when this copy is up
    /// to date, checks are off or no check has succeeded yet.
    public private(set) var availableVersion: String?

    /// The latest release that is neither a draft nor a prerelease, so
    /// release candidates are never offered.
    nonisolated static let latestRelease = URL(string: "https://api.github.com/repos/aka-cronos/uzzy/releases/latest")!
    /// Where the browser downloads the latest `Uzzy.dmg`, as uzzy.app's
    /// download button does.
    public nonisolated static let download = URL(string: "https://github.com/aka-cronos/uzzy/releases/latest/download/Uzzy.dmg")!
    nonisolated static let checkInterval: TimeInterval = 24 * 60 * 60

    private let currentVersion: AppVersion?
    private let transport: any HTTPTransport
    private let clock: any WallClock
    private var isEnabled: Bool
    /// The only scheduled check; replacing it cancels the one before.
    @ObservationIgnored private var nextCheck: ScheduledWork? {
        didSet { oldValue?.cancel() }
    }
    @ObservationIgnored private var check: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    /// `currentVersion` is the bundle's `CFBundleShortVersionString`. Without
    /// a readable one there is nothing to compare, so it never checks.
    public init(currentVersion: String?, transport: any HTTPTransport, clock: any WallClock, isEnabled: Bool = true) {
        self.currentVersion = currentVersion.flatMap(AppVersion.init)
        self.transport = transport
        self.clock = clock
        self.isEnabled = isEnabled
    }

    /// Checks now and every 24 hours from then, while checks are on.
    public func start() {
        guard isEnabled, let currentVersion else { return }
        nextCheck = clock.schedule(at: clock.now().addingTimeInterval(Self.checkInterval)) { [weak self] in
            self?.start()
        }
        check = Task { [transport] in
            var request = URLRequest(url: Self.latestRelease)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            // GitHub requires a User-Agent. The default one would add the
            // build and the system's versions.
            request.setValue("Uzzy", forHTTPHeaderField: "User-Agent")
            let result = await transport.send(request)
            guard !Task.isCancelled,
                  case .response(let response) = result, response.status == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: response.body),
                  let latest = AppVersion(release.tagName)
            else { return }
            availableVersion = latest > currentVersion ? latest.description : nil
        }
    }

    /// Turned off, it contacts no one and offers nothing. Turning it on
    /// checks at once.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            start()
        } else {
            nextCheck = nil
            check = nil
            availableVersion = nil
        }
    }

    /// Returns once no check is in flight.
    public func checkFinished() async {
        await check?.value
    }

    private struct Release: Decodable {
        let tagName: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }
    }
}
