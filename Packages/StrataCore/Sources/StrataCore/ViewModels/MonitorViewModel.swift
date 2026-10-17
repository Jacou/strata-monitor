import Foundation

/// All the derivation the Monitor screen needs, mirroring `renderMonitor`, `renderConvCache`
/// and `renderTotals` in docs/reference-app.js. Plain value types so the views stay thin
/// and every label and sub-line is testable.
public struct MonitorViewModel: Sendable, Equatable {
    public enum Tone: String, Sendable, Equatable {
        case normal, info, warn, danger
    }

    // MARK: - live state card

    public struct LiveCard: Sendable, Equatable {
        public var label: String
        public var detail: String
        /// 0...100
        public var percent: Double
        public var tone: Tone
    }

    // MARK: - metric tiles

    public enum MetricKind: String, CaseIterable, Sendable, Equatable {
        case speed, gpu, vram, temp, power, pcie, cpu, disk
    }

    public struct Secondary: Sendable, Equatable {
        public var value: String
        public var unit: String
        public var sub: String
        public var series: [Double]
        public var seriesMax: Double?

        /// "126 tokens per second, Prefill last request".
        public var accessibilityLabel: String {
            "\(MonitorViewModel.spoken(value, unit)), \(sub)"
        }
    }

    public struct Metric: Identifiable, Sendable, Equatable {
        public var kind: MetricKind
        public var id: MetricKind { kind }
        public var label: String
        /// "–" when the server did not report it.
        public var value: String
        public var unit: String
        public var sub: String
        public var series: [Double]
        /// Ceiling for the sparkline, like the `max` in the web app's `spark()`.
        public var seriesMax: Double?
        public var tone: Tone
        /// The Speed tile carries a second value + series (prefill).
        public var secondary: Secondary?

        /// One VoiceOver phrase per tile: "Speed, 98.5 tokens per second, decode last request".
        public var accessibilityLabel: String {
            var parts = [label, MonitorViewModel.spoken(value, unit)]
            if !sub.isEmpty { parts.append(sub) }
            if let secondary { parts.append(secondary.accessibilityLabel) }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - bars and the context ring

    public struct Bar: Sendable, Equatable {
        public var text: String
        public var percent: Double
        public var tone: Tone
    }

    public struct Context: Sendable, Equatable {
        public var percentText: String
        public var sub: String
        /// 0...1
        public var fraction: Double
        /// A near-zero arc would draw just its round cap — the web app hides it.
        public var arcVisible: Bool
    }

    // MARK: - requests

    public enum BadgeStyle: Sendable, Equatable {
        case neutral, warning, danger
    }

    public struct RequestRow: Identifiable, Sendable, Equatable {
        public var id: String
        public var timeText: String
        public var finishText: String
        public var badge: BadgeStyle
        public var projectionText: String?
        public var promptText: String
        public var reusedText: String
        public var outputText: String
        public var tokSText: String
        public var hitText: String
        /// "+3.6% PCIe", or nil when there is none to show.
        public var pcieText: String?
        public var durationText: String
        /// What the sheet shows when the row is tapped.
        public var detail: RequestDetail
    }

    /// One request, opened up. Mirrors the columns the web table shows plus the fields it only
    /// keeps in the payload (prefill / decode milliseconds, drafts, images).
    public struct RequestDetail: Identifiable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var badgeText: String
        public var badge: BadgeStyle
        /// "1,155 tokens · 92.9 t/s · 15.5 s"
        public var headline: String
        public var facts: [Fact]
        /// Drafts accepted / offered for this request, nil when the server reported neither.
        public var acceptance: Bar?
    }

    // MARK: - session

    /// The engine's whole run, replacing the old one-line totals: uptime, throughput and how much
    /// of the speculative work paid off.
    public struct Session: Sendable, Equatable {
        public var headline: String
        public var uptimeText: String
        public var facts: [Fact]
        /// Speculative acceptance, nil when the server reports no drafts (speculation off).
        public var acceptance: Bar?
        public var acceptanceNote: String
    }

