import SwiftUI
import StrataCore

/// The Monitor tab: pill, live card, eight metric tiles, resources, conversation cache, requests.
public struct MonitorView: View {
    @Environment(MetricsPoller.self) private var poller
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.theme) private var theme

    @State private var presentedDetail: MonitorViewModel.RequestDetail?
    @State private var trendsSeries: Trends.Series = .decode
    /// The request picked on the chart, highlighted in the list below it.
    @State private var highlightedRequestID: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    let model = MonitorViewModel(
                        metrics: poller.metrics ?? Metrics(),
                        now: .now,
                        allRequests: poller.allRequests,
                        modelLoaded: poller.health?.loaded
                    )
                    // Measured on the viewport, not on the capped content, so the column
                    // count cannot feed back on itself.
                    let layout = MonitorLayout(
                        horizontalSizeClass: horizontalSizeClass,
                        width: viewport.size.width,
                        isAccessibilityText: dynamicTypeSize.isAccessibilitySize
                    )
                    let trends = Trends(requests: poller.trendRequests, series: trendsSeries)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ScreenTitle("Monitor")

                            header

                            LiveStateCard(card: model.live)

                            // Tiles stretch to their row's height (see MetricTileView), so neighbours align.
                            LazyVGrid(columns: layout.gridColumns, spacing: MonitorLayout.gridSpacing) {
                                ForEach(model.metrics) { metric in
                                    MetricTileView(metric: metric, sparklineHeight: layout.sparklineHeight,
                                                   compact: !layout.isRegularWidth)
                                }
                            }

                            if layout.isWide, let cache = model.convCache {
                                // A wide screen has room for both cards; they share the row's height.
                                HStack(alignment: .top, spacing: 14) {
                                    ResourcesCard(
                                        context: model.context,
                                        experts: model.experts,
                                        ram: model.ram,
                                        temp: model.temp,
                                        fillsHeight: true
                                    )

                                    ConversationCacheCard(cache: cache, fillsHeight: true)
                                }
                                .id("resources")
                            } else {
                                ResourcesCard(
                                    context: model.context,
                                    experts: model.experts,
                                    ram: model.ram,
                                    temp: model.temp
                                )
                                .id("resources")

                                if let cache = model.convCache {
                                    ConversationCacheCard(cache: cache)
                                        .id("cache")
                                }
                            }

                            // Trends need at least three requests to be worth a card.
                            if !trends.isHidden {
                                TrendsCard(
                                    trends: trends,
                                    series: $trendsSeries,
                                    selectedID: highlightedRequestID
                                ) { id in
                                    select(request: id, in: model, proxy: proxy)
                                }
                                .id("trends")
                            }

                            RequestsCard(
                                rows: model.requests,
                                emptyText: model.noRequestsText,
                                showAllLabel: model.showAllLabel,
                                showingAll: poller.allRequests,
                                isTable: layout.isWide,
                                highlightedID: highlightedRequestID,
                                presented: $presentedDetail
                            ) {
                                poller.setAllRequests(!poller.allRequests)
                            }

                            if let session = model.session {
                                SessionCard(session: session)
                                    .id("session")
                            }
                        }
                        .padding()
                        .padding(.bottom, 16)   // the last card must clear the tab bar
                        .frame(maxWidth: MonitorLayout.contentMaxWidth)
                        .id("bottom")
                    }
                    .frame(width: viewport.size.width, height: viewport.size.height)
                    .background(ThemeBackground())
                    // The trends series comes from `metrics?requests=all`: once on appear, then
                    // every 30 s. The 1 s poll keeps carrying the rest of the screen.
                    .task {
                        await poller.refreshTrends()
                        while !Task.isCancelled {
                            try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                            guard !Task.isCancelled else { break }
                            await poller.refreshTrends()
                        }
                    }
                    #if DEBUG
                    .onAppear {
                        DebugLaunch.scroll(proxy, to: "resources", anchor: .center)
                        DebugLaunch.scroll(proxy, to: "cache", anchor: .center)
                        DebugLaunch.scroll(proxy, to: "trends", anchor: .center)
                        DebugLaunch.scroll(proxy, to: "session", anchor: .center)
                        DebugLaunch.scroll(proxy, to: "bottom", anchor: .bottom)
                        if DebugLaunch.opensRequestSheet {
                            // simctl cannot tap a row, so `--open-request` opens the newest one
                            // once the first poll has brought a request in.
                            DebugLaunch.retryUntilOpened {
                                if presentedDetail != nil { return true }
                                let current = MonitorViewModel(
                                    metrics: poller.metrics ?? Metrics(),
                                    now: .now,
                                    allRequests: poller.allRequests,
                                    modelLoaded: poller.health?.loaded
                                )
                                presentedDetail = current.requests.first?.detail
                                return presentedDetail != nil
                            }
                        }
                        if DebugLaunch.selectsTrendPoint {
                            // …and `--select-trend` takes the chart's own tap path once it has points:
                            // highlight the newest request's row and scroll to it.
                            DebugLaunch.retryUntilOpened {
                                guard let newest = poller.trendRequests.max(by: { ($0.time ?? 0) < ($1.time ?? 0) })
                                else { return false }
                                let current = MonitorViewModel(
                                    metrics: poller.metrics ?? Metrics(),
                                    now: .now,
                                    allRequests: poller.allRequests,
                                    modelLoaded: poller.health?.loaded
                                )
                                select(request: newest.id, in: current, proxy: proxy)
                                return true
                            }
                        }
                    }
                    #endif
                }
            }
            .navigationTitle("Monitor")
            // The title is drawn by ScreenTitle, so the theme controls its type.
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await poller.pollOnce() }
        }
    }

    private var header: some View {
        HStack {
            StatusPill(poller.status)
            Spacer(minLength: 8)
            Text(updatedText)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(theme.textTertiary)
        }
    }

    private var updatedText: String {
        updatedCaption(status: poller.status, lastUpdated: poller.lastUpdated)
    }

    /// A tap on the chart highlights that request; if the list is showing only the last twelve,
    /// switch it to "all" so the row is actually on screen.
    private func select(request id: String, in model: MonitorViewModel, proxy: ScrollViewProxy) {
        highlightedRequestID = id
        if model.requests.first(where: { $0.id == id }) == nil, !poller.allRequests {
            poller.setAllRequests(true)
        }
        proxy.scrollTo(id)
    }
}
