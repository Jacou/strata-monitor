import Foundation

/// The cards a Basalt server adds to the Monitor, mirroring its own web page: the parallel slots,
/// the queue waiting for one, and where the last request's experts were read from.
extension MonitorViewModel {
    // MARK: - slots

    public struct SlotsCard: Sendable, Equatable {
        /// "1 of 2 busy"
        public var summary: String
        /// "262k context each"
        public var note: String
        public var rows: [SlotRow]
    }

    public struct SlotRow: Identifiable, Sendable, Equatable {
        public var id: Int
        /// "Slot 0"
        public var title: String
        /// "Decoding" / "Prefill" / "Idle"
        public var stateText: String
        public var isBusy: Bool
        /// "39.5 tok/s" while decoding, "–" otherwise
        public var speedText: String
        /// "5,023 tokens" while busy, "" otherwise
        public var detail: String
        /// "87k / 262k"
        public var contextText: String
        /// 0...100
        public var contextPercent: Double
        public var contextTone: Tone
        /// "73% drafts accepted", nil when the slot drafted nothing
        public var draftsText: String?
    }

    static func slotsCard(live: Live?, slots: [Slot], locale: Locale) -> SlotsCard? {
        guard live?.isMultiSlot == true, !slots.isEmpty else { return nil }
        let busy = live?.slots?.active ?? slots.filter { $0.isProcessing == true }.count
        let rows = slots.sorted { $0.id < $1.id }.map { slot -> SlotRow in
            let processing = slot.isProcessing == true
            let percent = (slot.nCtx ?? 0) > 0 ? min(100, 100 * (slot.ctxUsed ?? 0) / (slot.nCtx ?? 1)) : 0
            var detail = ""
            if processing {
                switch slot.state {
                case .prefill:
                    detail = "read \(fmt(slot.prefillDone, 0, locale: locale)) of \(fmt(slot.promptTokens, 0, locale: locale)) tokens"
                default:
                    detail = "\(fmt(slot.generated, 0, locale: locale)) tokens"
                }
            }
            var drafts: String?
            if let offered = slot.draftsOffered, offered > 0, processing, slot.state == .decoding {
                drafts = "\(fmt(100 * (slot.draftsAccepted ?? 0) / offered, 0, locale: locale))% drafts accepted"
            }
            return SlotRow(
                id: slot.id,
                title: "Slot \(slot.id)",
                stateText: processing ? slot.state.label : "Idle",
                isBusy: processing,
                speedText: slot.state == .decoding && processing ? "\(fmt(slot.tokS, 1, locale: locale)) tok/s" : notAvailable,
                detail: detail,
                contextText: "\(kfmt(slot.ctxUsed ?? 0, locale: locale)) / \(kfmt(slot.nCtx, locale: locale))",
                contextPercent: percent,
                contextTone: percent > 90 ? .danger : (percent > 75 ? .warn : .normal),
                draftsText: drafts
            )
        }
        return SlotsCard(
            summary: "\(busy) of \(slots.count) busy",
            note: slots.first?.nCtx.map { "\(kfmt($0, locale: locale)) context each" } ?? "",
            rows: rows
        )
    }

    // MARK: - queue

    public struct QueueCard: Sendable, Equatable {
        /// "2 waiting"
        public var summary: String
        public var rows: [QueueRow]
        /// "+ 3 more", nil when every waiting request is listed
        public var more: String?
    }

    public struct QueueRow: Identifiable, Sendable, Equatable {
        public var id: Int
        /// "12.3 s"
        public var waitedText: String
        /// "OpenAI · qwen3.8-flash-next"
        public var source: String
        /// "82,433 tokens"
        public var promptText: String
    }

    /// The first few, like the web page — a queue long enough to need scrolling is its own problem.
    static let shownQueueRows = 3

    static func queueCard(live: Live?, locale: Locale) -> QueueCard? {
        let waiting = live?.queuedCount ?? 0
        let queue = live?.queue ?? []
        guard waiting > 0 || !queue.isEmpty else { return nil }
        let count = max(waiting, queue.count)
        let rows = queue.prefix(shownQueueRows).enumerated().map { index, request in
            QueueRow(
                id: index,
                waitedText: "\(fmt(request.waitedS ?? 0, 1, locale: locale)) s",
                source: [apiName(request.api), request.model].compactMap { $0 }.joined(separator: " · "),
                promptText: request.promptTokens.map { "\(fmt($0, 0, locale: locale)) tokens" } ?? notAvailable
            )
        }
        let hidden = count - rows.count
        return QueueCard(
            summary: "\(count) waiting",
            rows: rows,
            more: hidden > 0 && !rows.isEmpty ? "+ \(hidden) more" : nil
        )
    }

    static func apiName(_ api: String?) -> String? {
        switch api {
        case "openai": "OpenAI"
        case "anthropic": "Anthropic"
        case let other?: other
        case nil: nil
        }
    }

    // MARK: - expert sources

    /// The routed expert lookups of the last request, split by where they were served from:
    /// this GPU's VRAM, the other GPU over PCIe, or system RAM on the CPU side.
    public struct ExpertSources: Sendable, Equatable {
        public struct Part: Identifiable, Sendable, Equatable {
            public var id: String { label }
            public var label: String
            /// 0...1
            public var fraction: Double
            public var text: String
            public var tone: Tone
        }

        public var parts: [Part]
        public var note: String
    }

    /// Basalt's split: hits are VRAM, minus the share fetched from the peer GPU; misses go to the CPU.
    static func expertSources(_ request: Request?, locale: Locale) -> ExpertSources? {
        guard let hit = request?.hitRate else { return nil }
        let peer = request?.pcieShare ?? 0
        let parts: [(String, Double, Tone)] = [
            ("VRAM", hit * (1 - peer), .normal),
            ("Peer GPU", peer, .info),
            ("CPU", (1 - hit) * (1 - peer), .warn),
        ]
        return ExpertSources(
            parts: parts.map { label, fraction, tone in
                ExpertSources.Part(
                    label: label,
                    fraction: max(0, min(1, fraction)),
                    text: "\(fmt(fraction * 100, 1, locale: locale))%",
                    tone: tone
                )
            },
            note: "Routed lookups, last request"
        )
    }
}
