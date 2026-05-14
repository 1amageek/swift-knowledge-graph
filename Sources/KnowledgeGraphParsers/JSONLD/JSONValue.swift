import Foundation

/// Algebraic data type for a parsed JSON value.
///
/// Foundation's `JSONSerialization` produces `[String: Any]` / `[Any]` /
/// `NSNumber`, which forces every consumer to `as?`-cast at every level and
/// loses the integer-vs-floating distinction we need to preserve for
/// `xsd:integer` / `xsd:double` literals. `JSONValue` captures the shape
/// exactly once, with a typed integer case for whole numbers and a typed
/// double case for anything with a fractional part or exponent. The JSON-LD
/// algorithms then pattern-match against this enum without any casting.
indirect enum JSONValue: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var asArray: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    var asObject: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
}
