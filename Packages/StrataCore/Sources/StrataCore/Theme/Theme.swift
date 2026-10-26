import SwiftUI

/// The "Mission control" palette: dark-first, glowing cyan for Strata, ember orange for Basalt.
///
/// Every colour the app draws comes from here — the hex literals in this file are the only ones
/// in the project. A `Theme` is resolved once per colour scheme and injected through
/// `@Environment(\.theme)`, so views never branch on light/dark — or on the engine — themselves.
public struct Theme: Sendable, Equatable {
    public let scheme: ColorScheme

    /// The raw token values, kept as hex so tests can check them and their contrast.
    public struct Raw: Sendable, Equatable {
        public let background: UInt32
        public let headerGlow: UInt32
        public let headerGlowAlpha: Double
        public let cardTop: UInt32
        public let cardBottom: UInt32
        public let cardOpacity: Double
        public let cardBorder: UInt32
        public let cardBorderAlpha: Double
        public let cardHighlightAlpha: Double
        public let textPrimary: UInt32
        public let textSecondary: UInt32
        public let textTertiary: UInt32
        public let accent: UInt32
        public let accentDim: UInt32
        public let warn: UInt32
        public let danger: UInt32
        public let track: UInt32
        public let separatorBase: UInt32
        public let separatorAlpha: Double
    }

    public let raw: Raw

    // MARK: resolved colours

    public let background: Color
    /// The radial wash behind the top of every screen.
    public let headerGlow: Color
    public let cardBorder: Color
    public let cardHighlight: Color
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let accent: Color
    public let accentDim: Color
    public let warn: Color
    public let danger: Color
    /// The same hues as `accent` / `warn` / `danger`, darkened where necessary so they clear
    /// 4.5:1 as *text* on cards and background. The table's own values are too pale for text in
    /// light (accent 3.7:1, warn 3.3:1), so graphics use the table colours and text uses these.
    public let accentText: Color
    public let warnText: Color
    public let dangerText: Color
    /// The hex behind those text variants, so the contrast tests can check them.
    public let rawAccentText: UInt32
    public let rawWarnText: UInt32
    public let rawDangerText: UInt32
    public let track: Color
    public let separator: Color

    // MARK: shape

    public let cardRadius: CGFloat = 16
    public let barHeight: CGFloat = 6
    public let barRadius: CGFloat = 3
    public let hairline: CGFloat = 1
    /// How far the top scrim reaches down from the top edge of the screen.
    public static let topScrimDepth: CGFloat = 24

