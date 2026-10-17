import XCTest
@testable import StrataCore

/// The iPad/phone layout decision, kept out of the views so it can be checked directly.
final class MonitorLayoutTests: XCTestCase {
    func testMetricColumns() {
        // iPhone: two tiles per row.
        XCTAssertEqual(MonitorLayout.metricColumns(compact: true, width: 402, isAccessibilityText: false), 2)
        XCTAssertEqual(MonitorLayout.metricColumns(compact: true, width: 390, isAccessibilityText: false), 2)
        // A narrow Split View or a small phone cannot fit two 160-point tiles.
        XCTAssertEqual(MonitorLayout.metricColumns(compact: true, width: 320, isAccessibilityText: false), 1)
        XCTAssertEqual(MonitorLayout.metricColumns(compact: true, width: 0, isAccessibilityText: false), 1)

        // iPad Pro 13": 1024 in portrait, 1366 in landscape — four columns either way.
        XCTAssertEqual(MonitorLayout.metricColumns(compact: false, width: 1024, isAccessibilityText: false), 4)
        XCTAssertEqual(MonitorLayout.metricColumns(compact: false, width: 1366, isAccessibilityText: false), 4)
        // A regular-width split that cannot fit four tiles gets three, not a squeezed four.
        XCTAssertEqual(MonitorLayout.metricColumns(compact: false, width: 640, isAccessibilityText: false), 3)

        // Accessibility text sizes always collapse to one column.
        XCTAssertEqual(MonitorLayout.metricColumns(compact: false, width: 1366, isAccessibilityText: true), 1)
        XCTAssertEqual(MonitorLayout.metricColumns(compact: true, width: 402, isAccessibilityText: true), 1)
    }

    func testLayoutMode() {
        let ipad = MonitorLayout(horizontalSizeClass: .regular, width: 1024, isAccessibilityText: false)
        XCTAssertTrue(ipad.isRegularWidth)
        XCTAssertTrue(ipad.isWide, "table and side-by-side cards")
        XCTAssertEqual(ipad.columns, 4)
        XCTAssertEqual(ipad.gridColumns.count, 4)
        XCTAssertEqual(ipad.sparklineHeight, 48, "charts need more height at tile width")

        let phone = MonitorLayout(horizontalSizeClass: .compact, width: 402, isAccessibilityText: false)
        XCTAssertFalse(phone.isWide)
        XCTAssertEqual(phone.columns, 2)
        XCTAssertEqual(phone.sparklineHeight, 34)

        // Split View hands over a compact size class: fall back to the phone layout.
        let split = MonitorLayout(horizontalSizeClass: .compact, width: 512, isAccessibilityText: false)
        XCTAssertFalse(split.isWide)
        XCTAssertEqual(split.columns, 2)

        // iPad with accessibility text: one column and the compact rows again.
        let ax = MonitorLayout(horizontalSizeClass: .regular, width: 1366, isAccessibilityText: true)
        XCTAssertFalse(ax.isWide)
        XCTAssertEqual(ax.columns, 1)
        XCTAssertEqual(ax.sparklineHeight, 34)

        // No size class reported is treated as compact.
        XCTAssertEqual(MonitorLayout(horizontalSizeClass: nil, width: 402, isAccessibilityText: false).columns, 2)
    }

    func testWidthCaps() {
        XCTAssertEqual(MonitorLayout.contentMaxWidth, 1_200)
        XCTAssertEqual(MonitorLayout.formMaxWidth, 720)
        XCTAssertLessThan(MonitorLayout.formMaxWidth, MonitorLayout.contentMaxWidth)
    }
}
