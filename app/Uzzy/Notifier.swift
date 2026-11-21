import Foundation
import Observation
import UserNotifications
import UzzyCore

/// Delivers the core's alerts as macOS notifications, and opens the panel
/// when one is clicked. It asks for permission only when the person turns an
/// alert on in Settings, never at launch.
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Whether macOS lets Uzzy notify. `.notDetermined` until the person
    /// first turns an alert on.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    var isDenied: Bool {
        authorization == .denied
    }

    /// Where macOS lets the person turn Uzzy's notifications back on.
    static let systemSettings = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// Runs when the person clicks a delivered notification.
    @ObservationIgnored var openPanel: (@MainActor () -> Void)?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        refreshAuthorization()
    }

    /// Reads whether macOS lets Uzzy notify, which the person may change in
    /// System Settings at any time. Never asks. The completion handlers here
    /// run on a background queue, so they are `@Sendable` and hop to the
    /// main actor. The notifier lives as long as the app.
    func refreshAuthorization() {
        center.getNotificationSettings { @Sendable settings in
            let status = settings.authorizationStatus
            Task { @MainActor in self.authorization = status }
        }
    }

    /// Shows macOS's permission prompt the first time; afterwards macOS
    /// answers with the person's earlier choice without asking.
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in
            Task { @MainActor in self.refreshAuthorization() }
        }
    }

    /// A two-line notification: a title and a body, with no subtitle.
    func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    /// Settings may be in front when an alert fires; it still shows.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run { self.openPanel?() }
    }
}
