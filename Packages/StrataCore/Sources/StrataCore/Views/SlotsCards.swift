import SwiftUI

/// Basalt's parallel slots: one row per slot with its state, speed and how full its context is.
public struct SlotsCardView: View {
    public let card: MonitorViewModel.SlotsCard
    /// The menu bar popover's tighter version: no drafts line.
    public let compact: Bool

    @Environment(\.theme) private var theme

    public init(card: MonitorViewModel.SlotsCard, compact: Bool = false) {
        self.card = card
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Slots")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(card.summary)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                Spacer(minLength: 4)
                Text(card.note)
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(card.rows) { row in
                slot(row)
            }
        }
        .strataCard(theme)
    }

    private func slot(_ row: MonitorViewModel.SlotRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(row.isBusy ? theme.accent : theme.track)
                    .frame(width: 7, height: 7)
                Text(row.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                Text(row.stateText)
                    .font(theme.subFont)
                    .foregroundStyle(row.isBusy ? theme.accentText : theme.textTertiary)
                Spacer(minLength: 4)
                Text(row.speedText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(row.isBusy ? theme.textPrimary : theme.textTertiary)
            }

            ProgressBar(percent: row.contextPercent, tone: row.contextTone)

            HStack(spacing: 6) {
                Text("context \(row.contextText)")
                if !row.detail.isEmpty { Text("· \(row.detail)") }
                if !compact, let drafts = row.draftsText { Text("· \(drafts)") }
            }
            .font(theme.subFont)
            .monospacedDigit()
            .foregroundStyle(theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Requests waiting for a free slot. Only on screen while something waits.
public struct QueueCardView: View {
    public let card: MonitorViewModel.QueueCard

    @Environment(\.theme) private var theme

    public init(card: MonitorViewModel.QueueCard) {
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Queue")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text(card.summary)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.warnText)
                Spacer(minLength: 4)
                Text("Waiting for a free slot")
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(card.rows) { row in
                HStack(spacing: 8) {
                    Text(row.waitedText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .frame(minWidth: 52, alignment: .leading)
                    Text(row.source)
                        .font(theme.subFont)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(row.promptText)
                        .font(theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }

            if let more = card.more {
                Text(more)
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .strataCard(theme)
    }
}

/// Where the last request's routed expert lookups came from: VRAM, the peer GPU, or the CPU.
public struct ExpertSourcesCardView: View {
    public let sources: MonitorViewModel.ExpertSources

    @Environment(\.theme) private var theme

    public init(sources: MonitorViewModel.ExpertSources) {
        self.sources = sources
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Experts")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 4)
                Text(sources.note)
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(sources.parts) { part in
                        if part.fraction > 0 {
                            RoundedRectangle(cornerRadius: theme.barRadius)
                                .fill(color(part.tone))
                                .frame(width: max(2, (geometry.size.width - 4) * part.fraction))
                        }
                    }
                }
            }
            .frame(height: theme.barHeight * 1.6)
            .accessibilityHidden(true)

            HStack(spacing: 14) {
                ForEach(sources.parts) { part in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(color(part.tone))
                            .frame(width: 7, height: 7)
                        Text(part.label)
                            .foregroundStyle(theme.textSecondary)
                        Text(part.text)
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(theme.subFont)
        }
        .strataCard(theme)
    }

    private func color(_ tone: MonitorViewModel.Tone) -> Color {
        switch tone {
        case .normal: theme.accent
        case .info: theme.textTertiary
        case .warn: theme.warnText
        case .danger: theme.dangerText
        }
    }
}
