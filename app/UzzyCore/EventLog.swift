import Foundation
import os

/// Something worth logging. It holds only categories and codes, so a log
/// can never carry a token, an identifier or a raw response.
public enum LogEvent: Sendable, Equatable {
    case queryFailed(Provider, Failure)
}

public protocol EventLog: Sendable {
    func record(_ event: LogEvent)
}

/// Logs to the unified system log (`log show`).
public struct SystemLog: EventLog {
    private static let logger = Logger(subsystem: "com.akacronos.Uzzy", category: "usage")

    public init() {}

    public func record(_ event: LogEvent) {
        switch event {
        case .queryFailed(let provider, let failure):
            Self.logger.notice("Query failed: \(String(describing: provider), privacy: .public) \(String(describing: failure), privacy: .public)")
        }
    }
}
