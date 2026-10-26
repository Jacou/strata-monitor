import Foundation

/// What the macOS hover card shows: the state, and the two speeds that matter.
///
/// The numbers follow the same branch the web Monitor uses for its Speed tile — live while the
/// engine is working, the last request when it is not.
public struct HoverCard: Sendable, Equatable {
    /// One of the two big numbers.
    public struct Speed: Sendable, Equatable {
        /// "104.3", or the "no value" dash.
        public var text: String
        /// "now" when it came from `live`, "last request" when it came from the last request,
        /// "" when there was nothing to show.
        public var caption: String
    }

    public var status: MonitorStatus
    /// The pill text. While generating this names the phase ("Generating · Thinking") because the
    /// speed sits right under it and would otherwise be printed twice.
    public var pillText: String
    public var decode: Speed
    public var prefill: Speed
    /// "model · updated 3s ago".
    public var footer: String

    public init(
        metrics: Metrics?,
        status: MonitorStatus,
        model: String?,
        lastUpdated: Date?,
        paused: Bool = false,
        slots: [Slot] = [],
        now: Date = .now,
        locale: Locale = .autoupdatingCurrent
    ) {
        let live = metrics?.live
        let last = metrics?.requests?.first
        let state = live?.state
        let generating = state == .generating

        // Basalt running two requests at once: the big number is their sum, so name both.
        let streams = slots.filter { $0.state == .decoding && $0.isProcessing == true }

        var pill = status.text
        if case .generating = status {
            if streams.count > 1 {
                pill = "Generating · \(streams.count) streams"
            } else if live?.phase?.isEmpty == false {
                pill = "Generating · \(Self.capitalized(live?.phase))"
            } else {
                pill = "Generating"   // Basalt names no phase; "Generating · Generating" says nothing
            }
        }
        // The backoff gave up: say so, and how to get it going again.
        if paused { pill = "Paused · click to retry" }

        // Decode: the engine's live rate while it is generating, otherwise the last request's.
        let decodeValue = generating ? live?.tokS : last?.decodeTokS
        let decode = Speed(
            text: fmt(decodeValue, 1, locale: locale),
            caption: generating
                ? (streams.count > 1 ? streams.map { fmt($0.tokS, 0, locale: locale) }.joined(separator: " + ") : "now")
                : (last != nil ? "last request" : "")
        )

        // Prefill: the web page's own branch — the engine's mean whenever the state is not idle,
        // otherwise the last request's unread prompt tokens over its prompt milliseconds.
        let prefillValue: Double?
        if state != .idle {
            prefillValue = live?.prefillTokSMean
        } else if let last, let promptMs = last.promptMs, promptMs > 0 {
            prefillValue = max(0, (last.promptTokens ?? 0) - (last.reused ?? 0)) / (promptMs / 1000)
        } else {
            prefillValue = nil
        }
        let prefill = Speed(
            text: fmt(prefillValue, 0, locale: locale),
            caption: prefillValue == nil ? "" : (state == .idle ? "last request" : "now")
        )

        let updated = updatedCaption(status: status, lastUpdated: lastUpdated, now: now)
        let name = model.flatMap { $0.isEmpty ? nil : $0 }

        self.status = status
        self.pillText = pill
        self.decode = decode
        self.prefill = prefill
        self.footer = [name, updated].compactMap { $0 }.joined(separator: " · ")
    }

    /// "thinking" → "Thinking", the web page's `phase[0].toUpperCase() + phase.slice(1)`.
    static func capitalized(_ phase: String?) -> String {
        guard let phase, !phase.isEmpty else { return "Generating" }
        return phase.prefix(1).uppercased() + phase.dropFirst()
    }
}
