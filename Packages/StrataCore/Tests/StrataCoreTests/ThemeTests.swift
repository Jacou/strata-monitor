import XCTest
import SwiftUI
@testable import StrataCore

/// The token table from docs/TASKS.md, and the status → colour mapping.
final class ThemeTests: XCTestCase {
    private let dark = Theme(scheme: .dark)
    private let light = Theme(scheme: .light)

    // MARK: - tokens

    func testDarkTokens() {
        XCTAssertEqual(dark.raw.background, 0x070B14)
        XCTAssertEqual(dark.raw.headerGlow, 0x1FB8DD)
        XCTAssertEqual(dark.raw.headerGlowAlpha, 0.22, accuracy: 0.001)
        XCTAssertEqual(dark.raw.cardTop, 0x121B2E)
        XCTAssertEqual(dark.raw.cardBottom, 0x0B111F)
        XCTAssertEqual(dark.raw.cardOpacity, 0.92, accuracy: 0.001)
        XCTAssertEqual(dark.raw.cardBorder, 0x4FE3FF)
        XCTAssertEqual(dark.raw.cardBorderAlpha, 0.14, accuracy: 0.001)
        XCTAssertEqual(dark.raw.textPrimary, 0xE6EDF7)
        XCTAssertEqual(dark.raw.textSecondary, 0x8FA3BF)
        XCTAssertEqual(dark.raw.textTertiary, 0x6E82A0)
        XCTAssertEqual(dark.raw.accent, 0x4FE3FF)
        XCTAssertEqual(dark.raw.accentDim, 0x1FB8DD)
        XCTAssertEqual(dark.raw.warn, 0xFFB454)
        XCTAssertEqual(dark.raw.danger, 0xFF5C7A)
        XCTAssertEqual(dark.raw.track, 0x162034)
        XCTAssertEqual(dark.raw.separatorBase, 0xFFFFFF)
        XCTAssertEqual(dark.raw.separatorAlpha, 0.06, accuracy: 0.001)
    }

    func testLightTokens() {
        XCTAssertEqual(light.raw.background, 0xF3F6FB)
        XCTAssertEqual(light.raw.headerGlow, 0x0A8FB5)
        XCTAssertEqual(light.raw.headerGlowAlpha, 0.12, accuracy: 0.001)
        XCTAssertEqual(light.raw.cardTop, 0xFFFFFF)
        XCTAssertEqual(light.raw.cardBottom, 0xFFFFFF)
        XCTAssertEqual(light.raw.cardOpacity, 1, accuracy: 0.001)
        XCTAssertEqual(light.raw.cardBorder, 0x0A8FB5)
        XCTAssertEqual(light.raw.cardBorderAlpha, 0.16, accuracy: 0.001)
        XCTAssertEqual(light.raw.textPrimary, 0x0E1726)
        XCTAssertEqual(light.raw.textSecondary, 0x5B6B82)
        // Documented deviation: the table's #7B8AA0 is 3.2:1 on the light background.
        XCTAssertEqual(light.raw.textTertiary, 0x5E6D82)
        XCTAssertEqual(light.raw.accent, 0x0A8FB5)
        XCTAssertEqual(light.raw.accentDim, 0x0B7A9C)
        XCTAssertEqual(light.raw.warn, 0xC77A14)
        XCTAssertEqual(light.raw.danger, 0xC8324F)
        XCTAssertEqual(light.raw.track, 0xE3E9F2)
        XCTAssertEqual(light.raw.separatorBase, 0x000000)
        XCTAssertEqual(light.raw.separatorAlpha, 0.07, accuracy: 0.001)
    }

    func testShapeTokens() {
        for theme in [dark, light] {
            XCTAssertEqual(theme.cardRadius, 16)
            XCTAssertEqual(theme.barHeight, 6)
            XCTAssertEqual(theme.barRadius, 3)
            XCTAssertEqual(theme.hairline, 1)
        }
    }