    /// Cards: a top-to-bottom gradient, 92% opaque in dark so the glow shows through.
    public var cardFill: LinearGradient {
        LinearGradient(
            colors: [Color(hex: raw.cardTop, alpha: raw.cardOpacity), Color(hex: raw.cardBottom, alpha: raw.cardOpacity)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Bar fill: the dim end of the accent into the bright end.
    public var barFill: LinearGradient {
        LinearGradient(colors: [accentDim, accent], startPoint: .leading, endPoint: .trailing)
    }

    /// Sparkline area: accent at 35% fading to nothing.
    public var areaFill: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.35), accent.opacity(0)], startPoint: .top, endPoint: .bottom)
    }

    // MARK: glow

    public var hasGlow: Bool { scheme == .dark }
    public var glowColor: Color { accent.opacity(0.55) }
    public var glowRadius: CGFloat { scheme == .dark ? 6 : 0 }

    /// The same glow, tightened for sparklines so the 1 s redraw stays cheap.
    public var lineGlowRadius: CGFloat { scheme == .dark ? 3 : 0 }

    // MARK: type

    public var titleFont: Font { .system(size: 30, weight: .semibold) }
    public var titleTracking: CGFloat { -0.5 }
    public var metricValueSize: CGFloat { 26 }
    /// The Speed tile carries two numbers. At 26 pt "103.8 t/s  298 t/s" does not fit a phone
    /// tile, so a paired value drops to 22 pt there; a regular-width tile is wide enough for 26.
    public var pairedMetricValueSize: CGFloat { 26 }
    public var pairedMetricValueSizeCompact: CGFloat { 22 }
    public var metricValueFont: Font { .system(size: metricValueSize, weight: .semibold, design: .monospaced) }
    /// The menu bar popover is 360 points wide with two tiles in it: 20 pt, not 26.
    public var menuBarMetricValueSize: CGFloat { 20 }

    public func metricValueSize(paired: Bool, compact: Bool, variant: MetricTileVariant = .screen) -> CGFloat {
        switch variant {
        case .menuBar: return menuBarMetricValueSize
        case .screen: return paired && compact ? pairedMetricValueSizeCompact : metricValueSize
        }
    }

    public func valueFont(paired: Bool, compact: Bool, variant: MetricTileVariant = .screen) -> Font {
        .system(size: metricValueSize(paired: paired, compact: compact, variant: variant),
                weight: .semibold, design: .monospaced)
    }

    public var tileLabelFont: Font { .system(size: 12, weight: .medium) }
    public var tileLabelTracking: CGFloat { 0.5 }
    public var subFont: Font { .system(size: 11) }
    public var badgeFont: Font { .system(size: 11, weight: .medium) }
    public var gaugeFont: Font { .system(size: 22, weight: .semibold, design: .monospaced) }

    /// Which server the palette brands: Strata's glowing cyan, or Basalt's ember orange.
    public let engine: ServerEngine

    public init(scheme: ColorScheme, engine: ServerEngine = .strata) {
        let dark = scheme == .dark
        self.scheme = scheme
        self.engine = engine
        let text: (accent: UInt32, warn: UInt32, danger: UInt32)
        switch engine {
        case .strata:
            self.raw = Raw(
                background: dark ? 0x070B14 : 0xF3F6FB,
                headerGlow: dark ? 0x1FB8DD : 0x0A8FB5,
                headerGlowAlpha: dark ? 0.22 : 0.12,
                cardTop: dark ? 0x121B2E : 0xFFFFFF,
                cardBottom: dark ? 0x0B111F : 0xFFFFFF,
                cardOpacity: dark ? 0.92 : 1,
                cardBorder: dark ? 0x4FE3FF : 0x0A8FB5,
                cardBorderAlpha: dark ? 0.14 : 0.16,
                cardHighlightAlpha: dark ? 0.04 : 0.03,
                textPrimary: dark ? 0xE6EDF7 : 0x0E1726,
                textSecondary: dark ? 0x8FA3BF : 0x5B6B82,
                // The table says #7B8AA0; that is 3.2:1 on the light background, so light tertiary
                // is the same hue pushed to 4.8:1. Dark keeps the table value (4.8:1 on a card).
                textTertiary: dark ? 0x6E82A0 : 0x5E6D82,
                accent: dark ? 0x4FE3FF : 0x0A8FB5,
                accentDim: dark ? 0x1FB8DD : 0x0B7A9C,
                warn: dark ? 0xFFB454 : 0xC77A14,
                danger: dark ? 0xFF5C7A : 0xC8324F,
                track: dark ? 0x162034 : 0xE3E9F2,
                separatorBase: dark ? 0xFFFFFF : 0x000000,
                separatorAlpha: dark ? 0.06 : 0.07
            )
            // #C8324F already clears 4.5:1 in light.
            text = dark ? (0x4FE3FF, 0xFFB454, 0xFF5C7A) : (0x0A6E8C, 0x9A570A, 0xC8324F)
        case .basalt:
            // Basalt's web page (web/app.css): basalt greys, ember accent, a yellow warn so a
            // warning never reads as the accent. The page is dark only; light is the same hues on
            // a warm off-white. Dark cards sit a step darker than the page's #1A2128 surface, and
            // its #D93A5B error is brightened, so tertiary and danger text clear 4.5:1 on them.
            self.raw = Raw(
                background: dark ? 0x0E1114 : 0xF6F4F2,
                headerGlow: 0xF2662B,
                headerGlowAlpha: dark ? 0.16 : 0.10,
                cardTop: dark ? 0x171D23 : 0xFFFFFF,
                cardBottom: dark ? 0x12161A : 0xFFFFFF,
                cardOpacity: dark ? 0.92 : 1,
                cardBorder: dark ? 0xFF7A3D : 0xD9531F,
                cardBorderAlpha: dark ? 0.12 : 0.16,
                cardHighlightAlpha: dark ? 0.04 : 0.03,
                textPrimary: dark ? 0xE9ECEE : 0x14181C,
                textSecondary: dark ? 0x9AA4AD : 0x56616C,
                textTertiary: dark ? 0x808B95 : 0x5E6872,
                accent: dark ? 0xFF7A3D : 0xE8601F,
                accentDim: 0xB8401A,
                warn: dark ? 0xE9C341 : 0xC29A12,
                danger: dark ? 0xF25F7E : 0xC8324F,
                track: dark ? 0x222A32 : 0xECE7E3,
                separatorBase: dark ? 0xFFFFFF : 0x000000,
                separatorAlpha: dark ? 0.06 : 0.07
            )
            text = dark ? (0xFF7A3D, 0xE9C341, 0xF25F7E) : (0xB0400F, 0x7F6400, 0xC8324F)
        }

        self.background = Color(hex: raw.background)
        self.headerGlow = Color(hex: raw.headerGlow, alpha: raw.headerGlowAlpha)
        self.cardBorder = Color(hex: raw.cardBorder, alpha: raw.cardBorderAlpha)
        self.cardHighlight = Color(hex: 0xFFFFFF, alpha: raw.cardHighlightAlpha)
        self.textPrimary = Color(hex: raw.textPrimary)
        self.textSecondary = Color(hex: raw.textSecondary)
        self.textTertiary = Color(hex: raw.textTertiary)
        self.accent = Color(hex: raw.accent)
        self.accentDim = Color(hex: raw.accentDim)
        self.warn = Color(hex: raw.warn)
        self.danger = Color(hex: raw.danger)
        self.accentText = Color(hex: text.accent)
        self.warnText = Color(hex: text.warn)
        self.dangerText = Color(hex: text.danger)
        self.rawAccentText = text.accent
        self.rawWarnText = text.warn
        self.rawDangerText = text.danger
        self.track = Color(hex: raw.track)
        self.separator = Color(hex: raw.separatorBase, alpha: raw.separatorAlpha)
    }

    public static let dark = Theme(scheme: .dark)
    public static let light = Theme(scheme: .light)
}

