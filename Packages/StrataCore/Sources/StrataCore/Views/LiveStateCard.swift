import SwiftUI

/// "Reading prompt · 26,631 / 53,262 tokens · 50%" and its progress bar.
public struct LiveStateCard: View {
    public let card: MonitorViewModel.LiveCard

    @Environment(\.theme) private var theme

    public init(card: MonitorViewModel.LiveCard) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(card.tone.color(in: theme))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(card.label)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
            }

            // An empty detail means there is nothing to add to the label — the label already says it.
            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
            }

            ProgressBar(percent: card.percent, tone: card.tone)
        }
        .strataCard(theme)
        .accessibilityElement()
        .accessibilityLabel(card.detail.isEmpty ? card.label : "\(card.label). \(card.detail)")
    }
}
