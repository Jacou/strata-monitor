import SwiftUI
import StrataCore

/// The Monitor's body on an oMLX server, laid out like oMLX's own Status page: what is running now,
/// the loaded models and their requests, memory, serving totals, usage history, the cache tiers,
/// the finished requests and the engine versions. One column on iPhone, two on a wide iPad.
struct OmLXMonitorSections: View {
    /// The Strata-shaped derivation, for the request rows and their detail sheet.
    let requestsModel: MonitorViewModel
    let layout: MonitorLayout
    let trends: Trends
    @Binding var trendsSeries: Trends.Series
    let highlightedRequestID: String?
    @Binding var presentedDetail: MonitorViewModel.RequestDetail?
    @Binding var showsLogs: Bool
    let onSelectTrend: (String) -> Void

    @Environment(MetricsPoller.self) private var poller

    init(
        requestsModel: MonitorViewModel,
        layout: MonitorLayout,
        trends: Trends,
        trendsSeries: Binding<Trends.Series>,
        highlightedRequestID: String?,
        presentedDetail: Binding<MonitorViewModel.RequestDetail?>,
        showsLogs: Binding<Bool>,
        onSelectTrend: @escaping (String) -> Void
    ) {
        self.requestsModel = requestsModel
        self.layout = layout
        self.trends = trends
        _trendsSeries = trendsSeries
        self.highlightedRequestID = highlightedRequestID
        _presentedDetail = presentedDetail
        _showsLogs = showsLogs
        self.onSelectTrend = onSelectTrend
    }

    var body: some View {
        let model = OmLXMonitorModel(
            activity: poller.omlxActivity,
            stats: poller.omlxStats,
            scopedStats: poller.omlxScopedStats,
            scope: poller.omlxScope,
            modelFilter: poller.omlxModelFilter,
            usage: poller.omlxUsage,
            usageRange: poller.omlxUsageRange,
            modelList: poller.omlxModelList,
            slots: poller.omlxSlots
        )

        if layout.isWide {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    live(model)
                    models(model)
                    memory(model)
                    cache(model)
                }
                VStack(alignment: .leading, spacing: 14) {
                    serving(model)
                    usage(model)
                    engines(model)
                }
            }
            history
        } else {
            live(model)
            models(model)
            memory(model)
            serving(model)
            usage(model)
            cache(model)
            history
            engines(model)
        }

        Button { showsLogs = true } label: { LogsLinkCard() }
            .buttonStyle(.plain)
            .id("logs")
    }

    // MARK: - cards

    private func live(_ model: OmLXMonitorModel) -> some View {
        OmLXLiveCard(live: model.live, decodeHistory: poller.metrics?.history?.tokS ?? [])
    }

    private func models(_ model: OmLXMonitorModel) -> some View {
        OmLXModelsCard(rows: model.models, summary: model.modelsSummary)
            .id("models")
    }

    @ViewBuilder
    private func memory(_ model: OmLXMonitorModel) -> some View {
        if let memory = model.memory {
            OmLXMemoryCard(memory: memory)
                .id("resources")
        }
    }

    @ViewBuilder
    private func serving(_ model: OmLXMonitorModel) -> some View {
        if let serving = model.serving {
            OmLXServingCard(
                serving: serving,
                scope: Binding(get: { poller.omlxScope }, set: { poller.setOmLXScope($0) }),
                modelFilter: poller.omlxModelFilter,
                filterChoices: model.filterChoices,
                columns: layout.isRegularWidth ? 3 : 2
            ) { model in
                poller.setOmLXModelFilter(model)
            }
            .id("session")
        }
    }

    @ViewBuilder
    private func usage(_ model: OmLXMonitorModel) -> some View {
        if let usage = model.usage {
            OmLXUsageCard(
                usage: usage,
                range: Binding(get: { poller.omlxUsageRange }, set: { poller.setOmLXUsageRange($0) })
            )
            .id("usage")
        }
    }

    @ViewBuilder
    private func cache(_ model: OmLXMonitorModel) -> some View {
        if let cache = model.cache, !(cache.tiers.isEmpty && cache.facts.isEmpty) {
            OmLXCacheCard(cache: cache)
                .id("cache")
        }
    }

    @ViewBuilder
    private func engines(_ model: OmLXMonitorModel) -> some View {
        if !model.engines.isEmpty {
            OmLXEnginesCard(engines: model.engines)
        }
    }

    /// Finished requests, read from the server's log: the trend across them, then the list.
    @ViewBuilder
    private var history: some View {
        if !trends.isHidden {
            TrendsCard(
                trends: trends,
                series: $trendsSeries,
                selectedID: highlightedRequestID,
                onSelect: onSelectTrend
            )
            .id("trends")
        }

        RequestsCard(
            rows: requestsModel.requests,
            emptyText: requestsModel.noRequestsText,
            showAllLabel: requestsModel.showAllLabel,
            showingAll: poller.allRequests,
            showFewerLabel: requestsModel.showFewerLabel,
            isTable: layout.isWide,
            highlightedID: highlightedRequestID,
            presented: $presentedDetail
        ) {
            poller.setAllRequests(!poller.allRequests)
        }
    }
}
