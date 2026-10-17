import SwiftUI

/// The conversation cache: parked conversations, the memory they hold, and what has been reused.
public struct ConversationCacheCard: View {
    public let cache: MonitorViewModel.ConvCache
    /// See `ResourcesCard.fillsHeight`: the wide layout puts the two cards in one row.
    public let fillsHeight: Bool

    @Environment(\.theme) private var theme

    public init(cache: MonitorViewModel.ConvCache, fillsHeight: Bool = false) {
        self.cache = cache
        self.fillsHeight = fillsHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conversation cache")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(cache.enabled ? "on" : "last conversation only")
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }

            if cache.enabled {
                VStack(alignment: .leading, spacing: 10) {
                    bar("Slots", text: cache.slotsText, percent: cache.slotsPercent)
                    bar("Memory", text: cache.memoryText, percent: cache.memoryPercent)
                }
            }

            if !cache.summary.isEmpty {
                Text(cache.summary)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }

            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(cache.facts) { fact in
                    GridRow {
                        Text(fact.key)
                            .font(theme.subFont)
                            .foregroundStyle(theme.textSecondary)
                            .gridColumnAlignment(.leading)
                        Text(fact.value)
                            .font(theme.subFont)
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                            .multilineTextAlignment(.leading)
                            .gridColumnAlignment(.leading)
                    }
                }
            }

            Text(cache.note)
                .font(.caption2)
                .foregroundStyle(theme.textTertiary)
        }
        .strataCard(theme, fillsHeight: fillsHeight)
    }

    @ViewBuilder
    private func bar(_ label: String, text: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 4)
                Text(text)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            ProgressBar(percent: percent)
        }
    }
}
