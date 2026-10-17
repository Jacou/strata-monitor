import SwiftUI
import StrataCore

/// One request opened up: tap a row in the recent-requests card. Facts grid, same style as the
/// conversation-cache card.
public struct RequestDetailSheet: View {
    public let detail: MonitorViewModel.RequestDetail

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(detail: MonitorViewModel.RequestDetail) {
        self.detail = detail
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        FinishBadge(text: detail.badgeText, style: detail.badge)
                        Text(detail.headline)
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                        Spacer(minLength: 0)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                            ForEach(detail.facts) { fact in
                                GridRow {
                                    Text(fact.key)
                                        .font(theme.subFont)
                                        .foregroundStyle(theme.textSecondary)
                                    Text(fact.value)
                                        .font(.callout)
                                        .monospacedDigit()
                                        .foregroundStyle(theme.textPrimary)
                                        .multilineTextAlignment(.leading)
                                        .gridColumnAlignment(.leading)
                                }
                            }
                        }

                        if let acceptance = detail.acceptance {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Drafts accepted")
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
                        }
                    }
                    .strataCard(theme)
                }
                .padding()
                .frame(maxWidth: MonitorLayout.formMaxWidth, alignment: .leading)
            }
            .background(ThemeBackground())
            .navigationTitle(detail.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // "Close", not "Done": "Done" already means the request finished cleanly.
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
