import XCTest
@testable import StrataCore

/// The hover card's derivation: pill text, the two speeds and where each one came from.
final class HoverCardTests: XCTestCase {
    private func card(_ metrics: Metrics?, _ status: MonitorStatus, model: String? = "strata-test", lastUpdated: Date? = nil) -> HoverCard {
        HoverCard(metrics: metrics, status: status, model: model, lastUpdated: lastUpdated)
    }

    func testGeneratingShowsTheLiveSpeedsCaptionedNow() throws {
        let metrics = try Fixtures.metrics(named: "metrics_generating", testClass: type(of: self))
        let hover = card(metrics, .generating(tokS: 4.0))

        XCTAssertEqual(hover.pillText, "Generating · Thinking")
        XCTAssertEqual(hover.decode.text, "4.0")
        XCTAssertEqual(hover.decode.caption, "now")
        XCTAssertEqual(hover.prefill.text, "470")
        XCTAssertEqual(hover.prefill.caption, "now")
    }

    func testIdleShowsTheLastRequestsSpeedsCaptionedLastRequest() throws {
        let metrics = try Fixtures.metrics(named: "metrics_idle", testClass: type(of: self))
        let hover = card(metrics, .idle)

        XCTAssertEqual(hover.pillText, "Idle")
        XCTAssertEqual(hover.decode.text, "111.0", "the last request's decode_tok_s")
        XCTAssertEqual(hover.decode.caption, "last request")
        // (53,262 − 52,598) unread prompt tokens over 1,922.4 ms, the web page's own arithmetic.
        XCTAssertEqual(hover.prefill.text, "345")
        XCTAssertEqual(hover.prefill.caption, "last request")
    }

    func testReadingTakesPrefillFromTheEngineAndDecodeFromTheLastRequest() throws {
        let metrics = try Fixtures.decode(
            Metrics.self,
            """
            {"live": {"state": "reading", "prompt_read": 4000, "prompt_total": 8000, "prefill_tok_s_mean": 610.4},
             "requests": [{"time": 1, "decode_tok_s": 88.25, "prompt_ms": 1000, "prompt_tokens": 100, "reused": 0}]}
            """
        )
        let hover = card(metrics, .reading(percent: 50))

        XCTAssertEqual(hover.pillText, "Reading prompt · 50%")
        XCTAssertEqual(hover.decode.text, "88.2")
        XCTAssertEqual(hover.decode.caption, "last request")
        XCTAssertEqual(hover.prefill.text, "610")
        XCTAssertEqual(hover.prefill.caption, "now")
    }

    func testNothingToShowIsADashWithNoCaption() throws {
        let hover = card(Metrics(), .unknown)
        XCTAssertEqual(hover.pillText, "Connecting…")
        XCTAssertEqual(hover.decode.text, notAvailable)
        XCTAssertEqual(hover.decode.caption, "")
        XCTAssertEqual(hover.prefill.text, notAvailable)
        XCTAssertEqual(hover.prefill.caption, "")

        let broken = card(nil, .unreachable)
        XCTAssertEqual(broken.pillText, "Server not reachable")
        XCTAssertEqual(broken.decode.text, notAvailable)
        XCTAssertEqual(broken.prefill.text, notAvailable)
    }

    func testModelUnloadedKeepsThePillItAlreadyUses() throws {
        XCTAssertEqual(card(nil, .modelUnloaded).pillText, "Model unloaded")
    }

    func testFooterNamesTheModelAndTheFreshness() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let hover = HoverCard(
            metrics: nil, status: .idle, model: "qwen3.8-flash",
            lastUpdated: now.addingTimeInterval(-300), now: now
        )
        XCTAssertEqual(hover.footer, "qwen3.8-flash · updated 5 min ago")

        // No model name yet: the freshness line on its own.
        XCTAssertEqual(
            HoverCard(metrics: nil, status: .idle, model: nil, lastUpdated: now, now: now).footer,
            "updated just now"
        )
        XCTAssertEqual(
            HoverCard(metrics: nil, status: .idle, model: "", lastUpdated: nil, now: now).footer,
            "no data yet"
        )
    }

    func testPhaseCapitalisationMatchesTheWebPage() {
        XCTAssertEqual(HoverCard.capitalized("thinking"), "Thinking")
        XCTAssertEqual(HoverCard.capitalized("writing code"), "Writing code")
        XCTAssertEqual(HoverCard.capitalized(nil), "Generating")
        XCTAssertEqual(HoverCard.capitalized(""), "Generating")
    }
}