    // MARK: - conversation cache

    public struct Fact: Identifiable, Sendable, Equatable {
        public var id: String { key }
        public var key: String
        public var value: String
    }

    public struct ConvCache: Sendable, Equatable {
        public var enabled: Bool
        public var slotsText: String
        public var slotsPercent: Double
        public var memoryText: String
        public var memoryPercent: Double
        public var summary: String
        public var facts: [Fact]
        public var note: String
    }

    // MARK: - the screen

    public var live: LiveCard
    public var metrics: [Metric]
    public var context: Context
    public var experts: Bar
    public var ram: Bar
    public var temp: Bar
    /// nil when the server is too old to report it — the card is hidden.
    public var convCache: ConvCache?
    public var requests: [RequestRow]
    public var noRequestsText: String?
    /// nil when the server has not counted a request yet — the card is hidden.
    public var session: Session?
    /// "Show all (224)", or nil when everything kept is already on screen.
    public var showAllLabel: String?
    /// The button while showing all: "Show fewer", or "Show fewer · newest 100 of 500" when capped.
    public var showFewerLabel: String = "Show fewer"

    /// At most this many rows when "Show all" is on: the newest ones. A list is not a log.
    public static let maxShownRequests = 100

    public init(
        metrics: Metrics,
        now: Date = .now,
        locale: Locale = .autoupdatingCurrent,
        allRequests: Bool = false,
        fullRequests: [Request]? = nil,
        modelLoaded: Bool? = nil
    ) {
        let live = metrics.live
        let hw = metrics.hardware
        let st = metrics.hardwareStatic
        let eng = metrics.engine
        let history = metrics.history
        let all = metrics.requests ?? []
        let last = all.first
        // "Show all" draws from the separately fetched full list when there is one (newest first,
        // whatever order the server used), the 1 s payload otherwise.
        let pool = allRequests
            ? ((fullRequests?.isEmpty == false ? fullRequests! : all).sorted { ($0.time ?? 0) > ($1.time ?? 0) })
            : all
        let shown = allRequests ? Array(pool.prefix(Self.maxShownRequests)) : Array(all.prefix(12))

        self.live = Self.liveCard(live: live, last: last, modelLoaded: modelLoaded, locale: locale)
        self.metrics = Self.metricTiles(
            live: live, hw: hw, st: st, eng: eng, history: history, last: last, locale: locale
        )
        self.context = Self.contextInfo(live: live, eng: eng, last: last, locale: locale)
        self.experts = Self.expertBar(eng: eng, hw: hw, locale: locale)
        self.ram = Self.ramBar(hw: hw, locale: locale)
        self.temp = Self.tempBar(hw: hw, locale: locale)
        self.convCache = Self.convCacheInfo(metrics.conversationCache, now: now, locale: locale)
        self.requests = shown.map { Self.requestRow($0, locale: locale) }
        self.noRequestsText = all.isEmpty ? "No requests yet" : nil
        self.session = Self.session(metrics.totals, now: now, locale: locale)
        let kept = metrics.requestsKept ?? all.count
        self.showAllLabel = kept > 12 ? "Show all (\(fmt(Double(kept), 0, locale: locale)))" : nil
        if allRequests, kept > shown.count {
            self.showFewerLabel = "Show fewer · newest \(shown.count) of \(fmt(Double(kept), 0, locale: locale))"
        }
    }

    // MARK: - live card

