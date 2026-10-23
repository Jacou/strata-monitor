import XCTest
@testable import StrataCore

/// The menu bar item's text, symbol and tooltip.
final class MenuBarLabelTests: XCTestCase {
    func testGeneratingShowsTheNumberNotTheWord() {
        XCTAssertEqual(MenuBarLabel.text(for: .generating(tokS: 104.3)), "104 t/s")
        XCTAssertEqual(MenuBarLabel.text(for: .generating(tokS: 9.6)), "10 t/s")
        XCTAssertEqual(MenuBarLabel.text(for: .generating(tokS: nil)), "generating")
    }

    func testReadingShowsThePercent() {
        XCTAssertEqual(MenuBarLabel.text(for: .reading(percent: 42)), "42%")
        XCTAssertEqual(MenuBarLabel.text(for: .reading(percent: nil)), "reading")
    }

    func testIdleShowsNothing() {
        XCTAssertEqual(MenuBarLabel.text(for: .idle), "")
        XCTAssertEqual(MenuBarLabel.text(for: .unknown), "")
        XCTAssertEqual(MenuBarLabel.text(for: .modelUnloaded), "")
    }

    func testBrokenShowsADash() {
        // The same dash the rest of the app uses for "no value".
        XCTAssertEqual(MenuBarLabel.text(for: .unreachable), notAvailable)
        XCTAssertEqual(MenuBarLabel.text(for: .unauthorized), notAvailable)
    }

    func testQueuedShowsTheCount() {
        XCTAssertEqual(MenuBarLabel.text(for: .queued(2)), "2 queued")
    }

    func testEveryStateHasASymbol() {
        XCTAssertEqual(MenuBarLabel.symbol(for: .idle), "pause.circle")
        XCTAssertEqual(MenuBarLabel.symbol(for: .reading(percent: 42)), "text.magnifyingglass")
        XCTAssertEqual(MenuBarLabel.symbol(for: .generating(tokS: 104)), "bolt.fill")
        XCTAssertEqual(MenuBarLabel.symbol(for: .unreachable), "exclamationmark.triangle")
        XCTAssertEqual(MenuBarLabel.symbol(for: .unauthorized), "exclamationmark.triangle")
        XCTAssertEqual(MenuBarLabel.symbol(for: .queued(1)), "hourglass")
        XCTAssertEqual(MenuBarLabel.symbol(for: .modelUnloaded), "square.stack.3d.up.slash")
        XCTAssertEqual(MenuBarLabel.symbol(for: .unknown), "antenna.radiowaves.left.and.right")
    }

    func testTooltipNamesTheModelAndTheLastRequest() throws {
        let metrics = try Fixtures.metrics(named: "metrics_generating", testClass: type(of: self))
        let row = try XCTUnwrap(MonitorViewModel(metrics: metrics).requests.first)
        let text = MenuBarLabel.tooltip(model: "Strata-Qwen3-32B", lastRow: row)
        XCTAssertTrue(text.hasPrefix("Strata-Qwen3-32B · last: "))
        XCTAssertTrue(text.contains(" t/s"))

        XCTAssertEqual(MenuBarLabel.tooltip(model: nil, lastRow: nil), "")
        XCTAssertEqual(MenuBarLabel.tooltip(model: "", lastRow: nil), "")
    }

    func testPopoverTilesUseTheSmallerValueSize() {
        let theme = Theme(scheme: .dark)
        XCTAssertEqual(theme.metricValueSize(paired: false, compact: false, variant: .menuBar), 20)
        XCTAssertEqual(theme.metricValueSize(paired: true, compact: true, variant: .menuBar), 20)
        // Smaller than the phone tile, paired or not.
        XCTAssertLessThan(
            theme.metricValueSize(paired: true, compact: true, variant: .menuBar),
            theme.metricValueSize(paired: true, compact: true)
        )
        XCTAssertLessThan(
            theme.metricValueSize(paired: false, compact: false, variant: .menuBar),
            theme.metricValueSize(paired: false, compact: false)
        )
    }

    func testTagIsTheNameCutShort() {
        XCTAssertEqual(MenuBarLabel.tag(for: "Mac"), "Mac")
        XCTAssertEqual(MenuBarLabel.tag(for: "Mac Studio"), "Mac St")
        XCTAssertEqual(MenuBarLabel.tag(for: "  Studio  "), "Studio")
        XCTAssertEqual(MenuBarLabel.tag(for: "Big M4 Max"), "Big M4")
        XCTAssertEqual(MenuBarLabel.tag(for: "Mac   Pro"), "Mac", "no trailing space after the cut")
        XCTAssertEqual(MenuBarLabel.tag(for: ""), "")
    }
}
