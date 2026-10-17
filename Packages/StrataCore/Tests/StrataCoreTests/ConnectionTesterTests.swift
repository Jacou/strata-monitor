import XCTest
@testable import StrataCore

@MainActor
final class ConnectionTesterTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.10:8081")!

    private func client(_ transport: RoutingTransport) -> StrataClient {
        StrataClient(baseURL: base, apiKey: "k", transport: transport)
    }

    func testHappyPath() async {
        let transport = RoutingTransport()
        let tester = ConnectionTester()
        XCTAssertEqual(tester.state, .idle)
        XCTAssertEqual(tester.state.text, "")

        await tester.run(client: client(transport))

        XCTAssertEqual(tester.state, .ok(model: "qwen3.8-flash"))
        XCTAssertEqual(tester.state.text, "✓ qwen3.8-flash")
        XCTAssertTrue(tester.state.isOK)
        XCTAssertEqual(transport.paths, ["/health", "/metrics"], "health first, then metrics")
    }

    func testModelFallsBackToHealthWhenMetricsHasNoEngine() async {
        let transport = RoutingTransport(metrics: #"{"time":1}"#)
        let tester = ConnectionTester()
        await tester.run(client: client(transport))
        XCTAssertEqual(tester.state, .ok(model: "strata-model"))
    }

    func testMissingAPIKeyIsSaidInPlainWords() async {
        let transport = RoutingTransport(metricsStatus: 401)
        let tester = ConnectionTester()
        await tester.run(client: client(transport))
        XCTAssertEqual(tester.state, .failed("Wrong or missing API key"))
        XCTAssertEqual(tester.state.text, "Wrong or missing API key")
        XCTAssertFalse(tester.state.isOK)
    }

    func testUnreachableServerStopsAfterHealth() async {
        let transport = RoutingTransport(failure: URLError(.cannotConnectToHost))
        let tester = ConnectionTester()
        await tester.run(client: client(transport))
        XCTAssertEqual(tester.state, .failed(StrataError.unreachable.plainWords))
        XCTAssertEqual(transport.requests.count, 1, "no point asking /metrics after /health failed")
    }

    func testHTTPError() async {
        let transport = RoutingTransport(healthStatus: 500)
        let tester = ConnectionTester()
        await tester.run(client: client(transport))
        XCTAssertEqual(tester.state, .failed("Server replied HTTP 500"))
    }

    func testUndecodableBody() async {
        let transport = RoutingTransport(metrics: "<html>nope</html>")
        let tester = ConnectionTester()
        await tester.run(client: client(transport))
        XCTAssertEqual(tester.state, .failed(StrataError.decoding("").plainWords))
    }

    func testLocalFailureAndReset() {
        let tester = ConnectionTester()
        tester.fail("Fix the server address first")
        XCTAssertEqual(tester.state, .failed("Fix the server address first"))
        tester.reset()
        XCTAssertEqual(tester.state, .idle)
    }

    func testPlainWordsCoverEveryError() {
        XCTAssertEqual(StrataError.unauthorized.plainWords, "Wrong or missing API key")
        XCTAssertEqual(StrataError.http(404).plainWords, "Server replied HTTP 404")
        XCTAssertFalse(StrataError.unreachable.plainWords.isEmpty)
        XCTAssertFalse(StrataError.decoding("boom").plainWords.isEmpty)
        XCTAssertFalse(StrataError.decoding("boom").plainWords.contains("boom"),
                       "the decoder's own text stays out of the UI")
    }
}