// MARK: - environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .dark
}

extension EnvironmentValues {
    /// The resolved palette for the current colour scheme.
    public var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    /// Resolves the palette once, at the root, from the system colour scheme and the engine of the
    /// server on screen. `engine` is read while the modifier draws, so an observable model's
    /// engine repaints the screen when the server turns out to be Basalt.
    public func strataTheme(engine: @escaping @MainActor () -> ServerEngine = { .strata }) -> some View {
        modifier(StrataThemeModifier(engine: engine))
    }
}

private struct StrataThemeModifier: ViewModifier {
    let engine: @MainActor () -> ServerEngine
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.environment(\.theme, Theme(scheme: colorScheme, engine: engine()))
    }
}

// MARK: - status colours

extension MonitorStatus {
    /// Spec: idle grey (text secondary), reading and generating accent, queued warn, errors danger.
    public func color(in theme: Theme) -> Color {
        switch self {
        case .unknown, .idle, .modelUnloaded: theme.textSecondary
        case .reading, .generating: theme.accentText
        case .queued: theme.warnText
        case .unauthorized, .unreachable: theme.dangerText
        }
    }

    /// Only generating gets the pulsing dot.
    public var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }
}

extension MonitorViewModel.Tone {
    /// Bar / sparkline colour for a tone. `normal` and `info` are both the accent.
    func color(in theme: Theme) -> Color {
        switch self {
        case .normal, .info: theme.accent
        case .warn: theme.warn
        case .danger: theme.danger
        }
    }
}

// MARK: - shared card chrome

/// The card look as a standalone view: gradient fill, hairline border, inner top highlight.
public struct StrataCardBackground: View {
    private let theme: Theme

    public init(_ theme: Theme) {
        self.theme = theme
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: theme.cardRadius)
            .fill(theme.cardFill)
            .overlay(alignment: .top) {
                theme.cardHighlight
                    .frame(height: theme.hairline)
                    .padding(.horizontal, theme.cardRadius)
            }
            .overlay {
                RoundedRectangle(cornerRadius: theme.cardRadius)
                    .strokeBorder(theme.cardBorder, lineWidth: theme.hairline)
            }
    }
}

extension View {
    /// The card look: gradient fill, 1 pt hairline, 16 pt radius, inner top highlight.
    public func strataCard(_ theme: Theme, fillsHeight: Bool = false) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
            .background { StrataCardBackground(theme) }
    }
}

/// The screen title, drawn in the content so the theme controls its size and tracking.
public struct ScreenTitle: View {
    public let text: String
    @Environment(\.theme) private var theme

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(theme.titleFont)
            .tracking(theme.titleTracking)
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The screen background: the base colour plus the header glow behind the top of the view.
public struct ThemeBackground: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            theme.background
            RadialGradient(
                colors: [theme.headerGlow, .clear],
                center: .top,
                startRadius: 0,
                endRadius: max(geometry.size.height * 0.6, 1)
            )
        }
        .ignoresSafeArea()
    }
}

/// With the nav bar hidden, scrolled content runs under the status bar clock. This is a short
/// gradient of the background colour — opaque at the top edge, clear `topScrimDepth` points down —
/// pinned over the top of the screen so the clock always sits on the theme background.
public struct ThemeTopScrim: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            let inset = geometry.safeAreaInsets.top
            LinearGradient(stops: Self.stops(theme.background, safeAreaTop: inset), startPoint: .top, endPoint: .bottom)
                .frame(height: Self.height(safeAreaTop: inset))
                // The reader sits below the status bar; the band has to start above it.
                .offset(y: -inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    /// The status bar inset plus 24 pt, so the fade ends the same distance into the content
    /// whatever the device.
    nonisolated public static func height(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + Theme.topScrimDepth
    }

    /// Solid across the status bar — the clock has to sit on the theme background — then clear
    /// over the 24 pt below it.
    nonisolated public static func stops(_ background: Color, safeAreaTop: CGFloat) -> [Gradient.Stop] {
        let total = height(safeAreaTop: safeAreaTop)
        let hold = total > 0 ? safeAreaTop / total : 1
        return [
            Gradient.Stop(color: background, location: 0),
            Gradient.Stop(color: background, location: hold),
            Gradient.Stop(color: background.opacity(0), location: 1),
        ]
    }
}

extension View {
    /// Overlay the top scrim on a screen. Applied once, at the tab view, so every tab and both
    /// colour schemes get it.
    public func themeTopScrim() -> some View {
        overlay(alignment: .top) {
            // No ignoresSafeArea here: the scrim measures the inset, then offsets itself up.
            ThemeTopScrim()
        }
    }
}

// MARK: - hex

fileprivate extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
