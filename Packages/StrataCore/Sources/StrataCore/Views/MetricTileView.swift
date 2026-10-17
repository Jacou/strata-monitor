import SwiftUI

/// How big a tile is drawn. The Monitor grid and the macOS popover share the same tile, not the
/// same type scale.
public enum MetricTileVariant: Sendable, Equatable {
    /// The iPhone / iPad Monitor grid: 26 pt values, 22 when a tile carries two numbers.
    case screen
    /// The menu bar popover: 20 pt values in a 360-point window.
    case menuBar
}

/// One metric tile: label, value + unit, sub-line, sparkline. Speed carries decode and prefill.
/// Every tile in a row stretches to the row's height and pins its sparkline to the bottom,
/// so neighbours line up instead of ending at different depths.
public struct MetricTileView: View {
    public let metric: MonitorViewModel.Metric
    public let sparklineHeight: CGFloat
    /// A phone tile is narrow; a paired tile there needs the smaller value size.
    public let compact: Bool
    public let variant: MetricTileVariant

    @Environment(\.theme) private var theme

    public init(
        metric: MonitorViewModel.Metric,
        sparklineHeight: CGFloat = 34,
        compact: Bool = true,
        variant: MetricTileVariant = .screen
    ) {
        self.metric = metric
        self.sparklineHeight = sparklineHeight
        self.compact = compact
        self.variant = variant
    }

    public var body: some View {
        let valueColor = metricValueColor(metric, theme)
        let lineColor = metric.tone.color(in: theme)

        VStack(alignment: .leading, spacing: 6) {
            Text(metric.label.uppercased())
                .font(theme.tileLabelFont)
                .tracking(theme.tileLabelTracking)
                .foregroundStyle(theme.textSecondary)

            if let secondary = metric.secondary {
                HStack(alignment: .top, spacing: 12) {
                    value(metric.value, metric.unit, metric.sub, color: valueColor)
                    value(secondary.value, secondary.unit, secondary.sub, color: theme.textPrimary)
                }
            } else {
                value(metric.value, metric.unit, metric.sub, color: valueColor)
            }

            Spacer(minLength: 0)

            if let secondary = metric.secondary {
                HStack(spacing: 6) {
                    Sparkline(values: metric.series, ceiling: metric.seriesMax, tint: lineColor,
                              height: sparklineHeight)
                    Sparkline(values: secondary.series, ceiling: secondary.seriesMax,
                              tint: lineColor.opacity(0.55), height: sparklineHeight)
                }
            } else {
                Sparkline(values: metric.series, ceiling: metric.seriesMax, tint: lineColor,
                          height: sparklineHeight)
            }
        }
        .strataCard(theme)
        .accessibilityElement()
        .accessibilityLabel(metric.accessibilityLabel)
    }

    @ViewBuilder
    private func value(_ text: String, _ unit: String, _ sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(text)
                    .font(theme.valueFont(paired: metric.secondary != nil, compact: compact, variant: variant))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .shadow(color: theme.glowColor, radius: theme.glowRadius)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)   // "109.3" shrinks instead of breaking in half
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize()
                }
            }
            if !sub.isEmpty {
                Text(sub)
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Which colour a tile's headline value gets: Speed decode in accent, GPU temp in warn,
/// everything else in primary text.
func metricValueColor(_ metric: MonitorViewModel.Metric, _ theme: Theme) -> Color {
    if metric.kind == .speed { return theme.accentText }
    switch metric.tone {
    case .warn: return theme.warnText
    case .danger: return theme.dangerText
    case .normal, .info: return theme.textPrimary
    }
}

extension MonitorViewModel.MetricKind {
    var symbol: String {
        switch self {
        case .speed: "speedometer"
        case .gpu: "display"
        case .vram: "square.stack.3d.up"
        case .temp: "thermometer"
        case .power: "bolt.fill"
        case .pcie: "link"
        case .cpu: "cpu"
        case .disk: "internaldrive"
        }
    }
}
