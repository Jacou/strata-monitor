import AppKit
import StrataCore
import SwiftUI

/// The window under the menu bar item: the pill, the live state, the eight tiles in two columns,
/// the context ring with the resource bars, the last five requests, and a footer.
struct MenuBarPopover: View {
    static let contentWidth: CGFloat = 360
    static let contentHeight: CGFloat = 520
    /// The spec's compact tile: a smaller value and a 28-point sparkline.
    static let sparklineHeight: CGFloat = 28
    static let requestCount = 5

    let model: MenuBarModel

    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let monitor = model.monitor ?? MonitorViewModel(metrics: Metrics())

        VStack(spacing: 10) {
            header

            if model.isConfigured {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 10) {
                        LiveStateCard(card: monitor.live)
                        tiles(monitor)
                        ResourcesCard(
                            context: monitor.context,
                            experts: monitor.experts,
                            ram: monitor.ram,
                            temp: monitor.temp
                        )
                        requests(monitor)
                    }
                    .padding(.bottom, 2)
                }
            } else {
                emptyState
            }

            footer
        }
        .padding(12)
        .frame(width: Self.contentWidth, height: Self.contentHeight)
        .background(theme.background)
    }

    // MARK: - pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            StatusPill(model.status)
            Spacer(minLength: 0)
            Text(updatedCaption(status: model.status, lastUpdated: model.lastUpdated))
                .font(theme.subFont)
                .foregroundStyle(theme.textTertiary)
        }
    }

    /// Eight tiles, four rows of two.
    private func tiles(_ monitor: MonitorViewModel) -> some View {
        let rows = tileRows(monitor)
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(row) { metric in
                        MetricTileView(
                            metric: metric,
                            sparklineHeight: Self.sparklineHeight,
                            compact: true,
                            variant: .menuBar
                        )
                    }
                    if row.count == 1 {
                        Color.clear.gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
        }
    }

    private func tileRows(_ monitor: MonitorViewModel) -> [[MonitorViewModel.Metric]] {
        stride(from: 0, to: monitor.metrics.count, by: 2).map { start in
            Array(monitor.metrics[start..<min(start + 2, monitor.metrics.count)])
        }
    }

    private func requests(_ monitor: MonitorViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent requests")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if monitor.requests.count > Self.requestCount {
                    Text("last \(Self.requestCount) of \(monitor.requests.count)")
                        .font(theme.subFont)
                        .foregroundStyle(theme.textTertiary)
                }
            }

            if monitor.requests.isEmpty {
                Text(monitor.noRequestsText ?? "No requests yet")
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(monitor.requests.prefix(Self.requestCount)) { row in
                HStack(spacing: 8) {
                    Text(row.timeText)
                        .font(theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                    FinishBadge(text: row.finishText, style: row.badge)
                    Spacer(minLength: 6)
                    Text("\(row.outputText) out · \(row.tokSText) t/s · \(row.durationText)")
                        .font(theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .strataCard(theme)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No server yet")
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            Text("Open Settings and set the Strata server address and its API key.")
                .font(theme.subFont)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .strataCard(theme)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.modelName ?? "Strata")
                .font(theme.subFont)
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                Button("Open Strata web page") {
                    if let url = model.baseURL { NSWorkspace.shared.open(url) }
                }
                Button("Settings…") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer(minLength: 0)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(theme.subFont)
            .foregroundStyle(theme.accentText)
        }
        .padding(.top, 2)
    }
}
