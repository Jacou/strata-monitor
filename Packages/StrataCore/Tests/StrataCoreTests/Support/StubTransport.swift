import Foundation
@testable import StrataCore

/// Stands in for URLSession so client and poller tests never touch the network.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private let responder: @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    init(_ responder: @escaping @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)) {
        self.responder = responder
    }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        return try responder(request)
    }
}

extension StubTransport {
    static func responding(
        _ body: String,
        status: Int = 200,
        url: URL = URL(string: "http://192.168.1.10:8081/metrics")!
    ) -> StubTransport {
        StubTransport { _ in (Data(body.utf8), httpResponse(url, status)) }
    }

    static func respondingData(
        _ data: Data,
        status: Int = 200,
        url: URL = URL(string: "http://192.168.1.10:8081/metrics")!
    ) -> StubTransport {
        StubTransport { _ in (data, httpResponse(url, status)) }
    }

    static func failing(_ error: Error) -> StubTransport {
        StubTransport { _ in throw error }
    }

    static func status(_ code: Int, url: URL = URL(string: "http://192.168.1.10:8081/metrics")!) -> StubTransport {
        StubTransport { _ in (Data("{}".utf8), httpResponse(url, code)) }
    }
}

/// A counter a @Sendable responder closure may mutate (Swift 6 forbids capturing a plain var).
final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}

/// Answers /health and /metrics differently — what a real server does.
final class RoutingTransport: HTTPTransport, @unchecked Sendable {
    private let healthBody: String
    private let healthStatus: Int
    private let metricsBody: String
    private let metricsStatus: Int
    private let failure: (any Error)?
    private let fallbackURL = URL(string: "http://192.168.1.10:8081")!

    private(set) var requests: [URLRequest] = []

    init(
        health: String = #"{"status":"ok","model":"strata-model"}"#,
        healthStatus: Int = 200,
        metrics: String = #"{"engine":{"model":"qwen3.8-flash"},"time":1}"#,
        metricsStatus: Int = 200,
        failure: (any Error)? = nil
    ) {
        self.healthBody = health
        self.healthStatus = healthStatus
        self.metricsBody = metrics
        self.metricsStatus = metricsStatus
        self.failure = failure
    }

    var paths: [String] { requests.compactMap { $0.url?.path } }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        let isHealth = request.url?.path.hasSuffix("health") ?? false
        let body = isHealth ? healthBody : metricsBody
        let status = isHealth ? healthStatus : metricsStatus
        return (Data(body.utf8), httpResponse(request.url ?? fallbackURL, status))
    }
}

func httpResponse(_ url: URL, _ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
}
