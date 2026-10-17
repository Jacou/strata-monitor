import SwiftUI
import Charts

/// The web page's `spark(id, values, max)`: an area plus a line, scaled to `max` or the
/// biggest sample, whichever is larger.
public struct Sparkline: View {
    public let values: [Double]
    public let ceiling: Double?
    public let tint: Color
    /// Taller on a regular-width screen, where a 34-point chart looks flat inside a wide tile.
    public let height: CGFloat

    @Environment(\.theme) private var theme

    public init(values: [Double], ceiling: Double? = nil, tint: Color = .accentColor, height: CGFloat = 34) {
        self.values = values
        self.ceiling = ceiling
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        if values.count < 2 {
            // Nothing to connect — the web page clears the path too.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: height)
        } else {
            Chart {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    AreaMark(
                        x: .value("time", index),
                        y: .value("value", value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("time", index),
                        y: .value("value", value)
                    )
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
            }
            .chartYScale(domain: 0...top)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            // The glow is tightened to radius 3 so the 1 s redraw stays cheap, and the chart is
            // rasterised once per change rather than re-shadowed on every scrolled frame.
            .shadow(color: theme.glowColor, radius: theme.lineGlowRadius)
            .drawingGroup()
            .frame(height: height)
            .accessibilityHidden(true)   // VoiceOver gets the numbers from the tile, not the shape
        }
    }

    private var top: Double {
        max(ceiling ?? 0, values.filter(\.isFinite).max() ?? 0, 1e-9)
    }
}
