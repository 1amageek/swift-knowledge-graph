import Foundation

/// Decodes raw UTF-8 JSON bytes into a `JSONValue`.
///
/// We do not use `JSONSerialization` directly. `JSONSerialization` returns
/// `NSNumber` for every numeric value, and `NSNumber` erases the
/// integer-vs-floating distinction that JSON-LD's value-expansion step
/// needs to choose between `xsd:integer` and `xsd:double` for native
/// JSON numbers. A direct UTF-8 walker keeps the distinction.
///
/// The decoder is strict: trailing garbage after the top-level value
/// throws, control characters inside strings throw, escape sequences must
/// be syntactically valid, surrogate pairs must be paired correctly.
enum JSONValueDecoder {

    /// One-shot decode that discards positional metadata. Kept for the
    /// manifest loader and tests that don't care about source positions.
    static func decode(_ bytes: [UInt8]) throws -> JSONValue {
        try decodeWithEndPosition(bytes).value
    }

    /// Decode and also return the byte/line position where parsing
    /// successfully completed. The end position lets downstream algorithms
    /// report "error somewhere in a N-byte document" instead of always
    /// blaming line 1 column 1, until full per-node position tracking is
    /// wired through `JSONValue`.
    static func decodeWithEndPosition(_ bytes: [UInt8]) throws -> (value: JSONValue, end: SourcePosition) {
        var state = State(bytes: bytes, index: 0, line: 1, lineStart: 0)
        state.skipWhitespace()
        let value = try parseValue(&state)
        state.skipWhitespace()
        if state.index < state.bytes.count {
            throw ParserError.jsonSyntax(
                detail: "trailing data after JSON value",
                at: state.position
            )
        }
        return (value, state.position)
    }

    private struct State {
        let bytes: [UInt8]
        var index: Int
        var line: Int
        var lineStart: Int

        var position: SourcePosition {
            SourcePosition(
                line: line,
                column: max(1, index - lineStart + 1),
                byteOffset: index
            )
        }

        mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09:
                    index += 1
                case 0x0A:
                    index += 1
                    line += 1
                    lineStart = index
                case 0x0D:
                    index += 1
                    if index < bytes.count, bytes[index] == 0x0A {
                        index += 1
                    }
                    line += 1
                    lineStart = index
                default:
                    return
                }
            }
        }
    }

    // MARK: - Parsers

    private static func parseValue(_ state: inout State) throws -> JSONValue {
        state.skipWhitespace()
        guard state.index < state.bytes.count else {
            throw ParserError.unexpectedEndOfInput(
                at: state.position,
                expected: "JSON value"
            )
        }
        switch state.bytes[state.index] {
        case UInt8(ascii: "{"):
            return try parseObject(&state)
        case UInt8(ascii: "["):
            return try parseArray(&state)
        case UInt8(ascii: "\""):
            return .string(try parseString(&state))
        case UInt8(ascii: "t"), UInt8(ascii: "f"):
            return try parseBool(&state)
        case UInt8(ascii: "n"):
            return try parseNull(&state)
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return try parseNumber(&state)
        default:
            throw ParserError.jsonSyntax(
                detail: "unexpected byte \(state.bytes[state.index])",
                at: state.position
            )
        }
    }

    private static func parseObject(_ state: inout State) throws -> JSONValue {
        state.index += 1 // consume '{'
        var dict: [String: JSONValue] = [:]
        state.skipWhitespace()
        if state.index < state.bytes.count, state.bytes[state.index] == UInt8(ascii: "}") {
            state.index += 1
            return .object(dict)
        }
        while true {
            state.skipWhitespace()
            guard state.index < state.bytes.count,
                  state.bytes[state.index] == UInt8(ascii: "\"") else {
                throw ParserError.jsonSyntax(
                    detail: "expected '\"' (member key)",
                    at: state.position
                )
            }
            let key = try parseString(&state)
            state.skipWhitespace()
            guard state.index < state.bytes.count,
                  state.bytes[state.index] == UInt8(ascii: ":") else {
                throw ParserError.jsonSyntax(
                    detail: "expected ':' after member key",
                    at: state.position
                )
            }
            state.index += 1
            let value = try parseValue(&state)
            dict[key] = value
            state.skipWhitespace()
            guard state.index < state.bytes.count else {
                throw ParserError.unexpectedEndOfInput(
                    at: state.position,
                    expected: "',' or '}'"
                )
            }
            switch state.bytes[state.index] {
            case UInt8(ascii: ","):
                state.index += 1
                continue
            case UInt8(ascii: "}"):
                state.index += 1
                return .object(dict)
            default:
                throw ParserError.jsonSyntax(
                    detail: "expected ',' or '}' in object",
                    at: state.position
                )
            }
        }
    }

    private static func parseArray(_ state: inout State) throws -> JSONValue {
        state.index += 1
        var values: [JSONValue] = []
        state.skipWhitespace()
        if state.index < state.bytes.count, state.bytes[state.index] == UInt8(ascii: "]") {
            state.index += 1
            return .array(values)
        }
        while true {
            let value = try parseValue(&state)
            values.append(value)
            state.skipWhitespace()
            guard state.index < state.bytes.count else {
                throw ParserError.unexpectedEndOfInput(
                    at: state.position,
                    expected: "',' or ']'"
                )
            }
            switch state.bytes[state.index] {
            case UInt8(ascii: ","):
                state.index += 1
                continue
            case UInt8(ascii: "]"):
                state.index += 1
                return .array(values)
            default:
                throw ParserError.jsonSyntax(
                    detail: "expected ',' or ']' in array",
                    at: state.position
                )
            }
        }
    }

    private static func parseString(_ state: inout State) throws -> String {
        state.index += 1 // consume opening '"'
        var result = ""
        while state.index < state.bytes.count {
            let byte = state.bytes[state.index]
            if byte == UInt8(ascii: "\"") {
                state.index += 1
                return result
            }
            if byte < 0x20 {
                throw ParserError.jsonSyntax(
                    detail: "control character in string",
                    at: state.position
                )
            }
            if byte == UInt8(ascii: "\\") {
                try parseEscape(&state, into: &result)
                continue
            }
            try appendUTF8Scalar(&state, into: &result)
        }
        throw ParserError.unexpectedEndOfInput(
            at: state.position,
            expected: "closing '\"'"
        )
    }

    private static func parseEscape(_ state: inout State, into result: inout String) throws {
        state.index += 1 // consume '\\'
        guard state.index < state.bytes.count else {
            throw ParserError.unexpectedEndOfInput(
                at: state.position,
                expected: "escape character"
            )
        }
        let byte = state.bytes[state.index]
        switch byte {
        case UInt8(ascii: "\""): result.append("\""); state.index += 1
        case UInt8(ascii: "\\"): result.append("\\"); state.index += 1
        case UInt8(ascii: "/"):  result.append("/");  state.index += 1
        case UInt8(ascii: "b"):  result.append("\u{0008}"); state.index += 1
        case UInt8(ascii: "f"):  result.append("\u{000C}"); state.index += 1
        case UInt8(ascii: "n"):  result.append("\n"); state.index += 1
        case UInt8(ascii: "r"):  result.append("\r"); state.index += 1
        case UInt8(ascii: "t"):  result.append("\t"); state.index += 1
        case UInt8(ascii: "u"):
            state.index += 1
            let high = try parseHex4(&state)
            if (0xD800...0xDBFF).contains(high) {
                guard state.index + 1 < state.bytes.count,
                      state.bytes[state.index] == UInt8(ascii: "\\"),
                      state.bytes[state.index + 1] == UInt8(ascii: "u") else {
                    throw ParserError.invalidEscape(
                        sequence: "\\u\(String(high, radix: 16))",
                        at: state.position
                    )
                }
                state.index += 2
                let low = try parseHex4(&state)
                guard (0xDC00...0xDFFF).contains(low) else {
                    throw ParserError.invalidEscape(
                        sequence: "\\u\(String(low, radix: 16))",
                        at: state.position
                    )
                }
                let combined = 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)
                guard let scalar = Unicode.Scalar(combined) else {
                    throw ParserError.invalidEscape(
                        sequence: "\\u" + String(combined, radix: 16),
                        at: state.position
                    )
                }
                result.unicodeScalars.append(scalar)
            } else if (0xDC00...0xDFFF).contains(high) {
                throw ParserError.invalidEscape(
                    sequence: "\\u" + String(high, radix: 16),
                    at: state.position
                )
            } else {
                guard let scalar = Unicode.Scalar(high) else {
                    throw ParserError.invalidEscape(
                        sequence: "\\u" + String(high, radix: 16),
                        at: state.position
                    )
                }
                result.unicodeScalars.append(scalar)
            }
        default:
            throw ParserError.invalidEscape(
                sequence: "\\\(Character(UnicodeScalar(byte)))",
                at: state.position
            )
        }
    }

    private static func parseHex4(_ state: inout State) throws -> Int {
        guard state.index + 4 <= state.bytes.count else {
            throw ParserError.unexpectedEndOfInput(
                at: state.position,
                expected: "4 hex digits"
            )
        }
        var value = 0
        for _ in 0..<4 {
            let byte = state.bytes[state.index]
            let digit: Int
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                digit = Int(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"):
                digit = Int(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"):
                digit = Int(byte - UInt8(ascii: "A")) + 10
            default:
                throw ParserError.invalidEscape(
                    sequence: "\\u…",
                    at: state.position
                )
            }
            value = (value << 4) | digit
            state.index += 1
        }
        return value
    }

    private static func appendUTF8Scalar(_ state: inout State, into result: inout String) throws {
        let byte = state.bytes[state.index]
        if byte < 0x80 {
            result.append(Character(UnicodeScalar(byte)))
            state.index += 1
            return
        }
        let width: Int
        if byte & 0xE0 == 0xC0 { width = 2 }
        else if byte & 0xF0 == 0xE0 { width = 3 }
        else if byte & 0xF8 == 0xF0 { width = 4 }
        else {
            throw ParserError.jsonSyntax(
                detail: "invalid UTF-8 lead byte",
                at: state.position
            )
        }
        guard state.index + width <= state.bytes.count else {
            throw ParserError.unexpectedEndOfInput(
                at: state.position,
                expected: "UTF-8 continuation"
            )
        }
        var scalar: UInt32 = 0
        switch width {
        case 2: scalar = UInt32(byte & 0x1F)
        case 3: scalar = UInt32(byte & 0x0F)
        case 4: scalar = UInt32(byte & 0x07)
        default: break
        }
        for offset in 1..<width {
            let cont = state.bytes[state.index + offset]
            if cont & 0xC0 != 0x80 {
                throw ParserError.jsonSyntax(
                    detail: "invalid UTF-8 continuation",
                    at: state.position
                )
            }
            scalar = (scalar << 6) | UInt32(cont & 0x3F)
        }
        guard let unicode = Unicode.Scalar(scalar) else {
            throw ParserError.jsonSyntax(
                detail: "invalid Unicode scalar",
                at: state.position
            )
        }
        result.unicodeScalars.append(unicode)
        state.index += width
    }

    private static func parseBool(_ state: inout State) throws -> JSONValue {
        if matches(state, "true") {
            state.index += 4
            return .bool(true)
        }
        if matches(state, "false") {
            state.index += 5
            return .bool(false)
        }
        throw ParserError.jsonSyntax(
            detail: "invalid literal",
            at: state.position
        )
    }

    private static func parseNull(_ state: inout State) throws -> JSONValue {
        if matches(state, "null") {
            state.index += 4
            return .null
        }
        throw ParserError.jsonSyntax(
            detail: "invalid literal",
            at: state.position
        )
    }

    private static func matches(_ state: State, _ keyword: String) -> Bool {
        let chars = Array(keyword.utf8)
        guard state.index + chars.count <= state.bytes.count else { return false }
        for i in 0..<chars.count where state.bytes[state.index + i] != chars[i] {
            return false
        }
        return true
    }

    private static func parseNumber(_ state: inout State) throws -> JSONValue {
        let start = state.index
        var isFloating = false
        if state.bytes[state.index] == UInt8(ascii: "-") {
            state.index += 1
        }
        guard state.index < state.bytes.count else {
            throw ParserError.unexpectedEndOfInput(at: state.position, expected: "digit")
        }
        if state.bytes[state.index] == UInt8(ascii: "0") {
            state.index += 1
        } else if (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(state.bytes[state.index]) {
            while state.index < state.bytes.count,
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(state.bytes[state.index]) {
                state.index += 1
            }
        } else {
            throw ParserError.jsonSyntax(detail: "invalid number", at: state.position)
        }
        if state.index < state.bytes.count, state.bytes[state.index] == UInt8(ascii: ".") {
            isFloating = true
            state.index += 1
            var hasDigit = false
            while state.index < state.bytes.count,
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(state.bytes[state.index]) {
                state.index += 1
                hasDigit = true
            }
            if !hasDigit {
                throw ParserError.jsonSyntax(detail: "invalid number", at: state.position)
            }
        }
        if state.index < state.bytes.count,
           state.bytes[state.index] == UInt8(ascii: "e") || state.bytes[state.index] == UInt8(ascii: "E") {
            isFloating = true
            state.index += 1
            if state.index < state.bytes.count,
               state.bytes[state.index] == UInt8(ascii: "+") || state.bytes[state.index] == UInt8(ascii: "-") {
                state.index += 1
            }
            var hasDigit = false
            while state.index < state.bytes.count,
                  (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(state.bytes[state.index]) {
                state.index += 1
                hasDigit = true
            }
            if !hasDigit {
                throw ParserError.jsonSyntax(detail: "invalid exponent", at: state.position)
            }
        }
        let lexeme = String(decoding: state.bytes[start..<state.index], as: UTF8.self)
        if isFloating {
            guard let d = Double(lexeme) else {
                throw ParserError.jsonSyntax(detail: "invalid number", at: state.position)
            }
            return .double(d)
        }
        if let i = Int64(lexeme) {
            return .int(i)
        }
        // Out-of-range integer falls back to double.
        guard let d = Double(lexeme) else {
            throw ParserError.jsonSyntax(detail: "invalid number", at: state.position)
        }
        return .double(d)
    }
}
