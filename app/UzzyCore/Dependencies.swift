import Foundation
import Synchronization

// External dependencies of the usage core. They are injected so tests use
// fakes and the app uses thin real implementations.

public struct Session: Sendable, Equatable {
    public let accessToken: String
    /// Account identity; `nil` when it cannot be verified.
    public let accountID: String?
    /// The account's plan as the official app stores it, e.g. `"max"`: the
    /// provider's own identifier, not a name to show. `nil` when the session
    /// holds none, or the provider reports it elsewhere.
    public let plan: String?

    public init(accessToken: String, accountID: String?, plan: String? = nil) {
        self.accessToken = accessToken
        self.accountID = accountID
        self.plan = plan
    }
}

public enum SessionReading: Sendable, Equatable {
    case session(Session)
    case noSession
    /// A session of a kind that has no subscription quotas, e.g. an API key.
    case withoutSubscriptionQuotas
    case accessDenied
    /// The session store could not be read right now.
    case storeUnavailable
    /// The session store was locked by another process.
    case storeBusy
    case unknownFormat
    /// The session is encrypted with a key the user has not let the app
    /// read yet. Nothing was read from the Keychain.
    case needsAccess
}

public protocol SessionReader: Sendable {
    func read() async -> SessionReading
}

/// Whether the user let the app read a provider's encryption key from the
/// Keychain. Withdrawn whenever the provider is turned off.
public protocol AccessConsent: Sendable {
    func isGranted() -> Bool
    func setGranted(_ granted: Bool)
}

/// Consent kept only in memory, given to no one at first.
public final class MemoryAccessConsent: AccessConsent {
    private let granted: Mutex<Bool>

    public init(granted: Bool = false) {
        self.granted = Mutex(granted)
    }

    public func isGranted() -> Bool {
        granted.withLock { $0 }
    }

    public func setGranted(_ granted: Bool) {
        self.granted.withLock { $0 = granted }
    }
}

/// Consent saved in the app's defaults under `key`.
public struct DefaultsAccessConsent: AccessConsent {
    private let key: String

    public init(key: String) {
        self.key = key
    }

    public func isGranted() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    public func setGranted(_ granted: Bool) {
        if granted {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

public enum HTTPResult: Sendable, Equatable {
    case response(HTTPResponse)
    case networkError
    case timeout
    /// The response grew past the byte budget and was dropped before being
    /// decoded.
    case responseTooLarge
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async -> HTTPResult
}

public protocol WallClock: Sendable {
    func now() -> Date
    /// Runs `action` once the clock reaches `deadline`, unless the returned
    /// work is cancelled on the main actor first.
    func schedule(at deadline: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> ScheduledWork
}

/// Work a clock has scheduled. Once cancelled, its action never runs:
/// cancelling never runs it early.
public struct ScheduledWork: Sendable {
    private let onCancel: @Sendable () -> Void

    public init(onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel()
    }
}