    private static func liveCard(live: Live?, last: Request?, modelLoaded: Bool?, locale: Locale) -> LiveCard {
        switch live?.state {
        case .reading:
            let total = live?.promptTotal ?? 0
            if total > 0 {
                let read = live?.promptRead ?? 0
                let percent = (100 * read) / total
                return LiveCard(
                    label: "Reading prompt",
                    detail: "\(fmt(read, 0, locale: locale)) / \(fmt(total, 0, locale: locale)) tokens · \(fmt(percent, 0, locale: locale))%",
                    percent: percent,
                    tone: .info
                )
            }
            return LiveCard(
                label: "Reading prompt",
                detail: "\(fmt(live?.promptTokens, 0, locale: locale)) tokens",
                percent: 0,
                tone: .info
            )
        case .generating:
            let phase = live?.phase
            let label = phase.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Generating"
            let maxTokens = live?.maxTokens ?? 0
            let percent = maxTokens > 0 ? min(100, (100 * (live?.generated ?? 0)) / maxTokens) : 0
            return LiveCard(
                label: label,
                detail: "\(fmt(live?.generated, 0, locale: locale)) tokens · \(fmt(live?.tokS, 1, locale: locale)) tok/s",
                percent: percent,
                tone: .normal
            )
        case .idle, .other, .none:
            // /health says the weights are not resident: the first request has to load them.
            if modelLoaded == false {
                return LiveCard(
                    label: "Waiting for the first request to load the model",
                    detail: "",
                    percent: 0,
                    tone: .normal
                )
            }
            if let last {
                let speed = last.decodeTokS.map { " at \(fmt($0, 1, locale: locale)) tok/s" } ?? ""
                return LiveCard(
                    label: "Waiting for a request",
                    detail: "last: \(fmt(last.outputTokens, 0, locale: locale)) tokens\(speed)",
                    percent: 0,
                    tone: .normal
                )
            }
            return LiveCard(label: "Waiting for a request", detail: "", percent: 0, tone: .normal)
        }
    }

    // MARK: - metric tiles

    private static func metricTiles(
        live: Live?, hw: Hardware?, st: HardwareStatic?, eng: Engine?, history: History?, last: Request?, locale: Locale
    ) -> [Metric] {
        let gpus = hw?.gpus ?? []
        let multi = gpus.count > 1
        func per(_ f: (GPU) -> String) -> String {
            gpus.map { "GPU \($0.index.map(String.init) ?? "?") \(f($0))" }.joined(separator: " · ")
        }

        // Speed: decode now / last request, plus prefill
        let generating = live?.state == .generating
        let speed = generating ? live?.tokS : last?.decodeTokS
        let speedSub = generating ? "Decode now" : (last != nil ? "Decode last request" : "Decode")
        // Same branch as the web page: while not idle the engine reports the mean itself,
        // otherwise it is worked out from the last request's unread prompt tokens.
        let prefillValue: Double?
        if live?.state != .idle {
            prefillValue = live?.prefillTokSMean
        } else if let last, let promptMs = last.promptMs, promptMs > 0 {
            prefillValue = max(0, (last.promptTokens ?? 0) - (last.reused ?? 0)) / (promptMs / 1000)
        } else {
            prefillValue = nil
        }
        let prefillSub = live?.state == .reading ? "Prefill now"
            : (generating ? "Prefill this request" : (last != nil ? "Prefill last request" : "Prefill"))

        let tiles: [Metric] = [
            Metric(
                kind: .speed,
                label: "Speed",
                value: fmt(speed, 1, locale: locale),
                unit: "t/s",
                sub: speedSub,
                series: history?.tokS ?? [],
                seriesMax: nil,
                tone: .normal,
                secondary: Secondary(
                    value: fmt(prefillValue, 0, locale: locale),
                    unit: "t/s",
                    sub: prefillSub,
                    series: history?.prefillTokSMean ?? [],
                    seriesMax: nil
                )
            ),
            Metric(
                kind: .gpu,
                label: "GPU load",
                value: fmt(hw?.gpuUtil, 0, locale: locale),
                unit: "%",
                sub: multi ? per { $0.util.map { fmt($0, 0, locale: locale) + "%" } ?? notAvailable } : (st?.gpuName ?? ""),
                series: history?.gpuUtil ?? [],
                seriesMax: 100,
                tone: .normal,
                secondary: nil
            ),
            Metric(
                kind: .vram,
                label: "VRAM",
                value: gb(hw?.gpuMemUsed, 1, locale: locale),
                unit: hw?.gpuMemTotal.map { "/ \(gb($0, 0, locale: locale)) GB" } ?? "GB",
                sub: multi
                    ? per { $0.memUsed.map { gb($0, 1, locale: locale) + " GB" } ?? notAvailable }
                    : (eng?.expertSlots.map { "\(fmt($0, 0, locale: locale)) experts cached" } ?? ""),
                series: history?.gpuMemUsed ?? [],
                seriesMax: hw?.gpuMemTotal,
                tone: .normal,
                secondary: nil
            ),
            Metric(
                kind: .temp,
                label: "GPU temp",
                value: fmt(hw?.gpuTemp, 0, locale: locale),
                unit: "°C",
                sub: multi ? per { $0.temp.map { fmt($0, 0, locale: locale) + "°" } ?? notAvailable } : "",
                series: history?.gpuTemp ?? [],
                seriesMax: 90,
                tone: .warn,
                secondary: nil
            ),
            Metric(
                kind: .power,
                label: "Power",
                value: fmt(hw?.gpuPower, 0, locale: locale),
                unit: "W",
                sub: hw?.gpuPowerLimit.map { "of \(fmt($0, 0, locale: locale)) W limit" } ?? "",
                series: history?.gpuPower ?? [],
                seriesMax: hw?.gpuPowerLimit,
                tone: .normal,
                secondary: nil
            ),
            pcieTile(hw: hw, history: history, locale: locale),
            Metric(
                kind: .cpu,
                label: "CPU",
                value: fmt(hw?.cpu, 0, locale: locale),
                unit: "%",
                sub: st?.threads.map { "\((st?.cores).map { "\(fmt(Double($0), 0, locale: locale)) cores · " } ?? "")\(fmt(Double($0), 0, locale: locale)) threads" } ?? "",
                series: history?.cpu ?? [],
                seriesMax: 100,
                tone: .normal,
                secondary: nil
            ),
            diskTile(hw: hw, st: st, history: history, locale: locale),
        ]
        return tiles
    }

