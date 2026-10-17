import Foundation

/// The trends card: one series across the requests the server kept, oldest on the left.
public struct Trends: Sendable, Equatable {
    /// What the segmented control offers.
    public enum Series: String, CaseIterable, Sendable, Equatable {
        case decode
        case hitRate
        case prefill

        /// The segmented control's label.
        public var label: String {
            switch self {
            case .decode: "Decode tok/s"
            case .hitRate: "Expert hit rate %"
            case .prefill: "Prefill tok/s"
            }
        }

        public var shortLabel: String {
            switch self {
            case .decode: "Decode"
            case .hitRate: "Hit rate"
            case .prefill: "Prefill"
            }
        }

        public var unit: String {
            switch self {
            case .decode, .prefill: "t/s"
            case .hitRate: "%"
            }
        }

        /// Swift Charts draws points as well as the line only where the values are sparse counts.
        public var showsPoints: Bool { self != .hitRate }

        /// A percentage has a fixed ceiling; speeds scale to the data.
        public var fixedCeiling: Double? { self == .hitRate ? 100 : nil }

        public var footnote: String {
            switch self {
            case .decode: "Tokens per second while each answer was written."
            case .hitRate: "How much of the prompt the experts already had."
            case .prefill: "Unread prompt tokens over the time it took to read them."
            }
        }
    }

    public struct Point: Identifiable, Sendable, Equatable {
        /// The request's own id, so a tap can highlight its row in the list.
        public var id: String
        public var date: Date
        public var time: Double
        public var value: Double
        public var valueText: String
        public var timeText: String
    }

    /// Fewer than this is a couple of dots, not a trend.
    public static let minimumPoints = 3
    /// More than this is unreadable in a phone-width card.
    public static let maximumPoints = 40

    public var series: Series
    public var points: [Point]
    /// "40 requests · 11:02 – 11:51"
    public var rangeText: String
    public var footnote: String

    public var isHidden: Bool { points.count < Self.minimumPoints }
    public var isEmpty: Bool { points.isEmpty }

    public init(requests: [Request], series: Series, locale: Locale = .autoupdatingCurrent) {
        // The payload is newest first; a chart reads left to right in time order.
        let ordered = requests
            .filter { ($0.time ?? 0) > 0 }
            .sorted { ($0.time ?? 0) < ($1.time ?? 0) }

        let digits = series == .hitRate ? 1 : 1
        let points: [Point] = ordered.suffix(Self.maximumPoints).compactMap { request in
            guard let time = request.time, let value = Self.value(for: request, series: series) else { return nil }
            return Point(
                id: request.id,
                date: Date(timeIntervalSince1970: time),
                time: time,
                value: value,
                valueText: fmt(value, digits, locale: locale) + (series.unit == "%" ? "%" : ""),
                timeText: timeString(time, locale: locale)
            )
        }

        self.series = series
        self.points = points
        self.footnote = series.footnote
        if points.isEmpty {
            self.rangeText = "no requests yet"
        } else {
            let first = points.first!.timeText
            let last = points.last!.timeText
            self.rangeText = first == last
                ? "\(points.count) requests · \(first)"
                : "\(points.count) requests · \(first) – \(last)"
        }
    }

    /// The series' value for one request, or nil when the server did not report it.
    public static func value(for request: Request, series: Series) -> Double? {
        switch series {
        case .decode:
            return usable(request.decodeTokS)
        case .hitRate:
            guard let hit = request.hitRate else { return nil }
            // The payload is a fraction; the card shows a percentage.
            return usable(hit <= 1 ? hit * 100 : hit)
        case .prefill:
            guard let promptMs = request.promptMs, promptMs > 0 else { return nil }
            let unread = max(0, (request.promptTokens ?? 0) - (request.reused ?? 0))
            return usable(unread / (promptMs / 1000))
        }
    }

    /// The point nearest a time, for tapping the chart.
    public func nearest(to date: Date) -> Point? {
        let target = date.timeIntervalSince1970
        return points.min { abs($0.time - target) < abs($1.time - target) }
    }

    /// The highest value, so the y axis can be set once for the whole series.
    public var ceiling: Double {
        if let fixed = series.fixedCeiling { return fixed }
        return max(1, (points.map(\.value).max() ?? 1) * 1.15)
    }

    /// A whole-minute stride that puts roughly four time labels on the x axis for this span.
    /// Charts' own choice collapses to a single label when the span is a few minutes.
    public var axisStrideMinutes: Int {
        guard let first = points.first, let last = points.last else { return 1 }
        let span = max(0, last.time - first.time) / 60
        for stride in [1, 2, 5, 10, 15, 30, 60, 120, 360, 720] where span / Double(stride) <= 5 { return stride }
        return 1_440
    }

    private static func usable(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return max(0, value)
    }
}
