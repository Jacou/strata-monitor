import XCTest
@testable import StrataCore

/// The small pieces of view logic: empty bars, the ring arc, tile value colours, and the
/// "updated / last data" caption. (Pill colours live in ThemeTests.)
final class MonitorChromeTests: XCTestCase {
    private let dark = Theme(scheme: .dark)
    private let light = Theme(scheme: .light)

    private func metric(_ kind: MonitorViewModel.MetricKind, tone: MonitorViewModel.Tone = .normal) -> MonitorViewModel.Metric {
        MonitorViewModel.Metric(kind: kind, label: kind.rawValue, value: "1", unit: "", sub: "",
                                series: [], seriesMax: nil, tone: tone, secondary: nil)
    }

    func testTileValueColours() {
        for theme in [dark, light] {
            // Speed decode is the headline number: accent, with the glow.
            XCTAssertEqual(metricValueColor(metric(.speed), theme), theme.accentText)
            // Temperature is the one warning colour on the grid.
            XCTAssertEqual(metricValueColor(metric(.temp, tone: .warn), theme), theme.warnText)
            XCTAssertEqual(metricValueColor(metric(.vram), theme), theme.textPrimary)
            XCTAssertEqual(metricValueColor(metric(.pcie, tone: .info), theme), theme.textPrimary)
        }
    }

    func testProgressBarFillRatio() {
        XCTAssertEqual(ProgressBar.fillRatio(0), 0, "0% draws nothing, not a sliver")
        XCTAssertEqual(ProgressBar.fillRatio(0.4), 0.004, accuracy: 0.000001)
        XCTAssertEqual(ProgressBar.fillRatio(50), 0.5, accuracy: 0.000001)
        XCTAssertEqual(ProgressBar.fillRatio(100), 1)
        XCTAssertEqual(ProgressBar.fillRatio(140), 1, "clamped to the card")
        XCTAssertEqual(ProgressBar.fillRatio(-5), 0)
        XCTAssertEqual(ProgressBar.fillRatio(Double.nan), 0)
        XCTAssertEqual(ProgressBar.fillRatio(Double.infinity), 0)
    }

    func testContextRingHidesTinyArcs() {
        // 2% of the context: 314.16 × 0.75 × 0.0187 ≈ 4.4 units — shorter than the 8-point stroke,
        // so a round cap would read as a blob.
        XCTAssertFalse(ringArcIsDrawn(fraction: 0.018_7, lineWidth: 8))
        XCTAssertTrue(ringArcIsDrawn(fraction: 0.05, lineWidth: 8))
        XCTAssertTrue(ringArcIsDrawn(fraction: 1, lineWidth: 8))
        XCTAssertFalse(ringArcIsDrawn(fraction: 0, lineWidth: 8))
        XCTAssertFalse(ringArcIsDrawn(fraction: -1, lineWidth: 8))
        XCTAssertFalse(ringArcIsDrawn(fraction: Double.nan, lineWidth: 8))

        // the web page's own cut-off: an arc shorter than 3 of 314.2 units
        XCTAssertTrue(ringArcIsDrawn(fraction: 0.012_8, lineWidth: 1))
        XCTAssertFalse(ringArcIsDrawn(fraction: 0.012_7, lineWidth: 1))
    }

    func testMetricTilesSpeakOnePhrase() {
        let speed = MonitorViewModel.Metric(
            kind: .speed, label: "Speed", value: "98.5", unit: "t/s", sub: "Decode last request",
            series: [], seriesMax: nil, tone: .normal,
            secondary: .init(value: "84", unit: "t/s", sub: "Prefill last request", series: [], seriesMax: nil)
        )
        XCTAssertEqual(
            speed.accessibilityLabel,
            "Speed, 98.5 tokens per second, Decode last request, 84 tokens per second, Prefill last request"
        )

        let vram = MonitorViewModel.Metric(
            kind: .vram, label: "VRAM", value: "31.4", unit: "/ 32 GB", sub: "",
            series: [], seriesMax: nil, tone: .normal, secondary: nil
        )
        XCTAssertEqual(vram.accessibilityLabel, "VRAM, 31.4 of 32 GB")

        let missing = MonitorViewModel.Metric(
            kind: .disk, label: "Disk read", value: notAvailable, unit: "MB/s", sub: "",
            series: [], seriesMax: nil, tone: .info, secondary: nil
        )
        XCTAssertEqual(missing.accessibilityLabel, "Disk read, no value reported")
    }

    func testSpokenUnits() {
        XCTAssertEqual(MonitorViewModel.spoken("98.5", "t/s"), "98.5 tokens per second")
        XCTAssertEqual(MonitorViewModel.spoken("0", "%"), "0 percent")
        XCTAssertEqual(MonitorViewModel.spoken("80", "W"), "80 watts")
        XCTAssertEqual(MonitorViewModel.spoken("41", "°C"), "41 degrees Celsius")
        XCTAssertEqual(MonitorViewModel.spoken("1.2", "MB/s"), "1.2 megabytes per second")
        XCTAssertEqual(MonitorViewModel.spoken("31.4", "/ 32 GB"), "31.4 of 32 GB")
        XCTAssertEqual(MonitorViewModel.spoken("Gen4", "x4"), "Gen4 x4")
        XCTAssertEqual(MonitorViewModel.spoken("Gen4", ""), "Gen4")
    }
}
