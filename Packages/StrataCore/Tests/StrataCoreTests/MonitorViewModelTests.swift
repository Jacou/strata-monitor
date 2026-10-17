import XCTest
@testable import StrataCore

/// Every label, sub-line and percentage, checked against the two real payloads.
final class MonitorViewModelTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private var idle: Metrics!
    private var generating: Metrics!

    override func setUpWithError() throws {
        idle = try Fixtures.metrics(testClass: type(of: self))
        generating = try Fixtures.metrics(named: "metrics_generating", testClass: type(of: self))
    }

    private func model(_ metrics: Metrics, now: Date = .now, allRequests: Bool = false, modelLoaded: Bool? = nil) -> MonitorViewModel {
        MonitorViewModel(metrics: metrics, now: now, locale: locale, allRequests: allRequests, modelLoaded: modelLoaded)
    }

    private func tile(_ model: MonitorViewModel, _ kind: MonitorViewModel.MetricKind) -> MonitorViewModel.Metric {
        guard let found = model.metrics.first(where: { $0.kind == kind }) else {
            XCTFail("missing tile \(kind.rawValue)")
            return MonitorViewModel.Metric(kind: kind, label: "", value: "", unit: "", sub: "",
                                           series: [], seriesMax: nil, tone: .normal, secondary: nil)
        }
        return found
    }

    // MARK: - idle payload

    func testIdleLiveCardShowsTheLastRequest() throws {
        let card = model(idle).live
        XCTAssertEqual(card.label, "Waiting for a request")
        XCTAssertEqual(card.detail, "last: 572 tokens at 111.0 tok/s")
        XCTAssertEqual(card.percent, 0)
        XCTAssertEqual(card.tone, .normal)
    }

    func testIdleTiles() throws {
        let m = model(idle)
        XCTAssertEqual(m.metrics.map(\.kind), MonitorViewModel.MetricKind.allCases)

        let speed = tile(m, .speed)
        XCTAssertEqual(speed.label, "Speed")
        XCTAssertEqual(speed.value, "111.0")
        XCTAssertEqual(speed.unit, "t/s")
        XCTAssertEqual(speed.sub, "Decode last request")
        XCTAssertEqual(speed.series.count, 60)
        XCTAssertNil(speed.seriesMax)

        // (prompt_tokens - reused) / prompt_ms = 664 / 1.9224 s
        let prefill = try XCTUnwrap(speed.secondary)
        XCTAssertEqual(prefill.value, "345")
        XCTAssertEqual(prefill.unit, "t/s")
        XCTAssertEqual(prefill.sub, "Prefill last request")
        XCTAssertEqual(prefill.series.count, 60)

        let gpu = tile(m, .gpu)
        XCTAssertEqual(gpu.value, "0")
        XCTAssertEqual(gpu.unit, "%")
        XCTAssertEqual(gpu.sub, "GPU 0 0% · GPU 1 0%")
        XCTAssertEqual(gpu.seriesMax, 100)

        let vram = tile(m, .vram)
        XCTAssertEqual(vram.value, "31.4")
        XCTAssertEqual(vram.unit, "/ 32 GB")
        XCTAssertEqual(vram.sub, "GPU 0 15.6 GB · GPU 1 15.7 GB")
        XCTAssertEqual(vram.seriesMax, 34_189_869_056)

        let temp = tile(m, .temp)
        XCTAssertEqual(temp.value, "41")
        XCTAssertEqual(temp.unit, "°C")
        XCTAssertEqual(temp.sub, "GPU 0 41° · GPU 1 39°")
        XCTAssertEqual(temp.seriesMax, 90)
        XCTAssertEqual(temp.tone, .warn)

        let power = tile(m, .power)
        XCTAssertEqual(power.value, "28")
        XCTAssertEqual(power.unit, "W")
        XCTAssertEqual(power.sub, "of 500 W limit")
        XCTAssertEqual(power.seriesMax, 500)

        let pcie = tile(m, .pcie)
        XCTAssertEqual(pcie.value, "Gen4")
        XCTAssertEqual(pcie.unit, "x4")
        XCTAssertEqual(pcie.sub, "to GPU 1.2 MB/s · idle Gen1")
        XCTAssertEqual(pcie.tone, .info)

        let cpu = tile(m, .cpu)
        XCTAssertEqual(cpu.value, "1")
        XCTAssertEqual(cpu.unit, "%")
        XCTAssertEqual(cpu.sub, "8 cores · 16 threads")
        XCTAssertEqual(cpu.seriesMax, 100)

        let disk = tile(m, .disk)
        XCTAssertEqual(disk.value, "0.0")
        XCTAssertEqual(disk.unit, "MB/s")
        XCTAssertEqual(disk.sub, "write 0.1 MB/s")
    }

    func testIdleResources() throws {
        let m = model(idle)

        // last request: 53,262 prompt + 572 output of 262,144
        XCTAssertEqual(m.context.percentText, "21%")
        XCTAssertEqual(m.context.sub, "54k / 256K")
        XCTAssertEqual(m.context.fraction, 53_834.0 / 262_144.0, accuracy: 0.0001)
        XCTAssertTrue(m.context.arcVisible)

        XCTAssertEqual(m.experts.text, "11,432 · 18.3 GB")
        XCTAssertEqual(m.experts.percent, 57.39, accuracy: 0.01)

        XCTAssertEqual(m.ram.text, "53.9 / 61 GB")
        XCTAssertEqual(m.ram.percent, 88.86, accuracy: 0.01)
        XCTAssertEqual(m.ram.tone, .normal)   // under the 92% line

        XCTAssertEqual(m.temp.text, "41 °C")
        XCTAssertEqual(m.temp.percent, 41)
    }

    func testIdleConversationCache() throws {
        let now = Date(timeIntervalSince1970: 1_792_199_432.569_0875 + 300)
        let cache = try XCTUnwrap(model(idle, now: now).convCache)
        XCTAssertTrue(cache.enabled)
        XCTAssertEqual(cache.slotsText, "2 / 4")
        XCTAssertEqual(cache.slotsPercent, 50)
        XCTAssertEqual(cache.memoryText, "2.4 / 3.0 GB")
        XCTAssertEqual(cache.memoryPercent, 78.95, accuracy: 0.01)
        XCTAssertEqual(cache.summary, "189 of 224 requests reused part of their prompt")

        let facts = Dictionary(uniqueKeysWithValues: cache.facts.map { ($0.key, $0.value) })
        XCTAssertEqual(facts["Last request"], "52,598 of 53,262 prompt tokens reused")
        XCTAssertEqual(facts["Reused since start"], "9,538,410 tokens (97% of all prompt tokens)")
        XCTAssertEqual(facts["Parked / restored"], "63 / 25 · 22 evicted")
        XCTAssertEqual(facts["Last switch"], "Parked 52,871 tokens, 5 min ago")
        XCTAssertFalse(cache.note.contains("--conversation-cache-mib"))
    }

    func testIdleRequestsAndTotals() throws {
        let m = model(idle)
        XCTAssertEqual(m.requests.count, 12)
        XCTAssertNil(m.noRequestsText)
        XCTAssertEqual(m.showAllLabel, "Show all (224)")

        let row = try XCTUnwrap(m.requests.first)
        XCTAssertTrue(row.timeText.contains(":"), "a clock time, got \(row.timeText)")
        XCTAssertNotEqual(row.timeText, notAvailable)
        XCTAssertEqual(row.finishText, "Done")
        XCTAssertEqual(row.badge, .neutral)
        XCTAssertNil(row.projectionText)
        XCTAssertEqual(row.promptText, "53,262")
        XCTAssertEqual(row.reusedText, "52,598")
        XCTAssertEqual(row.outputText, "572")
        XCTAssertEqual(row.tokSText, "111.0")
        XCTAssertEqual(row.hitText, "96.0%")
        XCTAssertEqual(row.pcieText, "+1.2% PCIe")
        XCTAssertEqual(row.durationText, "7.1 s")

        let session = try XCTUnwrap(model(idle, now: Date(timeIntervalSince1970: 1_792_199_293.358)).session)
        XCTAssertEqual(session.uptimeText, "10 h 36 m")
        // The uptime lives in the card's corner badge only — the headline used to repeat it.
        XCTAssertTrue(session.headline.hasPrefix("Since "), session.headline)
        XCTAssertFalse(session.headline.contains("up"), session.headline)
        XCTAssertFalse(session.headline.contains(session.uptimeText), session.headline)
        XCTAssertEqual(session.facts.map(\.key), ["Requests", "Prompt read", "Written", "Reused", "Tool calls"])
        XCTAssertEqual(session.facts.map(\.value), [
            "224",
            "319,435 tokens at 760 tok/s",
            "157,017 tokens at 101.9 tok/s",
            "9,538,410 tokens (97% of prompt)",
            "2 recovered from reasoning",
        ])
        let acceptance = try XCTUnwrap(session.acceptance)
        XCTAssertEqual(acceptance.percent, (100 * 100_687) / 136_380, accuracy: 0.01)
        XCTAssertEqual(acceptance.text, "74% · 100,687 of 136,380")
        XCTAssertEqual(acceptance.tone, .normal)
    }

    // MARK: - generating payload

    func testGeneratingLiveCard() throws {
        let card = model(generating).live
        XCTAssertEqual(card.label, "Thinking")            // live.phase, capitalised
        XCTAssertEqual(card.detail, "1 tokens · 4.0 tok/s")
        XCTAssertEqual(card.percent, 100.0 / 32_768.0, accuracy: 0.0001)
        XCTAssertEqual(card.tone, .normal)
    }

    func testGeneratingTiles() throws {
        let m = model(generating)

        let speed = tile(m, .speed)
        XCTAssertEqual(speed.value, "4.0")
        XCTAssertEqual(speed.sub, "Decode now")
        XCTAssertEqual(speed.secondary?.value, "470")
        XCTAssertEqual(speed.secondary?.sub, "Prefill this request")

        XCTAssertEqual(tile(m, .gpu).sub, "GPU 0 0% · GPU 1 100%")
        XCTAssertEqual(tile(m, .gpu).value, "50")
        XCTAssertEqual(tile(m, .temp).value, "43")
        XCTAssertEqual(tile(m, .temp).sub, "GPU 0 42° · GPU 1 43°")
        XCTAssertEqual(tile(m, .power).value, "115")
        XCTAssertEqual(tile(m, .pcie).sub, "to GPU 35,423 MB/s")   // no "idle Gen" when the link is at full gen
        XCTAssertEqual(tile(m, .cpu).value, "7")
        XCTAssertEqual(tile(m, .disk).value, "0.0")
    }

    func testGeneratingContextUsesTheLiveRequest() throws {
        let context = model(generating).context
        XCTAssertEqual(context.fraction, 4_892.0 / 262_144.0, accuracy: 0.0001)   // 4,891 prompt + 1 generated
        XCTAssertEqual(context.percentText, "2%")
        XCTAssertEqual(context.sub, "4.9k / 256K")
        XCTAssertTrue(context.arcVisible)
    }

    func testGeneratingResources() throws {
        let m = model(generating)
        XCTAssertEqual(m.ram.text, "53.2 / 61 GB")
        XCTAssertEqual(m.temp.text, "43 °C")
        XCTAssertEqual(m.experts.text, "11,432 · 18.3 GB")
    }

    func testGeneratingConversationCache() throws {
        let now = Date(timeIntervalSince1970: 1_792_199_519.580_9786 + 30)
        let cache = try XCTUnwrap(model(generating, now: now).convCache)
        XCTAssertEqual(cache.slotsText, "1 / 4")
        XCTAssertEqual(cache.memoryText, "1.6 / 3.0 GB")
        XCTAssertEqual(cache.summary, "191 of 226 requests reused part of their prompt")
        let facts = Dictionary(uniqueKeysWithValues: cache.facts.map { ($0.key, $0.value) })
        XCTAssertEqual(facts["Last request"], "2,780 of 3,275 prompt tokens reused")
        XCTAssertEqual(facts["Last switch"], "Restored 2,546 tokens, just now")
    }

    func testGeneratingRequests() throws {
        let m = model(generating)
        XCTAssertEqual(m.showAllLabel, "Show all (226)")
        let row = try XCTUnwrap(m.requests.first)
        XCTAssertEqual(row.promptText, "3,275")
        XCTAssertEqual(row.reusedText, "2,780")
        XCTAssertEqual(row.outputText, "102")
        XCTAssertEqual(row.tokSText, "107.6")
        XCTAssertEqual(row.hitText, "91.5%")
        XCTAssertEqual(row.pcieText, "+3.6% PCIe")
        XCTAssertEqual(row.durationText, "2.2 s")
    }

    // MARK: - reading state

    func testReadingLiveCard() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"live": {"state": "reading", "prompt_read": 26631, "prompt_total": 53262, "prompt_tokens": 53262}}
        """)
        let card = model(metrics).live
        XCTAssertEqual(card.label, "Reading prompt")
        XCTAssertEqual(card.detail, "26,631 / 53,262 tokens · 50%")
        XCTAssertEqual(card.percent, 50)
        XCTAssertEqual(card.tone, .info)

        let speed = tile(model(metrics), .speed)
        XCTAssertEqual(speed.value, notAvailable)
        XCTAssertEqual(speed.sub, "Decode")
        XCTAssertEqual(speed.secondary?.sub, "Prefill now")
    }

    func testReadingWithoutATotal() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"live": {"state": "reading", "prompt_tokens": 1200}}"#)
        let card = model(metrics).live
        XCTAssertEqual(card.detail, "1,200 tokens")
        XCTAssertEqual(card.percent, 0)
    }

    func testGeneratingWithoutAPhase() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"live": {"state": "generating", "generated": 12, "tok_s": 88.5}}"#)
        let card = model(metrics).live
        XCTAssertEqual(card.label, "Generating")
        XCTAssertEqual(card.detail, "12 tokens · 88.5 tok/s")
        XCTAssertEqual(card.percent, 0)
    }

    // MARK: - empty payload

    func testEmptyPayloadStillFillsEveryCard() throws {
        let m = model(try Fixtures.decode(Metrics.self, "{}"))
        XCTAssertEqual(m.live.label, "Waiting for a request")
        XCTAssertEqual(m.live.detail, "")
        XCTAssertEqual(m.metrics.count, 8)
        XCTAssertTrue(m.metrics.allSatisfy { $0.value == notAvailable })
        XCTAssertTrue(m.metrics.allSatisfy { $0.series.isEmpty })
        XCTAssertEqual(m.context.percentText, "0%")
        XCTAssertEqual(m.context.sub, notAvailable)
        XCTAssertFalse(m.context.arcVisible)
        XCTAssertEqual(m.experts.text, notAvailable)
        XCTAssertEqual(m.experts.percent, 0)
        XCTAssertEqual(m.ram.text, notAvailable)
        XCTAssertEqual(m.temp.text, notAvailable)
        XCTAssertNil(m.convCache, "an older server: the card is hidden")
        XCTAssertTrue(m.requests.isEmpty)
        XCTAssertEqual(m.noRequestsText, "No requests yet")
        XCTAssertNil(m.session)
        XCTAssertNil(m.showAllLabel)
    }

    // MARK: - details that vary by server

    func testSingleGPUUsesTheCardNameAndExpertSub() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"engine": {"expert_slots": 6465},
         "hardware": {"gpus": [{"index": 0, "util": 42, "mem_used": 8000000000}], "gpu_mem_total": 17179869184},
         "hardware_static": {"gpu_name": "RTX 5070 Ti"}}
        """)
        let m = model(metrics)
        XCTAssertEqual(tile(m, .gpu).sub, "RTX 5070 Ti")
        XCTAssertEqual(tile(m, .vram).sub, "6,465 experts cached")
        XCTAssertEqual(tile(m, .vram).unit, "/ 16 GB")
        XCTAssertEqual(tile(m, .temp).sub, "")
    }

    func testDiskNeedsPsutil() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"hardware": {"cpu": 1}, "hardware_static": {"psutil": false}}"#)
        let disk = tile(model(metrics), .disk)
        XCTAssertEqual(disk.value, notAvailable)
        XCTAssertEqual(disk.unit, "")
        XCTAssertEqual(disk.sub, "needs psutil (setup installs it)")

        let withPsutil = tile(model(try Fixtures.decode(Metrics.self, #"{"hardware_static": {"psutil": true}}"#)), .disk)
        XCTAssertEqual(withPsutil.sub, "")
    }

    func testDiskSwitchesToGBPerSecond() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"hardware": {"disk_read_mb": 2560.5, "disk_write_mb": 1234.5}}"#)
        let disk = tile(model(metrics), .disk)
        XCTAssertEqual(disk.value, "2.50")
        XCTAssertEqual(disk.unit, "GB/s")
        XCTAssertEqual(disk.sub, "write 1,234.5 MB/s")
    }

    func testRAMTurnsRedAbove92Percent() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"hardware": {"ram_used": 95000000000, "ram_total": 100000000000}}"#)
        let ram = model(metrics).ram
        XCTAssertEqual(ram.percent, 95, accuracy: 0.001)
        XCTAssertEqual(ram.tone, .danger)
    }

    func testContextRingHidesANearZeroArc() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"engine": {"max_context": 262144}, "live": {"state": "idle"}, "requests": [{"time": 1, "prompt_tokens": 100, "output_tokens": 10}]}"#)
        let context = model(metrics).context
        XCTAssertEqual(context.percentText, "0%")
        XCTAssertFalse(context.arcVisible)
        XCTAssertEqual(context.sub, "110 / 256K")
    }

    func testContextFollowsTheWebAppWhenTheServerSendsNoLiveSection() throws {
        // The web page does `live = m.live || {}`, so with no `live` at all it counts the running
        // request's tokens — none — rather than the last finished one. Same here.
        let metrics = try Fixtures.decode(Metrics.self, #"{"engine": {"max_context": 262144}, "requests": [{"time": 1, "prompt_tokens": 100, "output_tokens": 10}]}"#)
        let context = model(metrics).context
        XCTAssertEqual(context.fraction, 0)
        XCTAssertEqual(context.sub, "0 / 256K")
    }

    func testContextUsesLiveTokensWhenNotIdle() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"engine": {"max_context": 1000}, "live": {"state": "generating", "prompt_tokens": 300, "generated": 100},
         "requests": [{"time": 1, "prompt_tokens": 999, "output_tokens": 999}]}
        """)
        XCTAssertEqual(model(metrics).context.fraction, 0.4, accuracy: 0.0001)
    }

    func testConversationCacheDisabled() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"conversation_cache": {"enabled": false, "requests": 10, "requests_reused": 4,
         "reused_tokens": 500, "prompt_tokens": 1000, "last_prompt": 100, "last_reused": 40}}
        """)
        let cache = try XCTUnwrap(model(metrics).convCache)
        XCTAssertFalse(cache.enabled)
        XCTAssertEqual(cache.facts.map(\.key), ["Last request", "Reused since start"])
        XCTAssertTrue(cache.note.contains("--conversation-cache-mib"))
    }

    func testConversationCacheWithoutEvictions() throws {
        let metrics = try Fixtures.decode(Metrics.self,
            #"{"conversation_cache": {"enabled": true, "parks": 1, "restores": 0, "evictions": 0}}"#)
        let facts = Dictionary(uniqueKeysWithValues: (model(metrics).convCache?.facts ?? []).map { ($0.key, $0.value) })
        XCTAssertEqual(facts["Parked / restored"], "1 / 0")
        XCTAssertNil(facts["Last switch"])
    }

    // MARK: - request rows

    func testFinishBadges() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"requests": [{"time": 1, "finish": "stop"}, {"time": 2, "finish": "length"},
                      {"time": 3, "finish": "cancel"}, {"time": 4, "finish": "disconnect"},
                      {"time": 5, "finish": "error"}, {"time": 6, "finish": "vanished"}, {"time": 7}]}
        """)
        let rows = model(metrics).requests
        XCTAssertEqual(rows.map(\.finishText), ["Done", "Max tokens", "Stopped", "Closed", "Error", "vanished", notAvailable])
        XCTAssertEqual(rows.map(\.badge), [.neutral, .neutral, .warning, .warning, .danger, .neutral, .neutral])
    }

    func testProjectionBadgesAndMissingNumbers() throws {
        let metrics = try Fixtures.decode(Metrics.self, """
        {"requests": [{"time": 1, "finish": "stop", "projection": true},
                      {"time": 2, "finish": "stop", "projection": false},
                      {"time": 3, "finish": "stop", "projection": null, "hit_rate": null, "pcie_share": 0,
                       "decode_tok_s": null, "duration_s": null}]}
        """)
        let rows = model(metrics).requests
        XCTAssertEqual(rows[0].projectionText, "ESP")
        XCTAssertEqual(rows[1].projectionText, "stock")
        XCTAssertNil(rows[2].projectionText)
        XCTAssertEqual(rows[2].hitText, notAvailable)
        XCTAssertNil(rows[2].pcieText, "a zero PCIe share is not worth showing")
        XCTAssertEqual(rows[2].tokSText, notAvailable)
        XCTAssertEqual(rows[2].durationText, notAvailable)
    }

    func testShowAllOnlyWhenTheServerKeepsMoreThanAreShown() throws {
        let many = (1...15).map { #"{"time": \#($0), "finish": "stop"}"# }.joined(separator: ",")
        let m = model(try Fixtures.decode(Metrics.self, #"{"requests": [\#(many)]}"#))
        XCTAssertEqual(m.requests.count, 12, "the last 12, like the web page")
        XCTAssertEqual(m.showAllLabel, "Show all (15)")

        let all = model(try Fixtures.decode(Metrics.self, #"{"requests": [\#(many)]}"#), allRequests: true)
        XCTAssertEqual(all.requests.count, 15)

        let few = model(try Fixtures.decode(Metrics.self, #"{"requests": [{"time": 1}, {"time": 2}]}"#))
        XCTAssertNil(few.showAllLabel)
    }

    // MARK: - the model is not resident

    func testUnloadedModelChangesTheLiveCard() throws {
        let card = model(idle, modelLoaded: false).live
        XCTAssertEqual(card.label, "Waiting for the first request to load the model")
        XCTAssertEqual(card.detail, "")
        XCTAssertEqual(card.percent, 0)

        // Unknown load state (no /health yet) keeps the ordinary idle card.
        XCTAssertEqual(model(idle, modelLoaded: nil).live.label, "Waiting for a request")
        XCTAssertEqual(model(idle, modelLoaded: true).live.label, "Waiting for a request")

        // A request in flight means the model is loaded, whatever /health said a moment ago.
        XCTAssertTrue(model(generating, modelLoaded: false).live.label != "Waiting for the first request to load the model")
    }

    func testSessionNeedsRequests() throws {
        XCTAssertNil(model(try Fixtures.decode(Metrics.self, "{}")).session)
        let metrics = try Fixtures.decode(Metrics.self, #"{"totals": {"requests": 3, "prompt_tokens": 90, "reused": 90, "output_tokens": 10, "prompt_ms": 100, "decode_ms": 100, "since": 1792161083.9}}"#)
        let session = try XCTUnwrap(model(metrics, now: Date(timeIntervalSince1970: 1_792_161_683.9)).session)
        XCTAssertEqual(session.uptimeText, "10 min")
        XCTAssertEqual(session.facts.map(\.value), [
            "3",
            "0 tokens",
            "10 tokens at 100.0 tok/s",
            "90 tokens (100% of prompt)",
        ])
        XCTAssertNil(session.acceptance, "no drafts reported: speculation is off")
    }

    func testSessionAcceptanceWarnsWhenMostDraftsAreWasted() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"totals": {"requests": 4, "drafts_offered": 200, "drafts_accepted": 40}}"#)
        let acceptance = try XCTUnwrap(model(metrics).session?.acceptance)
        XCTAssertEqual(acceptance.percent, 20, accuracy: 0.001)
        XCTAssertEqual(acceptance.text, "20% · 40 of 200")
        XCTAssertEqual(acceptance.tone, .warn, "a quarter of the drafts paid for the speculation")
    }

    // MARK: - one request, opened up

    func testRequestDetailFromTheIdleFixture() throws {
        let detail = try XCTUnwrap(model(idle).requests.first?.detail)
        XCTAssertEqual(detail.badgeText, "Done")
        XCTAssertEqual(detail.badge, .neutral)
        XCTAssertEqual(detail.headline, "572 tokens · 111.0 t/s · 7.1 s")
        XCTAssertTrue(detail.title.contains(":"), detail.title)

        let facts = Dictionary(uniqueKeysWithValues: detail.facts.map { ($0.key, $0.value) })
        XCTAssertEqual(facts["Duration"], "7.1 s")
        XCTAssertEqual(facts["Prompt"], "53,262")
        XCTAssertEqual(facts["Reused"], "52,598 (98.8%)")
        XCTAssertEqual(facts["Read"], "664")
        XCTAssertEqual(facts["Output"], "572")
        XCTAssertEqual(facts["Prefill"], "1,922 ms · 345 tok/s")
        XCTAssertEqual(facts["Decode"], "5,154 ms · 111.0 tok/s")
        XCTAssertEqual(facts["Drafts"], "346 of 510 accepted (68%)")
        XCTAssertEqual(facts["Expert hit rate"], "96.0%")
        XCTAssertEqual(facts["PCIe share"], "+1.2%")
        XCTAssertEqual(facts["Repeat coverage"], "0.0%")
        XCTAssertNil(facts["Reasoning"], "zero recoveries is not a fact worth a row")
        XCTAssertNil(facts["Images"], "no blobs, no files")
        XCTAssertNil(facts["Speed projection"], "the server reported null")

        let acceptance = try XCTUnwrap(detail.acceptance)
        XCTAssertEqual(acceptance.text, "68% · 346 of 510")
    }

    func testRequestDetailFillsInWhatTheServerOmits() throws {
        let metrics = try Fixtures.decode(Metrics.self, #"{"requests": [{"time": 1792199293, "prompt_tokens": 1000, "reused": 400, "output_tokens": 50, "prompt_ms": 600, "decode_ms": 500, "ram_blobs": 2, "file_blobs": 1, "file_mb": 1.4, "projection": true}]}"#)
        let detail = try XCTUnwrap(model(metrics).requests.first?.detail)
        let facts = Dictionary(uniqueKeysWithValues: detail.facts.map { ($0.key, $0.value) })
        XCTAssertEqual(facts["Read"], "600", "prompt minus reused when prompt_read is missing")
        XCTAssertEqual(facts["Prefill"], "600 ms · 1,000 tok/s")
        XCTAssertEqual(facts["Decode"], "500 ms · 100.0 tok/s", "output / decode_ms when decode_tok_s is missing")
        XCTAssertEqual(facts["Finish"], notAvailable)
        XCTAssertEqual(facts["Duration"], notAvailable)
        XCTAssertEqual(facts["Images"], "2 in RAM · 1 files · 1.4 MB")
        XCTAssertEqual(facts["Speed projection"], "on")
        XCTAssertNil(detail.acceptance)
    }
}
