import Foundation

/// The Config screen: the server's editable keys, grouped by prefix, and the diff a Save sends.
public struct ConfigViewModel: Sendable, Equatable {
    public struct Row: Identifiable, Sendable, Equatable {
        public var id: String { key }

        public var key: String
        /// "0.6", "on", or "default" when the file's own value is in force.
        public var valueText: String
        public var isDefault: Bool
        public var kindLabel: String
        public var help: String
    }

    public struct Group: Identifiable, Sendable, Equatable {
        public var id: String { name }

        /// The prefix as the server spells it.
        public var name: String
        /// The section header: "sampling" reads as "Sampling".
        public var title: String { name.prefix(1).uppercased() + name.dropFirst() }
        public var rows: [Row]
    }

    public var file: String
    public var groups: [Group]
    /// The server's own order, which the editor and the diff work from.
    public var keys: [ConfigKey]

    public init(_ response: ConfigResponse?) {
        let keys = response?.keys ?? []
        self.keys = keys
        self.file = response?.file ?? ""

        var ordered: [String] = []
        var buckets: [String: [Row]] = [:]
        for key in keys {
            let group = Self.group(for: key.key)
            if buckets[group] == nil {
                ordered.append(group)
                buckets[group] = []
            }
            buckets[group, default: []].append(Row(
                key: key.key,
                valueText: key.value?.text ?? "default",
                isDefault: key.value == nil || key.value == .null,
                kindLabel: key.kind.label,
                help: key.help ?? ""
            ))
        }
        self.groups = ordered.compactMap { name in buckets[name].map { Group(name: name, rows: $0) } }
    }

    public var isEmpty: Bool { groups.isEmpty }

    public var keyCount: Int { keys.count }

    /// `sampling.top_k` belongs with `sampling.temperature`; a key with no prefix stands alone.
    public static func group(for key: String) -> String {
        guard let dot = key.firstIndex(of: ".") else { return "General" }
        return String(key[..<dot])
    }

    /// Only the keys whose value really changed. `null` is a real change: back to the default.
    public static func changes(keys: [ConfigKey], edits: [String: ConfigValue?]) -> [String: ConfigValue] {
        var set: [String: ConfigValue] = [:]
        for key in keys where key.key.isEmpty == false {
            guard edits[key.key] != nil else { continue }        // untouched keys are never sent
            let proposed = edits[key.key] ?? nil
            if differs(from: key.value, to: proposed) {
                set[key.key] = proposed ?? .null
            }
        }
        return set
    }

    /// The web page compares `JSON.stringify(old ?? null)` with the new value; this is the same
    /// test, with a number and a numeric string treated as the same value.
    public static func differs(from old: ConfigValue?, to proposed: ConfigValue?) -> Bool {
        let left = old ?? .null
        let right = proposed ?? .null
        switch (left, right) {
        case (.number(let a), .number(let b)): return a != b
        case (.string(let a), .string(let b)): return a != b
        case (.bool(let a), .bool(let b)): return a != b
        case (.names(let a), .names(let b)): return a != b
        case (.number(let a), .string(let b)): return a != Double(b)
        case (.string(let a), .number(let b)): return Double(a) != b
        case (.null, .null): return false
        default: return true
        }
    }
}
