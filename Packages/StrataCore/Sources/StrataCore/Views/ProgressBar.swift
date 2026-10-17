import SwiftUI

/// A thin bar with the same meaning as the web page's `style.width = "N%"`.
public struct ProgressBar: View {
    public let percent: Double
    public let tone: MonitorViewModel.Tone

    @Environment(\.theme) private var theme

    public init(percent: Double, tone: MonitorViewModel.Tone = .normal) {
        self.percent = Self.clamped(percent)
        self.tone = tone
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: theme.barRadius)
                    .fill(theme.track)

                // 0% draws nothing: a 2-point sliver of colour would read as "a little progress".
                if percent > 0 {
                    RoundedRectangle(cornerRadius: theme.barRadius)
                        .fill(theme.barFill)
                        .frame(width: max(geometry.size.width * percent / 100, theme.barHeight))
                        .shadow(color: theme.glowColor, radius: theme.glowRadius)
                }
            }
        }
        .frame(height: theme.barHeight)
        .accessibilityElement()
        .accessibilityLabel("\(Int(percent)) percent")
    }

    /// 0...1 of the bar to fill. A missing or wild value fills nothing.
    nonisolated public static func fillRatio(_ percent: Double) -> Double {
        clamped(percent) / 100
    }

    private nonisolated static func clamped(_ percent: Double) -> Double {
        guard percent.isFinite else { return 0 }
        return Swift.min(Swift.max(percent, 0), 100)
    }
}
