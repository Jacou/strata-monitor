import SwiftUI

/// Context gauge, expert cache bar, RAM bar (red above 92%), GPU temperature bar.
public struct ResourcesCard: View {
    public let context: MonitorViewModel.Context
    public let experts: MonitorViewModel.Bar
    public let ram: MonitorViewModel.Bar
    public let temp: MonitorViewModel.Bar
    /// In the wide layout the card shares a row with the conversation cache; this is what makes
    /// the card's background stretch to the row's height instead of stopping short.
    public let fillsHeight: Bool

    @Environment(\.theme) private var theme

    public init(
        context: MonitorViewModel.Context,
        experts: MonitorViewModel.Bar,
        ram: MonitorViewModel.Bar,
        temp: MonitorViewModel.Bar,
        fillsHeight: Bool = false
    ) {
        self.context = context
        self.experts = experts
        self.ram = ram
        self.temp = temp
        self.fillsHeight = fillsHeight
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ring
            VStack(alignment: .leading, spacing: 12) {
                bar("Expert cache", experts)
                bar("RAM", ram)
                bar("GPU temp", temp)
            }
        }
        .strataCard(theme, fillsHeight: fillsHeight)
    }

    // MARK: - the ring: a 270° gauge open at the bottom, like the web page's 235.6 of 314.2

    private static let ringSize: CGFloat = 108
    private static let ringLineWidth: CGFloat = 8
    private static let gaugeSpan: CGFloat = 0.75      // 270° of the circle
    /// A Circle starts at 3 o'clock and sweeps clockwise. Rotating 135° moves the arc to start at
    /// 7:30, run clockwise over the top and end at 4:30, leaving the gap at the bottom.
    private static let gaugeRotation: Angle = .degrees(135)

    private var ring: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: Self.gaugeSpan)
                .stroke(theme.track, style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round))
                .rotationEffect(Self.gaugeRotation)

            if ringArcIsDrawn(fraction: context.fraction, lineWidth: Self.ringLineWidth) {
                Circle()
                    .trim(from: 0, to: Self.gaugeSpan * context.fraction)
                    .stroke(
                        context.fraction > 0.9 ? theme.danger : theme.accent,
                        style: StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round)
                    )
                    .rotationEffect(Self.gaugeRotation)
                    .shadow(color: theme.glowColor, radius: theme.glowRadius)
            }

            VStack(spacing: 1) {
                Text(context.percentText)
                    .font(theme.gaugeFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Text(context.sub)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(12)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityElement()
        .accessibilityLabel("Context \(context.percentText), \(context.sub)")
    }

    @ViewBuilder
    private func bar(_ label: String, _ bar: MonitorViewModel.Bar) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 4)
                Text(bar.text)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(bar.tone == .danger ? theme.dangerText : theme.textPrimary)
            }
            ProgressBar(percent: bar.percent, tone: bar.tone)
        }
    }
}

/// The web page draws `stroke-dasharray: (235.6 * frac) 314.2` and hides an arc shorter than
/// 3 units. We also hide one shorter than the stroke width, so a round cap cannot read as a blob.
func ringArcIsDrawn(
    fraction: Double,
    lineWidth: CGFloat,
    circumference: Double = 314.16,
    gaugeSpan: Double = 0.75
) -> Bool {
    guard fraction.isFinite, fraction > 0 else { return false }
    let arcLength = circumference * gaugeSpan * Swift.min(fraction, 1)
    return arcLength >= 3 && arcLength >= Double(lineWidth)
}