    func testGlowOnlyInDark() {
        XCTAssertTrue(dark.hasGlow)
        XCTAssertEqual(dark.glowRadius, 6)
        XCTAssertEqual(dark.glowColor, dark.accent.opacity(0.55))
        XCTAssertFalse(light.hasGlow)
        XCTAssertEqual(light.glowRadius, 0)
        XCTAssertEqual(light.lineGlowRadius, 0)
    }

    func testTypeTokens() {
        // Sizes the spec calls out; the fonts themselves are system SF, monospaced digits for numbers.
        XCTAssertEqual(dark.metricValueFont, Font.system(size: 26, weight: .semibold, design: .monospaced))
        XCTAssertEqual(dark.gaugeFont, Font.system(size: 22, weight: .semibold, design: .monospaced))
        XCTAssertEqual(dark.titleFont, Font.system(size: 30, weight: .semibold))
        XCTAssertEqual(dark.titleTracking, -0.5)
        XCTAssertEqual(dark.tileLabelFont, Font.system(size: 12, weight: .medium))
        XCTAssertEqual(dark.tileLabelTracking, 0.5)
        XCTAssertEqual(dark.subFont, Font.system(size: 11))
        XCTAssertEqual(dark.badgeFont, Font.system(size: 11, weight: .medium))

        // A paired tile (Speed) drops to 22 pt on a compact width so "103.8 t/s  298 t/s" fits.
        XCTAssertEqual(dark.metricValueSize, 26)
        XCTAssertEqual(dark.pairedMetricValueSize, 26)
        XCTAssertEqual(dark.pairedMetricValueSizeCompact, 22)
        XCTAssertEqual(dark.valueFont(paired: true, compact: true),
                       Font.system(size: 22, weight: .semibold, design: .monospaced))
        XCTAssertEqual(dark.valueFont(paired: true, compact: false),
                       Font.system(size: 26, weight: .semibold, design: .monospaced))
        XCTAssertEqual(dark.valueFont(paired: false, compact: true),
                       Font.system(size: 26, weight: .semibold, design: .monospaced))
    }

    // MARK: - status colours

    func testStatusColoursComeFromTheTheme() {
        for theme in [dark, light] {
            XCTAssertEqual(MonitorStatus.unknown.color(in: theme), theme.textSecondary)
            XCTAssertEqual(MonitorStatus.idle.color(in: theme), theme.textSecondary)
            XCTAssertEqual(MonitorStatus.reading(percent: 42).color(in: theme), theme.accentText)
            XCTAssertEqual(MonitorStatus.generating(tokS: 91.4).color(in: theme), theme.accentText)
            XCTAssertEqual(MonitorStatus.queued(2).color(in: theme), theme.warnText)
            XCTAssertEqual(MonitorStatus.unauthorized.color(in: theme), theme.dangerText)
            XCTAssertEqual(MonitorStatus.unreachable.color(in: theme), theme.dangerText)
        }
    }

    func testOnlyGeneratingPulses() {
        XCTAssertTrue(MonitorStatus.generating(tokS: 90).isGenerating)
        XCTAssertFalse(MonitorStatus.idle.isGenerating)
        XCTAssertFalse(MonitorStatus.reading(percent: 10).isGenerating)
        XCTAssertFalse(MonitorStatus.queued(1).isGenerating)
    }

    func testToneColours() {
        for theme in [dark, light] {
            XCTAssertEqual(MonitorViewModel.Tone.normal.color(in: theme), theme.accent)
            XCTAssertEqual(MonitorViewModel.Tone.info.color(in: theme), theme.accent)
            XCTAssertEqual(MonitorViewModel.Tone.warn.color(in: theme), theme.warn)
            XCTAssertEqual(MonitorViewModel.Tone.danger.color(in: theme), theme.danger)
        }
    }

    // MARK: - contrast (WCAG, every text/background pair must clear 4.5:1)