    private static func pcieTile(hw: Hardware?, history: History?, locale: Locale) -> Metric {
        let gen = hw?.gpuPcieGenMax ?? hw?.gpuPcieGen
        var sub = ""
        if let rx = hw?.gpuPcieRxMb {
            sub = "to GPU \(fmt(rx, rx < 10 ? 1 : 0, locale: locale)) MB/s"
            if let gen, let current = hw?.gpuPcieGen, current < gen {
                sub += " · idle Gen\(current)"
            }
        }
        return Metric(
            kind: .pcie,
            label: "PCIe",
            value: gen.map { "Gen\($0)" } ?? notAvailable,
            unit: hw?.gpuPcieWidth.map { "x\($0)" } ?? "",
            sub: sub,
            series: history?.gpuPcieRxMb ?? [],
            seriesMax: nil,
            tone: .info,
            secondary: nil
        )
    }

    private static func diskTile(hw: Hardware?, st: HardwareStatic?, history: History?, locale: Locale) -> Metric {
        guard let read = hw?.diskReadMb else {
            return Metric(
                kind: .disk,
                label: "Disk read",
                value: notAvailable,
                unit: "",
                sub: st?.psutil == true ? "" : "needs psutil (setup installs it)",
                series: history?.diskReadMb ?? [],
                seriesMax: nil,
                tone: .info,
                secondary: nil
            )
        }
        let big = read >= 1000
        return Metric(
            kind: .disk,
            label: "Disk read",
            value: big ? fmt(read / 1024, 2, locale: locale) : fmt(read, read < 10 ? 1 : 0, locale: locale),
            unit: big ? "GB/s" : "MB/s",
            sub: hw?.diskWriteMb.map { "write \(fmt($0, 1, locale: locale)) MB/s" } ?? "",
            series: history?.diskReadMb ?? [],
            seriesMax: nil,
            tone: .info,
            secondary: nil
        )
    }

