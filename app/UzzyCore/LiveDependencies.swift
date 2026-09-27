import Foundation

/// HTTP transport over `URLSession`. Each request is limited to 15 s and
/// each response to `byteBudget`, and nothing is cached or stored: no
/// cookies, no credentials, no responses. Redirects are not followed, so
/// only the requested host is contacted.
public struct URLSessionTransport: HTTPTransport {
    /// The most bytes a response may have: 1 MiB. The sanitized sample
    /// responses (`Samples`) take under 2 KB each, so the budget leaves room
    /// for hundreds of times more limits than any known account has, while
    /// capping what a faulty or hostile answer can make the app download,
    /// hold and decode.
    static let byteBudget = 1_048_576
    private static let timeout: TimeInterval = 15

    private let session: URLSession

    public init() {
        self.init(timeout: Self.timeout)
    }

    /// `protocolClasses` lets tests answer requests without the network.
    init(timeout: TimeInterval, protocolClasses: [AnyClass]? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        if let protocolClasses {
            configuration.protocolClasses = protocolClasses
        }
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async -> HTTPResult {
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
            guard let response = response as? HTTPURLResponse else { return .networkError }
            // The announced length is only a hint: the bytes received are
            // counted either way, since it can be missing or wrong.
            guard response.expectedContentLength <= Self.byteBudget else {
                bytes.task.cancel()
                return .responseTooLarge
            }
            var body = Data(capacity: Int(max(0, response.expectedContentLength)))
            for try await byte in bytes {
                guard body.count < Self.byteBudget else {
                    bytes.task.cancel()
                    return .responseTooLarge
                }
                body.append(byte)
            }
            var headers: [String: String] = [:]
            for case let (name as String, value as String) in response.allHeaderFields {
                headers[name] = value
            }
            return .response(HTTPResponse(status: response.statusCode, headers: headers, body: body))
        } catch let error as URLError where error.code == .timedOut {
            return .timeout
        } catch {
            return .networkError
        }
    }
}

/// Hands a redirect back to the caller as its 3xx response instead of following it.
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

public struct SystemClock: WallClock {
    public init() {}

    public func now() -> Date {
        Date()
    }

    public func schedule(at deadline: Date, _ action: @escaping @MainActor @Sendable () -> Void) -> ScheduledWork {
        let sleeper = Task { @MainActor in
            // A cancelled sleep ends early and throws. The check after it
            // runs on the main actor, like `cancel()`, so a cancellation that
            // lands once the sleep is over still stops the action.
            guard (try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))) != nil,
                  !Task.isCancelled
            else { return }
            action()
        }
        return ScheduledWork(onCancel: { sleeper.cancel() })
    }
}