    func testTextContrast() {
        for theme in [dark, light] {
            let onBackground: [(UInt32, UInt32)] = [
                (theme.raw.textPrimary, theme.raw.background),
                (theme.raw.textSecondary, theme.raw.background),
                (theme.raw.textTertiary, theme.raw.background),
            ]
            let onCard: [(UInt32, UInt32)] = [
                (theme.raw.textPrimary, theme.raw.cardBottom),
                (theme.raw.textSecondary, theme.raw.cardBottom),
                (theme.raw.textTertiary, theme.raw.cardBottom),
                (theme.raw.textPrimary, theme.raw.cardTop),
            ]
            for (front, back) in onBackground + onCard {
                let ratio = Self.contrast(front, back)
                XCTAssertGreaterThanOrEqual(
                    ratio, 4.5,
                    String(format: "%06X on %06X is %.2f:1 in %@ (needs 4.5:1)",
                          front, back, ratio, theme.scheme == .dark ? "dark" : "light")
                )
            }
        }
    }

    /// Accent, warn and danger carry text too (pill, badges, Speed value), which is why the theme
    /// keeps text variants of them: the table's light accent is 3.7:1 and its light warn 3.3:1.
    func testTextVariantsClearContrast() {
        for theme in [dark, light] {
            for (name, hex) in [("accent", theme.rawAccentText), ("warn", theme.rawWarnText), ("danger", theme.rawDangerText)] {
                for background in [theme.raw.background, theme.raw.cardBottom, theme.raw.cardTop] {
                    let ratio = Self.contrast(hex, background)
                    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) text on \(String(format: "%06X", background)) is \(ratio):1")
                }
            }
        }
    }

    /// Tertiary text on a card in dark is the tightest pair in the table (~4.8:1).
    func testTightestPairIsStillComfortable() {
        XCTAssertGreaterThanOrEqual(Self.contrast(dark.raw.textTertiary, dark.raw.cardBottom), 4.7)
        XCTAssertGreaterThanOrEqual(Self.contrast(light.raw.textTertiary, light.raw.background), 4.7)
    }

    // MARK: - top scrim

    /// With the nav bar hidden, scrolled content runs under the status bar. The scrim is the
    /// background colour, opaque at the top edge and clear 24 pt into the content.
    func testTopScrimCoversTheStatusBarPlus24Points() {
        XCTAssertEqual(Theme.topScrimDepth, 24)
        XCTAssertEqual(ThemeTopScrim.height(safeAreaTop: 59), 83)     // iPhone with a notch
        XCTAssertEqual(ThemeTopScrim.height(safeAreaTop: 0), 24)      // an old device or a Mac window
        XCTAssertGreaterThan(ThemeTopScrim.height(safeAreaTop: 59), ThemeTopScrim.height(safeAreaTop: 0))

        let stops = ThemeTopScrim.stops(dark.background, safeAreaTop: 59)
        XCTAssertEqual(stops.count, 3)
        XCTAssertEqual(stops[0].location, 0)
        XCTAssertEqual(stops[1].location, 59 / 83, accuracy: 0.001, "solid across the status bar")
        XCTAssertEqual(stops[2].location, 1)
        XCTAssertEqual(stops[0].color, dark.background, "opaque at the top edge")
        XCTAssertEqual(stops[1].color, dark.background, "still opaque where the clock sits")
        XCTAssertEqual(stops[2].color, dark.background.opacity(0), "clear at the bottom of the fade")
        XCTAssertEqual(ThemeTopScrim.stops(light.background, safeAreaTop: 0).count, 3)
        XCTAssertEqual(ThemeTopScrim.stops(light.background, safeAreaTop: 0)[1].location, 0, "no status bar: the whole 24 pt is fade")
    }

    func testModelUnloadedIsSecondaryText() {
        for theme in [dark, light] {
            XCTAssertEqual(MonitorStatus.modelUnloaded.color(in: theme), theme.textSecondary,
                           "an unloaded model is a fact, not an alarm")
        }
    }

    // MARK: - WCAG relative luminance

    private static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let raw = Double((hex >> shift) & 0xFF) / 255
            return raw <= 0.03928 ? raw / 12.92 : pow((raw + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        let lighter = max(la, lb), darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