    // MARK: - context ring, expert cache, RAM, temperature

    private static func contextInfo(live: Live?, eng: Engine?, last: Request?, locale: Locale) -> Context {
        let max = eng?.maxContext ?? 0
        var used = 0.0
        if live?.state != .idle {
            used = (live?.promptTokens ?? 0) + (live?.generated ?? 0)
        } else if let last {
            used = (last.promptTokens ?? 0) + (last.outputTokens ?? 0)
        }
        let fraction = max > 0 ? min(1, used / max) : 0
        return Context(
            percentText: "\(fmt(fraction * 100, 0, locale: locale))%",
            sub: max > 0 ? "\(kfmt(used, locale: locale)) / \(ctxfmt(max, locale: locale))" : notAvailable,
            fraction: fraction,
            arcVisible: 235.6 * fraction >= 3
        )
    }

    private static func expertBar(eng: Engine?, hw: Hardware?, locale: Locale) -> Bar {
        let cacheBytes = (eng?.expertCacheMib ?? 0) * 1_048_576
        let total = hw?.gpuMemTotal ?? 0
        return Bar(
            text: eng?.expertSlots.map { "\(fmt($0, 0, locale: locale)) · \(gb(cacheBytes, 1, locale: locale)) GB" } ?? notAvailable,
            percent: total > 0 ? min(100, (100 * cacheBytes) / total) : 0,
            tone: .normal
        )
    }

    private static func ramBar(hw: Hardware?, locale: Locale) -> Bar {
        let total = hw?.ramTotal ?? 0
        let used = hw?.ramUsed ?? 0
        let percent = total > 0 ? (100 * used) / total : 0
        return Bar(
            text: total > 0 ? "\(gb(used, 1, locale: locale)) / \(gb(total, 0, locale: locale)) GB" : notAvailable,
            percent: percent,
            tone: percent > 92 ? .danger : .normal
        )
    }

    private static func tempBar(hw: Hardware?, locale: Locale) -> Bar {
        Bar(
            text: hw?.gpuTemp.map { "\(fmt($0, 0, locale: locale)) °C" } ?? notAvailable,
            percent: hw?.gpuTemp.map { min(100, $0) } ?? 0,
            tone: .normal
        )
    }

    // MARK: - conversation cache

    private static func convCacheInfo(_ cache: ConversationCache?, now: Date, locale: Locale) -> ConvCache? {
        guard let cache else { return nil }
        let enabled = cache.enabled == true
        let budgetBytes = (cache.budgetMib ?? 0) * 1_048_576

        var facts: [Fact] = []
        if let lastPrompt = cache.lastPrompt {
            facts.append(Fact(
                key: "Last request",
                value: "\(fmt(cache.lastReused ?? 0, 0, locale: locale)) of \(fmt(lastPrompt, 0, locale: locale)) prompt tokens reused"
            ))
        }
        if (cache.requests ?? 0) > 0 {
            let share = (cache.promptTokens ?? 0) > 0
                ? " (\(fmt((100 * (cache.reusedTokens ?? 0)) / (cache.promptTokens ?? 1), 0, locale: locale))% of all prompt tokens)"
                : ""
            facts.append(Fact(
                key: "Reused since start",
                value: "\(fmt(cache.reusedTokens, 0, locale: locale)) tokens\(share)"
            ))
        }
        if enabled {
            let evictions = (cache.evictions ?? 0) > 0 ? " · \(fmt(cache.evictions, 0, locale: locale)) evicted" : ""
            facts.append(Fact(
                key: "Parked / restored",
                value: "\(fmt(cache.parks, 0, locale: locale)) / \(fmt(cache.restores, 0, locale: locale))\(evictions)"
            ))
            if let event = cache.lastEvent {
                let name = event == "parked" ? "Parked" : "Restored"
                facts.append(Fact(
                    key: "Last switch",
                    value: "\(name) \(fmt(cache.lastTokens, 0, locale: locale)) tokens, \(since(cache.lastAt, now: now, locale: locale))"
                ))
            }
        }

        return ConvCache(
            enabled: enabled,
            slotsText: "\(fmt(cache.parked, 0, locale: locale)) / \(fmt(cache.slots, 0, locale: locale))",
            slotsPercent: percent(cache.parked, cache.slots),
            memoryText: "\(gb(cache.bytes, 1, locale: locale)) / \(gb(budgetBytes, 1, locale: locale)) GB",
            memoryPercent: percent(cache.bytes, budgetBytes),
            summary: (cache.requests ?? 0) > 0
                ? "\(fmt(cache.requestsReused, 0, locale: locale)) of \(fmt(cache.requests, 0, locale: locale)) requests reused part of their prompt"
                : "",
            facts: facts,
            note: enabled
                ? "A request that continues a parked conversation gets its state back instead of reading it again; the oldest goes when the slots or the memory are full."
                : "The engine keeps the last conversation's state, so a follow-up reads only what is new. To keep several conversations (agents taking turns), add \"--conversation-cache-mib\", \"8192\" to the run config's args."
        )
    }

