import StrataCore
import SwiftUI

/// The card that appears when the pointer rests on the menu bar icon: the state, the two speeds,
/// and one line saying which model and how fresh the numbers are. Read-only — no buttons.
struct HoverCardView: View {
    static let cardWidth: CGFloat = 260

    let model: MenuBarModel

    @Environment(\.theme) private var theme

    var body: some View {
        let card = model.hoverCard

        VStack(alignment: .leading, spacing: 10) {
            StatusPill(card.status, text: card.pillText)

            HStack(alignment: .top, spacing: 16) {
                speed("Decode", card.decode, color: theme.accentText)
                speed("Prefill", card.prefill, color: theme.textPrimary)
            }

            Text(card.footer)
                .font(theme.subFont)
                .foregroundStyle(theme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .frame(width: Self.cardWidth)
        .background(theme.background)
        .accessibilityElement(children: .combine)
    }

    private func speed(_ label: String, _ speed: HoverCard.Speed, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(theme.tileLabelFont)
                .tracking(theme.tileLabelTracking)
                .foregroundStyle(theme.textSecondary)

            Text(speed.text)
                .font(theme.valueFont(paired: true, compact: true, variant: .menuBar))
                .monospacedDigit()
                .foregroundStyle(color)
                .shadow(color: theme.glowColor, radius: theme.glowRadius)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(speed.caption.isEmpty ? " " : speed.caption)
                .font(theme.subFont)
                .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
