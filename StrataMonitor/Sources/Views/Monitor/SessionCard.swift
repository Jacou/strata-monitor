import SwiftUI
import StrataCore

/// The engine's whole run: uptime, throughput, and how much of the speculative work paid off.
/// Replaces the one-line totals the web page prints under the request table.
public struct SessionCard: View {
    public let session: MonitorViewModel.Session

    @Environment(\.theme) private var theme

    public init(session: MonitorViewModel.Session) {
        self.session = session
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text(session.uptimeText)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }

            Text(session.headline)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(theme.textPrimary)

            Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(session.facts) { fact in
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

            if let acceptance = session.acceptance {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Speculative acceptance")
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 4)
                        Text(acceptance.text)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(acceptance.tone == .warn ? theme.warnText : theme.textPrimary)
                    }
                    ProgressBar(percent: acceptance.percent, tone: acceptance.tone)
                }
                .accessibilityElement()
                .accessibilityLabel("Speculative acceptance \(acceptance.text)")

                Text(session.acceptanceNote)
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .strataCard(theme)
    }
}