    private static func percent(_ value: Double?, _ total: Double?) -> Double {
        guard let total, total > 0 else { return 0 }
        return min(100, (100 * (value ?? 0)) / total)
    }

    /// A unit written the way you would say it, for VoiceOver.
    static func spoken(_ value: String, _ unit: String) -> String {
        if value == notAvailable { return "no value reported" }
        let trimmed = unit.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return value }
        if trimmed.hasPrefix("/ ") { return "\(value) of \(trimmed.dropFirst(2))" }   // "31.4 of 32 GB"
        switch trimmed {
        case "t/s": return "\(value) tokens per second"
        case "%": return "\(value) percent"
        case "W": return "\(value) watts"
        case "°C": return "\(value) degrees Celsius"
        case "MB/s": return "\(value) megabytes per second"
        case "GB/s": return "\(value) gigabytes per second"
        default: return "\(value) \(trimmed)"
        }
    }

    // MARK: - requests

    private static func requestRow(_ request: Request, locale: Locale) -> RequestRow {
        let (finishText, badge) = badge(for: request.finish)
        let hit = request.hitRate.map { "\(fmt($0 * 100, 1, locale: locale))%" } ?? notAvailable
        let pcie = (request.pcieShare ?? 0) != 0
            ? "+\(fmt((request.pcieShare ?? 0) * 100, 1, locale: locale))% PCIe"
            : nil
        return RequestRow(
            id: request.id,
            timeText: timeString(request.time, locale: locale),
            finishText: finishText,
            badge: badge,
            projectionText: request.projection.map { $0 ? "ESP" : "stock" },
            promptText: fmt(request.promptTokens, 0, locale: locale),
            reusedText: fmt(request.reused, 0, locale: locale),
            outputText: fmt(request.outputTokens, 0, locale: locale),
            tokSText: fmt(request.decodeTokS, 1, locale: locale),
            hitText: hit,
            pcieText: pcie,
            durationText: request.durationS.map { "\(fmt($0, 1, locale: locale)) s" } ?? notAvailable,
            detail: requestDetail(request, locale: locale)
        )
    }

