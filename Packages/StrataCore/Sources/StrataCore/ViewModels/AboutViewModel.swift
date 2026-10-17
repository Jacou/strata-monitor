import Foundation

/// One "fact" row, mirroring the web app's `facts(el, [[key, value, copyable]])`.
public struct AboutFact: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let value: String
    /// Non-nil means the row shows a copy button that puts this text on the pasteboard.
    public let copyValue: String?

    public init(label: String, value: String, copyValue: String? = nil) {
        self.id = label
        self.label = label
        self.value = value
        self.copyValue = copyValue
    }
}

public struct AboutSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let facts: [AboutFact]

    public init(title: String, facts: [AboutFact]) {
        self.id = title
        self.title = title
        self.facts = facts
    }
}

/// Everything `renderAbout` in docs/reference-app.js shows, from the same `/metrics` payload
/// the Monitor polls. Rows the server did not report are dropped, exactly like `facts()`.
public struct AboutViewModel: Equatable, Sendable {
    public let sections: [AboutSection]
    public let repositoryURL: URL
    /// True when the poller has not fetched anything yet.
    public let isEmpty: Bool

    public static let repository = "https://github.com/Niko1221/Strata"

    public init(metrics: Metrics?, baseURL: URL?, locale: Locale = .autoupdatingCurrent) {
        let eng = metrics?.engine
        let hw = metrics?.hardware
        let st = metrics?.hardwareStatic

        var sections: [AboutSection] = []

        // MARK: Engine
        var engine: [AboutFact] = []
        if let model = eng?.model, !model.isEmpty {
            engine.append(AboutFact(label: "Model", value: model))
        }
        engine.append(AboutFact(
            label: "Engine",
            value: eng?.version.map { $0.isEmpty ? "built from source" : "v\($0)" } ?? "built from source"
        ))
        if let maxContext = eng?.maxContext, maxContext > 0 {
            engine.append(AboutFact(label: "Context", value: "\(fmt(maxContext, 0, locale: locale)) tokens"))
        }
        if let kv = Self.kvName(eng?.kv) {
            let tail: String
            if let resident = eng?.kvResident, resident != 0 {
                tail = ", streamed: \(fmt(resident, 0, locale: locale)) positions per layer in VRAM, the rest in RAM"
            } else {
                tail = ", all in VRAM"
            }
            engine.append(AboutFact(label: "KV cache", value: kv + tail))
        }
        if let slots = eng?.expertSlots, slots != 0 {
            let mib = eng?.expertCacheMib ?? 0
            engine.append(AboutFact(
                label: "Experts in VRAM",
                value: "\(fmt(slots, 0, locale: locale)) (\(gb(mib * 1_048_576, 1, locale: locale)) GB)"
            ))
        }
        if let spec = eng?.spec, spec != 0 {
            // `eng.mtp_max || eng.spec`: a zero falls back to the spec depth.
            let drafts = max(0, (eng?.mtpMax.flatMap { $0 != 0 ? $0 : nil }) ?? spec) - 1
            let lookup = (eng?.lookup ?? 0) != 0 ? ", prompt lookup on" : ""
            engine.append(AboutFact(
                label: "Speculation",
                value: "MTP drafts up to \(fmt(drafts, 0, locale: locale)) tokens\(lookup)"
            ))
        }
        engine.append(AboutFact(label: "Images", value: eng?.images == true ? "on" : "off"))
        if let projection = Self.projectionText(eng?.cvec) {
            engine.append(AboutFact(label: "Experimental speed projection", value: projection))
        }
        sections.append(AboutSection(title: "Engine", facts: engine))

        // MARK: Hardware
        var hardware: [AboutFact] = []
        if let name = st?.gpuName, !name.isEmpty {
            let mem = hw?.gpuMemTotal.map { ", \(gb($0, 0, locale: locale)) GB" } ?? ""
            hardware.append(AboutFact(label: "GPU", value: name + mem))
        } else {
            hardware.append(AboutFact(label: "GPU", value: "not readable (NVML)"))
        }
        if let name = st?.cpuName, !name.isEmpty {
            let threads = (st?.threads ?? 0) != 0 ? ", \(st!.threads!) threads" : ""
            hardware.append(AboutFact(label: "CPU", value: name + threads))
        }
        if let ram = hw?.ramTotal, ram != 0 {
            hardware.append(AboutFact(label: "RAM", value: "\(gb(ram, 0, locale: locale)) GB"))
        }
        sections.append(AboutSection(title: "Hardware", facts: hardware))

        // MARK: API — the endpoints this server answers, each copyable
        var api: [AboutFact] = []
        if let base = Self.baseString(baseURL) {
            api.append(AboutFact(label: "OpenAI base URL", value: "\(base)/v1", copyValue: "\(base)/v1"))
            api.append(AboutFact(label: "Anthropic base URL", value: base, copyValue: base))
        }
        if let model = eng?.model, !model.isEmpty {
            api.append(AboutFact(label: "Model name", value: model, copyValue: model))
        }
        sections.append(AboutSection(title: "API", facts: api))

        self.sections = sections.filter { !$0.facts.isEmpty }
        self.repositoryURL = URL(string: Self.repository)!
        self.isEmpty = metrics == nil
    }

    /// `{int8: "8-bit", q4_0: "4-bit (Hadamard-rotated)", fp16: "16-bit"}[eng.kv] || eng.kv`
    static func kvName(_ kv: String?) -> String? {
        guard let kv, !kv.isEmpty else { return nil }
        switch kv {
        case "int8": return "8-bit"
        case "q4_0": return "4-bit (Hadamard-rotated)"
        case "fp16": return "16-bit"
        default: return kv
        }
    }

    /// `projectionText(eng.cvec)`: nil when the engine reports no control vector.
    static func projectionText(_ cvec: LenientString?) -> String? {
        guard let raw = cvec?.raw, !raw.isEmpty, raw != "0" else { return nil }
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let mode = parts[0]
        let range = parts.count > 1 ? parts[1] : ""
        let single = parts.count > 2 ? parts[2] : ""
        let layers = range.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        let from = layers.first ?? ""
        let to = layers.count > 1 ? layers[1] : ""
        let name = mode == "project" ? "Projection" : "Additive"
        let layer = single.isEmpty ? "" : " (layer \(single.replacingOccurrences(of: "single", with: ""))'s direction)"
        return "\(name) control vector on layers \(from)–\(to)\(layer). Per chat in Sampling. "
            + "Its package describes the vector as a refusal-direction projection; measure the speed yourself"
    }

    /// The server address without a trailing slash, so `<base>/v1` does not double up.
    static func baseString(_ url: URL?) -> String? {
        guard let url else { return nil }
        guard let string = url.absoluteString.split(separator: "?", omittingEmptySubsequences: false).first.map(String.init) else { return nil }
        let trimmed = string.hasSuffix("/") ? String(string.dropLast()) : string
        return trimmed.isEmpty ? nil : trimmed
    }
}
