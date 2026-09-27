import Foundation
import Testing
@testable import UzzyCore

/// The real transport, answered by a local stand-in for the provider: no
/// network and no accounts.
@Suite(.timeLimit(.minutes(1)))
struct URLSessionTransportTests {
    /// The largest response a provider may send: 1 MiB, as agreed on the
    /// issue, so it is written out rather than read from the transport.
    let budget = 1_048_576
    let transport = URLSessionTransport(timeout: 15, protocolClasses: [StandInProvider.self])

    @Test func aResponseUpToTheByteBudgetArrivesWhole() async {
        let result = await transport.send(StandInProvider.body(bytes: budget))

        guard case .response(let response) = result else {
            Issue.record("Expected a response, got \(result)")
            return
        }
        #expect(response.status == 200)
        #expect(response.body.count == budget)
    }

    @Test func aResponseOverTheByteBudgetIsDroppedWithoutAContentLength() async {
        #expect(await transport.send(StandInProvider.body(bytes: budget + 1)) == .responseTooLarge)
    }

    @Test func aResponseOverTheByteBudgetIsDroppedWhenItsContentLengthUnderstatesIt() async {
        #expect(await transport.send(StandInProvider.body(bytes: 4 * budget, contentLength: 100)) == .responseTooLarge)
    }

    @Test func aResponseThatAnnouncesMoreThanTheByteBudgetIsDropped() async {
        #expect(await transport.send(StandInProvider.body(bytes: 100, contentLength: budget + 1)) == .responseTooLarge)
    }

    @Test func aRedirectIsReturnedInsteadOfFollowed() async {
        let result = await transport.send(StandInProvider.redirect)

        guard case .response(let response) = result else {
            Issue.record("Expected the redirect, got \(result)")
            return
        }
        #expect(response.status == 302)
    }

    @Test func aProviderThatDoesNotAnswerInTimeTimesOut() async {
        let transport = URLSessionTransport(timeout: 0.2, protocolClasses: [StandInProvider.self])

        #expect(await transport.send(StandInProvider.silent) == .timeout)
    }

    @Test func aCancelledQueryEndsWithoutWaitingForTheProvider() async {
        let query = Task { await transport.send(StandInProvider.silent) }

        try? await Task.sleep(for: .milliseconds(100))
        query.cancel()

        #expect(await query.value == .networkError)
    }

    @Test func aQueryCancelledWhileItsBodyArrivesEndsWithoutWaitingForTheRest() async {
        let query = Task { await transport.send(StandInProvider.stalled) }

        try? await Task.sleep(for: .milliseconds(100))
        query.cancel()

        #expect(await query.value == .networkError)
    }
}

/// Answers each request as its URL says: `/body` with `bytes` spaces and an
/// optional `Content-Length`, `/redirect` with a 302, `/stalled` with the
/// start of a body that never ends, and `/silent` never.
private final class StandInProvider: URLProtocol, @unchecked Sendable {
    static func body(bytes: Int, contentLength: Int? = nil) -> URLRequest {
        var components = URLComponents(string: "https://provider.test/body")!
        components.queryItems = [URLQueryItem(name: "bytes", value: String(bytes))]
            + (contentLength.map { [URLQueryItem(name: "contentLength", value: String($0))] } ?? [])
        return URLRequest(url: components.url!)
    }

    static let redirect = URLRequest(url: URL(string: "https://provider.test/redirect")!)
    static let silent = URLRequest(url: URL(string: "https://provider.test/silent")!)
    static let stalled = URLRequest(url: URL(string: "https://provider.test/stalled")!)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let client, let url = request.url else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func number(_ name: String) -> Int? { items.first { $0.name == name }?.value.flatMap(Int.init) }

        switch url.path {
        case "/body":
            let headers = number("contentLength").map { ["Content-Length": String($0)] } ?? [:]
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            var remaining = number("bytes") ?? 0
            while remaining > 0 {
                let chunk = min(remaining, 64 * 1024)
                client.urlProtocol(self, didLoad: Data(repeating: 0x20, count: chunk))
                remaining -= chunk
            }
            client.urlProtocolDidFinishLoading(self)
        case "/redirect":
            let target = URL(string: "https://elsewhere.test/body?bytes=1")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            // If the redirect is declined, the 302 itself is the answer.
            client.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        case "/stalled":
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: Data(#"{"five_hour": "#.utf8))
        default:
            break
        }
    }

    override func stopLoading() {}
}
