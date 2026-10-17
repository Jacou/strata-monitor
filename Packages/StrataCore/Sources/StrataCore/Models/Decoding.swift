import Foundation

// Lenient decoding helpers.
//
// The server's JSON is not stable across versions: fields go missing, `live.*` is null when idle,
// a number arrives as an int or a float, and a few fields that look numeric arrive as strings.
// Every helper below returns nil instead of throwing, so a partial payload still decodes and renders.

extension KeyedDecodingContainer {
    /// Double from a JSON number, an integer, or a numeric string.
    func decodeDouble(forKey key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return Double(i) }
        if let s = try? decodeIfPresent(String.self, forKey: key), let d = Double(s) { return d }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? 1 : 0 }
        return nil
    }

    /// Int from a JSON integer, a float (truncated), or a numeric string.
    func decodeInt(forKey key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key), let d = Double(s) { return Int(d) }
        return nil
    }

    /// Bool from a JSON bool, 0/1, or "true"/"false"/"on"/"off"/"yes"/"no".
    func decodeBool(forKey key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d != 0 }
        guard let s = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        switch s.lowercased() {
        case "true", "1", "yes", "on": return true
        case "false", "0", "no", "off": return false
        default: return nil
        }
    }

    /// String from a JSON string, or from a number/bool rendered as text.
    func decodeString(forKey key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let d = LenientString.string(from: decodeDouble(forKey: key)) { return d }
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b ? "true" : "false" }
        return nil
    }

    /// A series of numbers. Nulls and unreadable entries become 0, like the web app's `spark()`.
    func decodeDoubleArray(forKey key: Key) -> [Double]? {
        guard var container = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var result: [Double] = []
        while !container.isAtEnd {
            guard let sub = try? container.superDecoder() else { break }
            guard let single = try? sub.singleValueContainer() else { break }
            if let d = try? single.decode(Double.self) { result.append(d) }
            else if let i = try? single.decode(Int.self) { result.append(Double(i)) }
            else if let s = try? single.decode(String.self), let d = Double(s) { result.append(d) }
            else if let b = try? single.decode(Bool.self) { result.append(b ? 1 : 0) }
            else { result.append(0) }
        }
        return result
    }

    /// An array of structs where a junk element is dropped rather than failing the whole payload.
    func decodeArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard var container = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var result: [T] = []
        while !container.isAtEnd {
            guard let sub = try? container.superDecoder() else { break }
            if let value = try? type.init(from: sub) { result.append(value) }
        }
        return result
    }
}

/// A field that may arrive as a string or as a number (`cvec`, `pcie_frac`, `spec_min_p`).
public struct LenientString: Codable, Equatable, Sendable, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) { self.raw = raw }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { raw = s; return }
        if let b = try? container.decode(Bool.self) { raw = b ? "true" : "false"; return }
        if let d = try? container.decode(Double.self), let s = LenientString.string(from: d) { raw = s; return }
        raw = ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    public var description: String { raw }

    /// The value as a number when it reads as one.
    public var doubleValue: Double? { Double(raw) }

    /// Empty, "0" or "off": the web app treats those as "not set".
    public var isBlank: Bool { raw.isEmpty || raw == "0" || raw.lowercased() == "off" }

    /// Integers print without a trailing ".0", so "0.18" stays "0.18" and 262144 stays "262144".
    static func string(from value: Double?) -> String? {
        guard let value else { return nil }
        if value.isFinite && value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }
}
