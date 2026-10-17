import XCTest
@testable import StrataCore

/// Nothing in the payload is guaranteed: an older server, a newer server, a half-written body.
/// None of these may crash — a partial payload still has to render.
final class LenientDecodingTests: XCTestCase {
    // MARK: - empty and null payloads

    func testEmptyPayloadDecodes() throws {
        let metrics = try Fixtures.decode(Metrics.self, "{}")
        XCTAssertNil(metrics.engine)
        XCTAssertNil(metrics.live)
        XCTAssertNil(metrics.requests)
        XCTAssertNil(metrics.conversationCache)
        XCTAssertNil(metrics.requestsKept)
        XCTAssertNil(metrics.totals)
        XCTAssertNil(metrics.hardware)
        XCTAssertNil(metrics.hardwareStatic)
        XCTAssertNil(metrics.history)
        XCTAssertNil(metrics.time)
        XCTAssertNil(metrics.latestRequest)

        let health = try Fixtures.decode(Health.self, "{}")
        XCTAssertNil(health.status)
        XCTAssertFalse(health.isOK)
    }

    func testEveryLiveFieldNull() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {
          "live": {
            "state": null, "queued": null, "phase": null, "prompt_tokens": null, "prompt_read": null,
            "prompt_total": null, "generated": null, "max_tokens": null, "elapsed_s": null,
            "tok_s": null, "tok_s_mean": null, "prefill_tok_s_mean": null, "tok_s_window_s": null
          },
          "time": 1
        }
        """)
        let live = try XCTUnwrap(metrics.live)
        XCTAssertNil(live.state)
        XCTAssertNil(live.queued)
        XCTAssertEqual(live.queuedCount, 0)
        XCTAssertNil(live.phase)
        XCTAssertNil(live.promptTokens)
        XCTAssertNil(live.promptRead)
        XCTAssertNil(live.promptTotal)
        XCTAssertNil(live.generated)
        XCTAssertNil(live.maxTokens)
        XCTAssertNil(live.elapsedS)
        XCTAssertNil(live.tokS)
        XCTAssertNil(live.tokSMean)
        XCTAssertNil(live.prefillTokSMean)
        XCTAssertNil(live.tokSWindowS)
        XCTAssertEqual(metrics.time, 1)
    }

    func testLiveNullAndRequestsNull() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"live": null, "requests": null, "hardware": null}"#)
        XCTAssertNil(metrics.live)
        XCTAssertNil(metrics.requests)
        XCTAssertNil(metrics.hardware)
    }

    // MARK: - numbers that are not numbers

    func testIntsFloatsAndNumericStrings() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {
          "engine": {"max_context": 262144.0, "cvec": 7, "pcie_frac": 0.18, "spec_min_p": "0.5", "images": 1},
          "live": {"queued": 3.0, "state": "generating", "tok_s": "12.5", "generated": "44"},
          "requests": [{"time": 1.5, "finish": "stop", "prompt_tokens": 10.9, "reused": 0, "projection": 1}],
          "requests_kept": 7.4,
          "hardware": {"gpu_temp": "44", "gpus": [{"index": 0.0, "util": "55"}]},
          "hardware_static": {"cores": "8", "psutil": "true"},
          "totals": {"requests": 12},
          "time": "1792199432.5"
        }
        """)

        let engine = try XCTUnwrap(metrics.engine)
        XCTAssertEqual(engine.maxContext, 262_144)
        XCTAssertEqual(engine.cvec?.raw, "7")
        XCTAssertEqual(engine.cvec?.doubleValue, 7)
        XCTAssertEqual(engine.pcieFrac?.raw, "0.18")
        XCTAssertEqual(engine.specMinP?.doubleValue, 0.5)
        XCTAssertEqual(engine.images, true)

        let live = try XCTUnwrap(metrics.live)
        XCTAssertEqual(live.queued, 3)
        XCTAssertEqual(live.state, .generating)
        XCTAssertEqual(live.tokS, 12.5)
        XCTAssertEqual(live.generated, 44)

        let request = try XCTUnwrap(metrics.requests?.first)
        XCTAssertEqual(request.promptTokens, 10.9)
        XCTAssertEqual(request.projection, true)

        XCTAssertEqual(metrics.requestsKept, 7)

        let hardware = try XCTUnwrap(metrics.hardware)
        XCTAssertEqual(hardware.gpuTemp, 44)
        XCTAssertEqual(hardware.gpus?.first?.index, 0)
        XCTAssertEqual(hardware.gpus?.first?.util, 55)

        XCTAssertEqual(metrics.hardwareStatic?.cores, 8)
        XCTAssertEqual(metrics.hardwareStatic?.psutil, true)
        XCTAssertEqual(metrics.time, 1_792_199_432.5)
    }

    func testUnknownStateAndFinishAreKept() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"live": {"state": "warming"}, "requests": [{"time": 1, "finish": "timeout"}]}
        """)
        XCTAssertEqual(metrics.live?.state, .other("warming"))
        XCTAssertEqual(metrics.requests?.first?.finish, .other("timeout"))
    }

    func testLenientStringFromBool() throws {
        let engine = try Fixtures.decode(Engine.self, #"{"cvec": true}"#)
        XCTAssertEqual(engine.cvec?.raw, "true")
    }

    // MARK: - junk inside arrays is dropped, not fatal

    func testJunkRequestEntriesAreSkipped() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"requests": [null, 5, "nope", [], {"time": 1, "finish": "stop"}, {"time": 2}]}
        """)
        let requests = try XCTUnwrap(metrics.requests)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.map(\.time), [1, 2])
        XCTAssertEqual(Set(requests.map(\.id)).count, 2)
    }

    func testJunkGPUEntriesAreSkipped() throws {
        let hardware = try Fixtures.decode(Hardware.self, #"{"gpus": [{"index": 0}, "junk", {"index": 1}]}"#)
        XCTAssertEqual(hardware.gpus?.count, 2)
        XCTAssertEqual(hardware.gpus?.map(\.index), [0, 1])
    }

    func testSeriesNullsBecomeZero() throws {
        let history = try Fixtures.decode(History.self, #"{"tok_s": [1, null, 2.5, "3", true, {}]}"#)
        XCTAssertEqual(history.tokS, [1, 0, 2.5, 3, 1, 0])
    }

    func testMissingSeriesAndEmptySeries() throws {
        let history = try Fixtures.decode(History.self, #"{"tok_s": [], "cpu": null}"#)
        XCTAssertEqual(history.tokS, [])
        XCTAssertNil(history.cpu)
    }

    // MARK: - unknown keys are ignored

    func testUnknownKeysIgnored() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"time": 5, "brand_new_section": {"a": [1, 2]}, "engine": {"model": "m", "whatever": {"deep": 1}}}
        """)
        XCTAssertEqual(metrics.time, 5)
        XCTAssertEqual(metrics.engine?.model, "m")
    }

    func testRequestWithOnlyTimeDecodes() throws {
        let request = try Fixtures.decode(Request.self, #"{"time": 123.5}"#)
        XCTAssertEqual(request.time, 123.5)
        XCTAssertEqual(request.id, "123.5")
        XCTAssertNil(request.finish)
        XCTAssertNil(request.hitRate)
    }

    func testRequestWithoutTimeStillIdentifiable() throws {
        let requests = try Fixtures.decode([Request].self, #"[{"finish": "stop"}, {"finish": "error"}]"#)
        XCTAssertEqual(Set(requests.map(\.id)).count, 2)
    }

    // MARK: - a payload that is not an object at all

    func testNonObjectPayloadThrowsDecodableNotCrash() {
        XCTAssertThrowsError(try Fixtures.decode(Metrics.self, "[]"))
        XCTAssertThrowsError(try Fixtures.decode(Metrics.self, "not json"))
    }
}
