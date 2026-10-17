import XCTest
@testable import StrataCore

final class StrataClientTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.10:8081")!

    // MARK: - request shape

    func testMetricsRequest() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let client = StrataClient(baseURL: base, transport: transport)
        _ = try await client.metrics()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/metrics")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.timeoutInterval, StrataClient.defaultTimeout)
    }

    func testMetricsAllRequestsQuery() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let client = StrataClient(baseURL: base, transport: transport)
        _ = try await client.metrics(allRequests: true)

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/metrics")
        XCTAssertEqual(queryItems(of: transport.requests.first), [URLQueryItem(name: "requests", value: "all")])
    }

    func testAPIKeyHeader() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let client = StrataClient(baseURL: base, apiKey: "  secret  ", transport: transport)
        _ = try await client.metrics()
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer secret")
    }

    func testEmptyAPIKeySendsNoHeader() async throws {
        let transport = StubTransport.responding(#"{"time":1}"#)
        let client = StrataClient(baseURL: base, apiKey: "   ", transport: transport)
        _ = try await client.metrics()
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testHealthRequest() async throws {
        let transport = StubTransport.responding(#"{"status":"ok"}"#, url: URL(string: "http://192.168.1.10:8081/health")!)
        let client = StrataClient(baseURL: base, transport: transport)
        let health = try await client.health()
        XCTAssertEqual(health.status, "ok")
        XCTAssertEqual(transport.requests.first?.url?.path, "/health")
    }

    func testBaseURLVariants() {
        func path(_ baseString: String) -> String? {
            StrataClient(baseURL: URL(string: baseString)!).request(path: "metrics")?.url?.absoluteString
        }
        XCTAssertEqual(path("http://192.168.1.10:8081"), "http://192.168.1.10:8081/metrics")
        XCTAssertEqual(path("http://192.168.1.10:8081/"), "http://192.168.1.10:8081/metrics")
        XCTAssertEqual(path("http://192.168.1.10:8081/strata"), "http://192.168.1.10:8081/strata/metrics")
        XCTAssertEqual(path("http://192.168.1.10:8081/strata/"), "http://192.168.1.10:8081/strata/metrics")
        XCTAssertEqual(path("http://192.168.1.10:8081/metrics"), "http://192.168.1.10:8081/metrics/metrics")
    }

    // MARK: - decoding real bodies

    func testMetricsDecodesTheFixture() async throws {
        let data = try Fixtures.data("metrics_idle", testClass: type(of: self))
        let transport = StubTransport.respondingData(data)
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)
        let metrics = try await client.metrics()
        XCTAssertEqual(metrics.requests?.count, 12)
        XCTAssertEqual(metrics.engine?.model, "qwen3.8-flash-next-iq3_xxs")
    }

    func testPartialBodyStillDecodes() async throws {
        let transport = StubTransport.responding(#"{"live": {"state": "generating", "tok_s": 91.4}}"#)
        let client = StrataClient(baseURL: base, transport: transport)
        let metrics = try await client.metrics()
        XCTAssertEqual(metrics.live?.state, .generating)
        XCTAssertEqual(metrics.live?.tokS, 91.4)
        XCTAssertNil(metrics.hardware)
    }

    // MARK: - typed errors

    func testUnauthorized() async {
        let client = StrataClient(baseURL: base, transport: StubTransport.status(401))
        await XCTAssertThrowsErrorAsync(try await client.metrics()) { error in
            XCTAssertEqual(error as? StrataError, .unauthorized)
        }
    }

    func testOtherHTTPStatus() async {
        let client = StrataClient(baseURL: base, transport: StubTransport.status(503))
        await XCTAssertThrowsErrorAsync(try await client.metrics()) { error in
            XCTAssertEqual(error as? StrataError, .http(503))
        }
    }

    func testTransportFailureIsUnreachable() async {
        let client = StrataClient(baseURL: base, transport: StubTransport.failing(URLError(.timedOut)))
        await XCTAssertThrowsErrorAsync(try await client.metrics()) { error in
            XCTAssertEqual(error as? StrataError, .unreachable)
        }
    }

    func testUnknownTransportFailureIsUnreachable() async {
        struct Boom: Error {}
        let client = StrataClient(baseURL: base, transport: StubTransport.failing(Boom()))
        await XCTAssertThrowsErrorAsync(try await client.metrics()) { error in
            XCTAssertEqual(error as? StrataError, .unreachable)
        }
    }

    func testUndecodableBodyIsDecodingError() async {
        let client = StrataClient(baseURL: base, transport: StubTransport.responding("<html>nope</html>"))
        await XCTAssertThrowsErrorAsync(try await client.metrics()) { error in
            guard case .some(.decoding(let detail)) = error as? StrataError else {
                return XCTFail("expected .decoding, got \(error)")
            }
            XCTAssertFalse(detail.isEmpty)
        }
    }

    func testBaseURLWithoutAHostBuildsNoRequest() {
        let client = StrataClient(baseURL: URL(string: "http://192.168.1.10:8081")!)
        XCTAssertNotNil(client.request(path: "metrics"))
    }

    // MARK: - /config

    func testConfigRequestIsAnAuthenticatedGET() async throws {
        let data = try Fixtures.data("config", testClass: type(of: self))
        let transport = StubTransport.respondingData(data, url: URL(string: "http://192.168.1.10:8081/config")!)
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)
        let config = try await client.config()

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/config")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(config.keys?.count, 15)
    }

    func testConfigRequestSendsNoKeyWhenThereIsNone() async throws {
        let transport = StubTransport.responding(#"{"file":"f","keys":[]}"#, url: URL(string: "http://192.168.1.10:8081/config")!)
        _ = try await StrataClient(baseURL: base, transport: transport).config()
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testConfigPostBodyHeadersAndMethod() async throws {
        let transport = StubTransport.responding(#"{"changed":["top_k"],"file":"f"}"#, url: URL(string: "http://192.168.1.10:8081/config")!)
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)
        let reply = try await client.updateConfig(["sampling.top_k": .number(40), "lazy_load": .null])

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/config")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        // A JSON object's key order is not fixed, so read the body back rather than match the text.
        let body = try JSONDecoder().decode(ConfigRequest.self, from: try XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.set, ["sampling.top_k": .number(40), "lazy_load": .null])
        XCTAssertEqual(reply.changed, ["top_k"])
    }

    /// A rejected value comes back with the server's own words, which is what the screen shows.
    func testConfigPostSurfacesTheServersMessage() async {
        let body = #"{"error":{"type":"invalid_request_error","message":"'top_k' must be between 1 and 64"}}"#
        let transport = StubTransport.responding(body, status: 400, url: URL(string: "http://192.168.1.10:8081/config")!)
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)

        await XCTAssertThrowsErrorAsync(try await client.updateConfig(["top_k": .number(999)])) { error in
            XCTAssertEqual(error as? StrataServerError,
                           StrataServerError(message: "'top_k' must be between 1 and 64", statusCode: 400))
        }
    }

    func testConfigPostWithoutAnErrorMessageFallsBackToTheStatus() async {
        let transport = StubTransport.status(500, url: URL(string: "http://192.168.1.10:8081/config")!)
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.updateConfig(["top_k": .number(1)])) { error in
            XCTAssertEqual(error as? StrataError, .http(500))
        }
    }

    func testConfigPostUnauthorized() async {
        let transport = StubTransport.status(401, url: URL(string: "http://192.168.1.10:8081/config")!)
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.updateConfig(["top_k": .number(1)])) { error in
            XCTAssertEqual(error as? StrataError, .unauthorized)
        }
    }

    func testConfigPostTransportFailureIsUnreachable() async {
        let transport = StubTransport.failing(URLError(.timedOut))
        let client = StrataClient(baseURL: base, apiKey: "k", transport: transport)
        await XCTAssertThrowsErrorAsync(try await client.updateConfig(["top_k": .number(1)])) { error in
            XCTAssertEqual(error as? StrataError, .unreachable)
        }
    }
}

/// XCTest's XCTAssertThrowsError does not await, so async tests use this.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (_ error: any Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
    } catch {
        errorHandler(error)
        return
    }
    XCTFail("expected a thrown error")
}

func queryItems(of request: URLRequest?) -> [URLQueryItem]? {
    guard let url = request?.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
}
