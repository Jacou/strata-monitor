import Foundation
import Observation

/// The web page's thinking selector (`data-v` values): none / low / medium / high.
public enum ReasoningEffort: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case low
    case medium
    case high

    /// The button label.
    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// The web page's own hint for each choice (`o-thinking`).
    public var hint: String {
        switch self {
        case .none: "answers right away"
        case .low: "short"
        case .medium: "medium"
        case .high: "thorough (default)"
        }
    }

    /// What goes into `reasoning_effort`.
    public var wireValue: String { rawValue }
}

/// The sampling settings a chat request carries. Defaults are the web page's `DEFAULTS`
/// (docs/reference-app.js ~line 557): thinking "high", temperature 0.6, top_p 0.95, top_k 20,
/// no max tokens, no seed.
public struct ChatSamplingSettings: Codable, Sendable, Equatable {
    public var effort: ReasoningEffort
    public var temperature: Double
    public var topP: Double
    public var topK: Int
    /// nil / 0 is "not set", like the web page's empty field.
    public var maxTokens: Int?
    public var seed: Int?
    public var systemPrompt: String
    /// Open the "Thinking…" block while the model is still thinking.
    public var showsThinking: Bool

    public init(
        effort: ReasoningEffort = .high,
        temperature: Double = 0.6,
        topP: Double = 0.95,
        topK: Int = 20,
        maxTokens: Int? = nil,
        seed: Int? = nil,
        systemPrompt: String = "",
        showsThinking: Bool = true
    ) {
        self.effort = effort
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxTokens = maxTokens
        self.seed = seed
        self.systemPrompt = systemPrompt
        self.showsThinking = showsThinking
    }

    public static let defaults = ChatSamplingSettings()

    /// Greedy: temperature 0 sends only `temperature: 0` and the picker disables top_p / top_k.
    public var isGreedy: Bool { temperature == 0 }

    public var hasSystemPrompt: Bool { !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// "0.60" / "0 · greedy", the web page's `o-temp`.
    public var temperatureLabel: String {
        isGreedy ? "0 · greedy" : String(format: "%.2f", temperature)
    }

    public var maxTokensLabel: String { maxTokens.map(String.init) ?? "server default" }
    public var seedLabel: String { seed.map(String.init) ?? "random" }
}

/// The chat's sampling settings, kept in UserDefaults (no key lives here).
@Observable @MainActor
public final class ChatSettings {
    private static let storageKey = "chat.sampling"

    public var sampling: ChatSamplingSettings {
        didSet { save() }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, initial: ChatSamplingSettings? = nil) {
        self.defaults = defaults
        self.sampling = initial ?? Self.load(from: defaults) ?? .defaults
    }

    public func reset() {
        sampling = .defaults
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sampling) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// A half-written or old-shaped blob falls back to the web page's defaults rather than
    /// sending a request with junk settings.
    private static func load(from defaults: UserDefaults) -> ChatSamplingSettings? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(ChatSamplingSettings.self, from: data)
    }
}