    /// The sheet's facts. Anything the server did not report is left out rather than shown as "–",
    /// so a short payload gives a short sheet.
    private static func requestDetail(_ request: Request, locale: Locale) -> RequestDetail {
        let (finishText, badge) = badge(for: request.finish)
        let prompt = request.promptTokens ?? 0
        let reused = request.reused ?? 0
        // "read" is what the engine had to bring in: the server's own figure when it reports one,
        // otherwise prompt minus reused.
        let read = request.promptRead ?? max(0, prompt - reused)

        var facts: [Fact] = [
            Fact(key: "Time", value: timeString(request.time, locale: locale)),
            Fact(key: "Finish", value: finishText),
            Fact(key: "Duration", value: request.durationS.map { "\(fmt($0, 1, locale: locale)) s" } ?? notAvailable),
            Fact(key: "Prompt", value: fmt(prompt, 0, locale: locale)),
            Fact(key: "Reused", value: "\(fmt(reused, 0, locale: locale)) (\(fmt((100 * reused) / max(prompt, 1), 1, locale: locale))%)"),
            Fact(key: "Read", value: fmt(read, 0, locale: locale)),
            Fact(key: "Output", value: fmt(request.outputTokens, 0, locale: locale)),
        ]

        if let promptMs = request.promptMs, promptMs > 0 {
            let speed = read > 0 ? " · \(fmt(read / (promptMs / 1000), 0, locale: locale)) tok/s" : ""
            facts.append(Fact(key: "Prefill", value: "\(fmt(promptMs, 0, locale: locale)) ms\(speed)"))
        }
        if let decodeMs = request.decodeMs, decodeMs > 0 {
            let speed = request.decodeTokS.map { " · \(fmt($0, 1, locale: locale)) tok/s" }
                ?? (request.outputTokens.map { $0 > 0 ? " · \(fmt($0 / (decodeMs / 1000), 1, locale: locale)) tok/s" : "" } ?? "")
            facts.append(Fact(key: "Decode", value: "\(fmt(decodeMs, 0, locale: locale)) ms\(speed)"))
        }

        let acceptance = acceptanceBar(offered: request.draftsOffered, accepted: request.draftsAccepted, locale: locale)
        if let acceptance {
            facts.append(Fact(
                key: "Drafts",
                value: "\(fmt(request.draftsAccepted ?? 0, 0, locale: locale)) of \(fmt(request.draftsOffered ?? 0, 0, locale: locale)) accepted (\(fmt(acceptance.percent, 0, locale: locale))%)"
            ))
        }

        facts.append(Fact(key: "Expert hit rate", value: request.hitRate.map { "\(fmt($0 * 100, 1, locale: locale))%" } ?? notAvailable))
        if let pcie = request.pcieShare, pcie != 0 {
            facts.append(Fact(key: "PCIe share", value: "+\(fmt(pcie * 100, 1, locale: locale))%"))
        }
        if let recoveries = request.reasoningRecoveries, recoveries > 0 {
            facts.append(Fact(key: "Reasoning", value: "\(fmt(recoveries, 0, locale: locale)) tool calls recovered"))
        }
        if let coverage = request.reasoningRepeatCoverage {
            facts.append(Fact(key: "Repeat coverage", value: "\(fmt(coverage * 100, 1, locale: locale))%"))
        }
        if let images = imageText(request, locale: locale) {
            facts.append(Fact(key: "Images", value: images))
        }
        if let projection = request.projection {
            facts.append(Fact(key: "Speed projection", value: projection ? "on" : "off"))
        }

        let speed = request.decodeTokS.map { " · \(fmt($0, 1, locale: locale)) t/s" } ?? ""
        let duration = request.durationS.map { " · \(fmt($0, 1, locale: locale)) s" } ?? ""
        return RequestDetail(
            id: request.id,
            title: timeString(request.time, locale: locale),
            badgeText: finishText,
            badge: badge,
            headline: "\(fmt(request.outputTokens, 0, locale: locale)) tokens\(speed)\(duration)",
            facts: facts,
            acceptance: acceptance
        )
    }

