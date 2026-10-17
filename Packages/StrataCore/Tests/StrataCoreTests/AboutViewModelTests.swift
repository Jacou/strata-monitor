import XCTest
@testable import StrataCore

/// `renderAbout` from docs/reference-app.js, ported: same rows, same wording, same drops.
final class AboutViewModelTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")
    private var generating: Metrics!
    private let base = URL(string: "http://192.168.1.10:8081")!

    override func setUpWithError() throws {
        generating = try Fixtures.metrics(named: "metrics_generating", testClass: type(of: self))
    }

    private func model(_ metrics: Metrics?, baseURL: URL? = nil) -> AboutViewModel {
        AboutViewModel(metrics: metrics, baseURL: baseURL ?? base, locale: locale)
    }

    private func facts(_ model: AboutViewModel, _ title: String) -> [AboutFact] {
        model.sections.first(where: { $0.title == title })?.facts ?? []
    }

    private func value(_ model: AboutViewModel, _ title: String, _ label: String) -> String? {
        facts(model, title).first(where: { $0.label == label })?.value
    }

    // MARK: - engine

    func testEngineFactsMatchTheWebApp() throws {
        let m = model(generating)
        XCTAssertEqual(value(m, "Engine", "Model"), "qwen3.8-flash-next-iq3_xxs")
        XCTAssertEqual(value(m, "Engine", "Engine"), "v0.1.40")
        XCTAssertEqual(value(m, "Engine", "Context"), "262,144 tokens")
        XCTAssertEqual(
            value(m, "Engine", "KV cache"),
            "8-bit, streamed: 32,768 positions per layer in VRAM, the rest in RAM"
        )
        XCTAssertEqual(value(m, "Engine", "Experts in VRAM"), "11,432 (18.3 GB)")
        XCTAssertEqual(value(m, "Engine", "Speculation"), "MTP drafts up to 3 tokens, prompt lookup on")
        XCTAssertEqual(value(m, "Engine", "Images"), "on")
    }

    func testRowsTheServerDidNotReportAreDropped() throws {
        let m = model(generating)
        // cvec is 0 in the fixture: no projection row, like `projectionText` returning null.
        XCTAssertNil(value(m, "Engine", "Experimental speed projection"))

        let sparse = AboutViewModel(
            metrics: try Fixtures.decode(Metrics.self, #"{"engine": {"model": "m"}}"#),
            baseURL: nil, locale: locale
        )
        XCTAssertEqual(facts(sparse, "Engine").map(\.label), ["Model", "Engine", "Images"])
        XCTAssertEqual(value(sparse, "Engine", "Engine"), "built from source")
        XCTAssertEqual(value(sparse, "Engine", "Images"), "off")
        XCTAssertTrue(sparse.sections.allSatisfy { !$0.facts.isEmpty }, "empty sections are dropped")
    }

    func testKVNamesAreTranslatedLikeTheWebApp() {
        XCTAssertEqual(AboutViewModel.kvName("int8"), "8-bit")
        XCTAssertEqual(AboutViewModel.kvName("q4_0"), "4-bit (Hadamard-rotated)")
        XCTAssertEqual(AboutViewModel.kvName("fp16"), "16-bit")
        XCTAssertEqual(AboutViewModel.kvName("iq3_xxs"), "iq3_xxs")
        XCTAssertNil(AboutViewModel.kvName(nil))
        XCTAssertNil(AboutViewModel.kvName(""))
    }

    func testKVCacheWithoutStreamingSaysAllInVRAM() throws {
        let m = AboutViewModel(
            metrics: try Fixtures.decode(Metrics.self, #"{"engine": {"kv": "fp16"}}"#),
            baseURL: nil, locale: locale
        )
        XCTAssertEqual(value(m, "Engine", "KV cache"), "16-bit, all in VRAM")
    }

    func testSpeculationFallsBackToSpecDepth() throws {
        let noMTP = AboutViewModel(
            metrics: try Fixtures.decode(Metrics.self, #"{"engine": {"spec": 4, "lookup": 0}}"#),
            baseURL: nil, locale: locale
        )
        XCTAssertEqual(value(noMTP, "Engine", "Speculation"), "MTP drafts up to 3 tokens")

        let zeroMTP = AboutViewModel(
            metrics: try Fixtures.decode(Metrics.self, #"{"engine": {"spec": 5, "mtp_max": 0}}"#),
            baseURL: nil, locale: locale
        )
        XCTAssertEqual(value(zeroMTP, "Engine", "Speculation"), "MTP drafts up to 4 tokens")

        let noSpec = AboutViewModel(
            metrics: try Fixtures.decode(Metrics.self, #"{"engine": {"spec": 0}}"#),
            baseURL: nil, locale: locale
        )
        XCTAssertNil(value(noSpec, "Engine", "Speculation"))
    }

    // MARK: - the speed projection note

    func testProjectionText() {
        XCTAssertNil(AboutViewModel.projectionText(nil))
        XCTAssertNil(AboutViewModel.projectionText(LenientString("0")))
        XCTAssertNil(AboutViewModel.projectionText(LenientString("")))

        XCTAssertEqual(
            AboutViewModel.projectionText(LenientString("project:4-44:singleL")),
            "Projection control vector on layers 4–44 (layer L's direction). Per chat in Sampling. "
                + "Its package describes the vector as a refusal-direction projection; measure the speed yourself"
        )
        XCTAssertEqual(
            AboutViewModel.projectionText(LenientString("add:10-20")),
            "Additive control vector on layers 10–20. Per chat in Sampling. "
                + "Its package describes the vector as a refusal-direction projection; measure the speed yourself"
        )
    }

    // MARK: - hardware

    func testHardwareFacts() throws {
        let m = model(generating)
        XCTAssertEqual(
            value(m, "Hardware", "GPU"),
            "NVIDIA GeForce RTX 5070 Ti + NVIDIA GeForce RTX 5070 Ti, 32 GB"
        )
        XCTAssertEqual(value(m, "Hardware", "CPU"), "AMD Ryzen 7 5800X3D 8-Core Processor, 16 threads")
        XCTAssertEqual(value(m, "Hardware", "RAM"), "61 GB")
    }

    func testGPUNotReadableIsStatedPlainly() throws {
        let m = AboutViewModel(metrics: Metrics(), baseURL: nil, locale: locale)
        XCTAssertEqual(value(m, "Hardware", "GPU"), "not readable (NVML)")
        XCTAssertNil(value(m, "Hardware", "CPU"))
        XCTAssertNil(value(m, "Hardware", "RAM"))
    }

    // MARK: - API

    func testAPICopyRows() throws {
        let m = model(generating)
        let rows = facts(m, "API")
        XCTAssertEqual(rows.map(\.label), ["OpenAI base URL", "Anthropic base URL", "Model name"])
        XCTAssertEqual(rows[0].value, "http://192.168.1.10:8081/v1")
        XCTAssertEqual(rows[0].copyValue, "http://192.168.1.10:8081/v1")
        XCTAssertEqual(rows[1].value, "http://192.168.1.10:8081")
        XCTAssertEqual(rows[1].copyValue, "http://192.168.1.10:8081")
        XCTAssertEqual(rows[2].copyValue, "qwen3.8-flash-next-iq3_xxs")
        XCTAssertTrue(facts(m, "Engine").allSatisfy { $0.copyValue == nil }, "only API rows get a copy button")
    }

    func testBaseStringStripsOneTrailingSlash() {
        XCTAssertEqual(AboutViewModel.baseString(URL(string: "http://192.168.1.10:8081/")), "http://192.168.1.10:8081")
        XCTAssertEqual(AboutViewModel.baseString(URL(string: "https://example.com")), "https://example.com")
        XCTAssertNil(AboutViewModel.baseString(nil))
    }

    // MARK: - the screen as a whole

    func testRepositoryLinkAndEmptyState() {
        let empty = AboutViewModel(metrics: nil, baseURL: nil, locale: locale)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.repositoryURL.absoluteString, "https://github.com/Niko1221/Strata")
        XCTAssertFalse(model(generating).isEmpty)
    }
}
