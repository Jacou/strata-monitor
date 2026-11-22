import SwiftUI
import Charts

// The oMLX Monitor's cards, one per block of oMLX's own Status page. They draw an
// `OmLXMonitorModel`; the screen that stacks them lives in the app.

/// A card title with an optional note on the right, the way every Monitor card opens.
struct OmLXCardHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.theme) private var theme

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

extension OmLXCardHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

/// Key / value rows in two aligned columns.
struct OmLXFactsGrid: View {
    let facts: [MonitorViewModel.Fact]

    @Environment(\.theme) private var theme

    init(facts: [MonitorViewModel.Fact]) {
        self.facts = facts
    }

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 6) {
            ForEach(facts) { fact in
                GridRow {
                    Text(fact.key)
                        .font(theme.subFont)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .gridColumnAlignment(.leading)
                    Text(fact.value)
                        .font(theme.subFont)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                        .gridColumnAlignment(.leading)
                }
            }
        }
    }
}

// MARK: - live

/// Decode and prefill speed right now, summed across running requests, with the decode trace.
public struct OmLXLiveCard: View {
    public let live: OmLXMonitorModel.Live
    /// Decode tok/s, one sample per poll.
    public let decodeHistory: [Double]

    @Environment(\.theme) private var theme

    public init(live: OmLXMonitorModel.Live, decodeHistory: [Double]) {
        self.live = live
        self.decodeHistory = decodeHistory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                speed("DECODE", live.decodeText, active: live.isDecoding)
                speed("PREFILL", live.prefillText, active: live.isPrefilling)
                Spacer(minLength: 0)
            }

            Text(live.detail)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)

            Sparkline(values: decodeHistory, tint: theme.accent, height: 44)
        }
        .strataCard(theme)
        .accessibilityElement(children: .combine)
    }

    private func speed(_ label: String, _ value: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(theme.tileLabelFont)
                .tracking(theme.tileLabelTracking)
                .foregroundStyle(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(theme.metricValueFont)
                    .foregroundStyle(active ? theme.accentText : theme.textPrimary)
                    .contentTransition(.numericText())
                Text("tok/s")
                    .font(theme.subFont)
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

// MARK: - memory

public struct OmLXMemoryCard: View {
    public let memory: OmLXMonitorModel.Memory

    @Environment(\.theme) private var theme

    public init(memory: OmLXMonitorModel.Memory) {
        self.memory = memory
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OmLXCardHeader("Memory", subtitle: memory.text) {
                Text(memory.level)
                    .font(theme.badgeFont)
                    .foregroundStyle(levelColor)
            }
            ProgressBar(percent: memory.percent, tone: memory.tone)
            if !memory.facts.isEmpty {
                OmLXFactsGrid(facts: memory.facts)
            }
        }
        .strataCard(theme)
    }

    private var levelColor: Color {
        switch memory.tone {
        case .danger: theme.dangerText
        case .warn: theme.warnText
        case .normal, .info: theme.textTertiary
        }
    }
}

// MARK: - active models

/// Each loaded model with what it is doing: the prompts being read, the answers being written,
/// and the queue, one row per request.
public struct OmLXModelsCard: View {
    public let rows: [OmLXMonitorModel.ModelRow]
    public let summary: String

    @Environment(\.theme) private var theme

    public init(rows: [OmLXMonitorModel.ModelRow], summary: String) {
        self.rows = rows
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OmLXCardHeader("Active models", subtitle: summary)

            if rows.isEmpty {
                Text("No model in memory. The first request loads one.")
                    .font(.subheadline)
                    .foregroundStyle(theme.textTertiary)
            }

            ForEach(rows) { row in
                model(row)
                if row.id != rows.last?.id {
                    Divider().overlay(theme.separator)
                }
            }
        }
        .strataCard(theme)
    }

    private func model(_ row: OmLXMonitorModel.ModelRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(row.isBusy || row.isLoading ? theme.accent : theme.track)
                    .frame(width: 7, height: 7)
                Text(row.id)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Text(row.sizeText)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            }

            HStack(spacing: 6) {
                Text(row.statusText)
                    .foregroundStyle(row.isBusy || row.isLoading ? theme.accentText : theme.textSecondary)
                ForEach(row.badges, id: \.self) { badge in
                    Text(badge)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().stroke(theme.cardBorder))
                        .foregroundStyle(theme.textSecondary)
                }
                if let context = row.contextText {
                    Text("· \(context)")
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .font(theme.subFont)
            .monospacedDigit()

            ForEach(row.requests) { request in
                requestRow(request)
            }
        }
    }

    private func requestRow(_ request: OmLXMonitorModel.RequestRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: icon(request.kind))
                    .font(.caption)
                    .foregroundStyle(request.isStalled ? theme.warnText : theme.accentText)
                    .frame(width: 14)
                Text(request.stateText)
                    .font(.callout)
                    .foregroundStyle(request.isStalled ? theme.warnText : theme.textPrimary)
                    .lineLimit(1)
                Text(request.shortID)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textTertiary)
                Spacer(minLength: 4)
                Text(request.speedText)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            if let percent = request.percent {
                ProgressBar(percent: percent, tone: request.isStalled ? .warn : .normal)
            }
            Text(request.detail)
                .font(theme.subFont)
                .monospacedDigit()
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.leading, 15)
        .accessibilityElement(children: .combine)
    }

    private func icon(_ kind: OmLXMonitorModel.RequestKind) -> String {
        switch kind {
        case .prefill: "text.page"
        case .generate: "bolt.fill"
        case .waiting: "hourglass"
        }
    }
}

// MARK: - serving stats

