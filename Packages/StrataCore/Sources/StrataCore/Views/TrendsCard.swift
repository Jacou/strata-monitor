import Charts
import SwiftUI

/// Request trends: one series across the requests the server kept, oldest on the left.
///
/// Tapping the chart selects the nearest request so the screen can highlight its row in the list.
public struct TrendsCard: View {
    public let trends: Trends
    public let series: Binding<Trends.Series>
    public let selectedID: String?
    public let onSelect: (String) -> Void

    @Environment(\.theme) private var theme

    public init(
        trends: Trends,
        series: Binding<Trends.Series>,
        selectedID: String?,
        onSelect: @escaping (String) -> Void
    ) {
        self.trends = trends
        self.series = series
        self.selectedID = selectedID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Request trends")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Text(trends.rangeText)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }

            Picker("Series", selection: series) {
                ForEach(Trends.Series.allCases, id: \.self) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Trend series")

            if trends.isEmpty {
                Text("The server has not kept enough requests to chart yet.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                chart
                    .frame(height: 150)

                Text(trends.footnote)
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)

                // The tapped point, spelled out: the row highlighted in the list below.
                if let selectedID, let point = trends.points.first(where: { $0.id == selectedID }) {
                    HStack(spacing: 4) {
                        Image(systemName: "scope")
                            .font(.caption2)
                        Text("\(point.timeText) · \(point.valueText)")
                            .monospacedDigit()
                    }
                    .font(theme.subFont)
                    .foregroundStyle(theme.warnText)
                }
            }
        }
        .strataCard(theme)
    }

    private var chart: some View {
        let active = series.wrappedValue

        return Chart {
            ForEach(trends.points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value(active.label, point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .foregroundStyle(theme.accent)

                if active.showsPoints {
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value(active.label, point.value)
                    )
                    .foregroundStyle(point.id == selectedID ? theme.warnText : theme.accent)
                    .symbolSize(point.id == selectedID ? 130 : 36)
                }
            }

            if let selectedID, let point = trends.points.first(where: { $0.id == selectedID }) {
                RuleMark(x: .value("Selected", point.date))
                    .foregroundStyle(theme.separator)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: 0...trends.ceiling)
        .chartXAxis {
            AxisMarks(values: .stride(by: .minute, count: trends.axisStrideMinutes)) {
                AxisGridLine().foregroundStyle(theme.separator)
                AxisValueLabel(format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(theme.separator)
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                select(at: value.location, proxy: proxy, geometry: geometry)
                            }
                    )
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary(active))
    }

    private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let origin = geometry[anchor].origin
        let x = location.x - origin.x
        guard x >= 0, let date: Date = proxy.value(atX: x) else { return }
        if let point = trends.nearest(to: date) { onSelect(point.id) }
    }

    private func accessibilitySummary(_ active: Trends.Series) -> String {
        guard let first = trends.points.first, let last = trends.points.last else {
            return "No requests to chart"
        }
        let values = trends.points.map(\.valueText).joined(separator: ", ")
        return "\(active.label), \(trends.points.count) requests, \(first.timeText) to \(last.timeText): \(values)"
    }
}