    /// "3 in RAM · 2 files (1.4 MB)", or nil when this request carried no images.
    private static func imageText(_ request: Request, locale: Locale) -> String? {
        let ram = request.ramBlobs ?? 0
        let files = request.fileBlobs ?? 0
        let megabytes = request.fileMb ?? 0
        guard ram > 0 || files > 0 || megabytes > 0 else { return nil }
        var parts: [String] = []
        if ram > 0 { parts.append("\(fmt(ram, 0, locale: locale)) in RAM") }
        if files > 0 { parts.append("\(fmt(files, 0, locale: locale)) files") }
        if megabytes > 0 { parts.append("\(fmt(megabytes, 1, locale: locale)) MB") }
        return parts.joined(separator: " · ")
    }

    private static func badge(for finish: RequestFinish?) -> (String, BadgeStyle) {
        switch finish {
        case .stop: ("Done", .neutral)
        case .length: ("Max tokens", .neutral)
        case .cancel: ("Stopped", .warning)
        case .disconnect: ("Closed", .warning)
        case .error: ("Error", .danger)
        case .other(let raw): (raw, .neutral)
        case .none: (notAvailable, .neutral)
        }
    }

    // MARK: - session

    private static func session(_ totals: Totals?, now: Date, locale: Locale) -> Session? {
        guard let totals, (totals.requests ?? 0) > 0 else { return nil }

        let read = (totals.promptTokens ?? 0) - (totals.reused ?? 0)
        let promptSpeed = (totals.promptMs ?? 0) > 0 && read > 0
            ? " at \(fmt(read / ((totals.promptMs ?? 0) / 1000), 0, locale: locale)) tok/s"
            : ""
        let outputSpeed = (totals.decodeMs ?? 0) > 0 && (totals.outputTokens ?? 0) > 0
            ? " at \(fmt((totals.outputTokens ?? 0) / ((totals.decodeMs ?? 0) / 1000), 1, locale: locale)) tok/s"
            : ""
        let since = totals.since.map { sinceDateLine($0, locale: locale) } ?? notAvailable
        let up = totals.since.map { uptimeText(max(0, now.timeIntervalSince1970 - $0), locale: locale) } ?? notAvailable

        var facts: [Fact] = [
            Fact(key: "Requests", value: fmt(totals.requests, 0, locale: locale)),
            Fact(key: "Prompt read", value: "\(fmt(read, 0, locale: locale)) tokens\(promptSpeed)"),
            Fact(key: "Written", value: "\(fmt(totals.outputTokens, 0, locale: locale)) tokens\(outputSpeed)"),
        ]
        if (totals.promptTokens ?? 0) > 0 {
            facts.append(Fact(
                key: "Reused",
                value: "\(fmt(totals.reused, 0, locale: locale)) tokens (\(fmt((100 * (totals.reused ?? 0)) / (totals.promptTokens ?? 1), 0, locale: locale))% of prompt)"
            ))
        }
        if let recovered = totals.toolCallsFromReasoning, recovered > 0 {
            facts.append(Fact(key: "Tool calls", value: "\(fmt(recovered, 0, locale: locale)) recovered from reasoning"))
        }

        let acceptance = acceptanceBar(offered: totals.draftsOffered, accepted: totals.draftsAccepted, locale: locale)

        return Session(
            headline: "Since \(since)",
            uptimeText: up,
            facts: facts,
            acceptance: acceptance,
            acceptanceNote: "Speculative decoding drafts the next tokens ahead of time; acceptance is the share the engine kept."
        )
    }

    /// drafts_accepted / drafts_offered, or nil when the server offered none (speculation off).
    private static func acceptanceBar(offered: Double?, accepted: Double?, locale: Locale) -> Bar? {
        guard let offered, offered > 0 else { return nil }
        let accepted = accepted ?? 0
        let percent = min(100, (100 * accepted) / offered)
        return Bar(
            text: "\(fmt(percent, 0, locale: locale))% · \(fmt(accepted, 0, locale: locale)) of \(fmt(offered, 0, locale: locale))",
            percent: percent,
            tone: percent >= 50 ? .normal : .warn
        )
    }

}