/// The Status page's Serving Stats: totals for this session or all time, for every model or one.
public struct OmLXServingCard: View {
    public let serving: OmLXMonitorModel.Serving
    public let modelFilter: String?
    public let filterChoices: [String]
    public let onFilter: (String?) -> Void
    public let columns: Int

    @Binding private var scope: OmLXStatsScope
    @Environment(\.theme) private var theme

    public init(
        serving: OmLXMonitorModel.Serving,
        scope: Binding<OmLXStatsScope>,
        modelFilter: String?,
        filterChoices: [String],
        columns: Int = 2,
        onFilter: @escaping (String?) -> Void
    ) {
        self.serving = serving
        _scope = scope
        self.modelFilter = modelFilter
        self.filterChoices = filterChoices
        self.columns = columns
        self.onFilter = onFilter
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OmLXCardHeader("Serving", subtitle: serving.footnote) {
                filterMenu
            }

            Picker("Scope", selection: $scope) {
                ForEach(OmLXStatsScope.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if serving.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .topLeading), count: max(1, columns)),
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(serving.tiles) { tile in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.label.uppercased())
                                .font(theme.tileLabelFont)
                                .tracking(theme.tileLabelTracking)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(tile.value)
                                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.textPrimary)
                                    .contentTransition(.numericText())
                                if let unit = tile.unit {
                                    Text(unit)
                                        .font(theme.subFont)
                                        .foregroundStyle(theme.textTertiary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Divider().overlay(theme.separator)

                OmLXFactsGrid(facts: [
                    MonitorViewModel.Fact(key: "Avg prompt processing", value: serving.prefillSpeed),
                    MonitorViewModel.Fact(key: "Avg token generation", value: serving.generationSpeed),
                ])
            }
        }
        .strataCard(theme)
    }

    private var filterMenu: some View {
        Menu {
            Button {
                onFilter(nil)
            } label: {
                if modelFilter == nil { Label("All models", systemImage: "checkmark") } else { Text("All models") }
            }
            if !filterChoices.isEmpty {
                Divider()
                ForEach(filterChoices, id: \.self) { model in
                    Button {
                        onFilter(model)
                    } label: {
                        if modelFilter == model { Label(model, systemImage: "checkmark") } else { Text(model) }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(modelFilter ?? "All models")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(theme.badgeFont)
            .foregroundStyle(theme.accentText)
            .frame(maxWidth: 160, alignment: .trailing)
        }
        .accessibilityLabel("Model filter")
    }
}

// MARK: - usage

/// oMLX's hourly history: tokens per hour today, or per day over a week or a month.
public struct OmLXUsageCard: View {
    public let usage: OmLXMonitorModel.Usage

    @Binding private var range: OmLXUsageRange
    @Environment(\.theme) private var theme

    public init(usage: OmLXMonitorModel.Usage, range: Binding<OmLXUsageRange>) {
        self.usage = usage
        _range = range
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OmLXCardHeader("Usage", subtitle: usage.unavailableText == nil ? usage.totalText : nil)

            Picker("Range", selection: $range) {
                ForEach(OmLXUsageRange.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if let unavailable = usage.unavailableText {
                Text(unavailable)
                    .font(.subheadline)
                    .foregroundStyle(theme.textTertiary)
            } else {
                chart
                if !usage.facts.isEmpty {
                    OmLXFactsGrid(facts: usage.facts)
                }
            }
        }
        .strataCard(theme)
    }

    private var chart: some View {
        let bars = usage.bars
        // Six or seven labels at most, so a month of days does not crowd the axis.
        let step = max(1, Int((Double(bars.count) / 6).rounded(.up)))
        let shown = bars.enumerated().filter { $0.offset % step == 0 }.map { $0.element.id }
        let labels = Dictionary(uniqueKeysWithValues: bars.map { ($0.id, $0.label) })

        return Chart(bars) { bar in
            BarMark(
                x: .value(usage.axisLabel, bar.id),
                y: .value("Tokens", bar.tokens)
            )
            .foregroundStyle(theme.barFill)
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: shown) { value in
                AxisValueLabel {
                    if let id = value.as(String.self) {
                        Text(labels[id] ?? "")
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(theme.separator)
                AxisValueLabel {
                    if let tokens = value.as(Double.self) {
                        Text(OmLXMonitorModel.bigCount(tokens, locale: .autoupdatingCurrent))
                            .font(.caption2)
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .frame(height: 120)
        .accessibilityLabel("Tokens per \(usage.axisLabel.lowercased()), \(usage.totalText) in total")
    }
}

// MARK: - cache

public struct OmLXCacheCard: View {
    public let cache: OmLXMonitorModel.Cache

    @Environment(\.theme) private var theme

    public init(cache: OmLXMonitorModel.Cache) {
        self.cache = cache
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            OmLXCardHeader("Cache")

            ForEach(cache.tiers, id: \.label) { tier in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tier.label)
                            .font(.callout)
                            .foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 4)
                        Text(tier.text)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(theme.textPrimary)
                    }
                    ProgressBar(percent: tier.percent)
                }
            }

            if !cache.facts.isEmpty {
                OmLXFactsGrid(facts: cache.facts)
            }

            if let note = cache.note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .strataCard(theme)
    }
}

// MARK: - engines

public struct OmLXEnginesCard: View {
    public let engines: [MonitorViewModel.Fact]

    @Environment(\.theme) private var theme

    public init(engines: [MonitorViewModel.Fact]) {
        self.engines = engines
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OmLXCardHeader("Engine")
            OmLXFactsGrid(facts: engines)
        }
        .strataCard(theme)
    }
}
