import Foundation

// Model settings (`GET /config`, `POST /config`).
//
// The server lists the documented keys of its run config, checks every value itself, and keeps
// every other key of the file as it is. A `null` in the `set` body means "use the default again".

/// `GET /config`.
public struct ConfigResponse: Decodable, Sendable, Equatable {
    public var file: String?
    public var keys: [ConfigKey]?

    public init(file: String? = nil, keys: [ConfigKey]? = nil) {
        self.file = file
        self.keys = keys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = c.decodeString(forKey: .file)
        keys = c.decodeArray(ConfigKey.self, forKey: .keys)
    }

    private enum CodingKeys: String, CodingKey {
        case file, keys
    }
}

/// One editable key.
public struct ConfigKey: Decodable, Identifiable, Sendable, Equatable {
    public var id: String { key }

    public var key: String
    /// nil means the default from the file is in force.
    public var value: ConfigValue?
    public var kind: ConfigKind
    public var help: String?
    /// The options an `enum` offers, when the server lists them.
    public var choices: [ConfigValue]?

    public init(
        key: String,
        value: ConfigValue? = nil,
        kind: ConfigKind = .other(""),
        help: String? = nil,
        choices: [ConfigValue]? = nil
    ) {
        self.key = key
        self.value = value
        self.kind = kind
        self.help = help
        self.choices = choices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.decodeString(forKey: .key) ?? ""
        // `value` is deliberately absent-or-null here: `decodeIfPresent` on a lenient single value
        // cannot tell "missing" from "unreadable", so read the raw container instead.
        if c.contains(CodingKeys.value) {
            value = (try? c.decode(ConfigValue.self, forKey: .value)) ?? .null
        } else {
            value = nil
        }
        kind = (try? c.decode(ConfigKind.self, forKey: .kind)) ?? .other("")
        help = c.decodeString(forKey: .help)
        choices = c.decodeArray(ConfigValue.self, forKey: .choices)
        value = Self.coerce(value, kind: kind, choices: choices)
    }

    /// The server says what shape a key has, so a value that arrives in the wrong one is read as
    /// the kind says it should be: `"40"` for a `number` is 40, `"true"` for a `bool` is true.
    private static func coerce(_ value: ConfigValue?, kind: ConfigKind, choices: [ConfigValue]?) -> ConfigValue? {
        guard let value else { return nil }
        switch (kind, value) {
        case (.number, .string(let text)):
            return Double(text).map { .number($0) } ?? value
        case (.number, .bool(let flag)):
            return .number(flag ? 1 : 0)
        case (.boolean, .string(let text)):
            switch text.lowercased() {
            case "true", "1", "yes", "on": return .bool(true)
            case "false", "0", "no", "off": return .bool(false)
            default: return value
            }
        case (.boolean, .number(let number)): return .bool(number != 0)
        case (.names, .number), (.names, .bool): return .string(value.text)
        /// An enum arrives as the option it names, so the picker can select it.
        case (.enum, _):
            return choices?.first { $0.text == value.text } ?? value
        default: return value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case key, value, kind, help, choices
    }

    /// `true`/`false` are still an enum with two options to the screen.
    public var options: [ConfigValue] {
        switch kind {
        case .boolean: return [.bool(true), .bool(false)]
        case .enum: return choices ?? []
        default: return []
        }
    }
}

/// What kind of value the key holds. Unknown kinds stay readable rather than failing the payload.
public enum ConfigKind: Decodable, Encodable, Sendable, Equatable, Hashable {
    case number
    case boolean
    case `enum`
    case names
    case other(String)

    public init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        switch raw {
        case "number": self = .number
        case "bool", "boolean": self = .boolean
        case "enum": self = .enum
        case "names", "list", "string", "text": self = .names
        default: self = .other(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .number: try container.encode("number")
        case .boolean: try container.encode("bool")
        case .enum: try container.encode("enum")
        case .names: try container.encode("names")
        case .other(let raw): try container.encode(raw)
        }
    }

    public var label: String {
        switch self {
        case .number: "number"
        case .boolean: "bool"
        case .enum: "enum"
        case .names: "names"
        case .other(let raw): raw.isEmpty ? "value" : raw
        }
    }
}

/// A config value, in either direction. Lenient: a number that arrives as a string is still a
/// number, and a list of names is still a list.
public enum ConfigValue: Decodable, Encodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case names([String])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let d = try? container.decode(Double.self) { self = .number(d); return }
        if let i = try? container.decode(Int.self) { self = .number(Double(i)); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let nested = try? container.decode([ConfigValue].self) {
            // The server splits a list of names at commas, so send one back the same way.
            self = .names(nested.map(\.text))
            return
        }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let d):
            if d.isFinite && d == d.rounded() && abs(d) < 1e15 { try container.encode(Int(d)) }
            else { try container.encode(d) }
        case .bool(let b): try container.encode(b)
        case .names(let list): try container.encode(list.joined(separator: ", "))
        case .null: try container.encodeNil()
        }
    }

    /// How the value reads in a row.
    public var text: String {
        switch self {
        case .string(let s): s
        case .number(let d): LenientString.string(from: d) ?? "–"
        case .bool(let b): b ? "true" : "false"
        case .names(let list): list.joined(separator: ", ")
        case .null: "default"
        }
    }

    public var doubleValue: Double? { if case .number(let d) = self { d } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
    public var stringValue: String? {
        switch self {
        case .string(let s): s
        case .names(let list): list.joined(separator: ", ")
        default: text
        }
    }
}

/// `POST /config` body.
public struct ConfigRequest: Codable, Sendable, Equatable {
    public var set: [String: ConfigValue]

    public init(set: [String: ConfigValue]) {
        self.set = set
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(set, forKey: .set)
    }

    private enum CodingKeys: String, CodingKey {
        case set
    }
}

/// What `POST /config` answers: the keys it wrote, the backup it made, or why it refused.
public struct ConfigReply: Decodable, Sendable, Equatable {
    public struct ServerError: Decodable, Sendable, Equatable {
        public var type: String?
        public var message: String?

        public init(type: String? = nil, message: String? = nil) {
            self.type = type
            self.message = message
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = c.decodeString(forKey: .type)
            message = c.decodeString(forKey: .message)
        }

        private enum CodingKeys: String, CodingKey {
            case type, message
        }
    }

    public var changed: [String]?
    public var file: String?
    public var error: ServerError?

    public init(changed: [String]? = nil, file: String? = nil, error: ServerError? = nil) {
        self.changed = changed
        self.file = file
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        changed = c.decodeArray(String.self, forKey: .changed)
        file = c.decodeString(forKey: .file)
        error = try? c.decode(ServerError.self, forKey: .error)
    }

    private enum CodingKeys: String, CodingKey {
        case changed, file, error
    }

    public var errorMessage: String? { error?.message }
}

/// A value the server rejected, with the words it used.
public struct StrataServerError: Error, Equatable, Sendable {
    public var message: String
    public var statusCode: Int

    public init(message: String, statusCode: Int) {
        self.message = message
        self.statusCode = statusCode
    }
}
