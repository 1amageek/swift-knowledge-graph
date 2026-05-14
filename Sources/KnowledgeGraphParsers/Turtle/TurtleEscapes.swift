import Foundation

/// Escape-sequence decoding for the Turtle / TriG / N-Triples / N-Quads
/// family of grammars.
///
/// Two distinct escape vocabularies share this file because they live in
/// the same grammar:
///
/// 1. **String escapes** — what may appear inside a `"..."` / `'''...'''`
///    literal: `\t`, `\b`, `\n`, `\r`, `\f`, `\"`, `\'`, `\\`, plus the
///    Unicode escapes `\uXXXX` and `\UXXXXXXXX`.
/// 2. **Local-name escapes (PN_LOCAL_ESC)** — what may appear inside the
///    *local* component of a `prefix:local` form: a single backslash
///    followed by one of the punctuation characters listed in the
///    Turtle 1.1 production.
///
/// Each decoder reads from a UTF-8 byte buffer starting just after the
/// `\` that triggered it, mutating an index in place. They throw
/// `ParserError.invalidEscape` with the exact byte offset on malformed
/// input — no silent fallback.
enum TurtleEscapes {

    /// Decode a string escape sequence. The caller has already consumed
    /// the leading `\`; this routine reads the next 1–8 bytes depending on
    /// the escape kind, advances `index`, and appends the resulting Unicode
    /// scalars to `result`.
    static func decodeStringEscape(
        bytes: [UInt8],
        index: inout Int,
        position: SourcePosition,
        into result: inout String
    ) throws {
        guard index < bytes.count else {
            throw ParserError.invalidEscape(sequence: "\\", at: position)
        }
        let next = bytes[index]
        switch next {
        case UInt8(ascii: "t"):
            result.append("\t")
            index += 1
        case UInt8(ascii: "b"):
            result.unicodeScalars.append(Unicode.Scalar(0x08))
            index += 1
        case UInt8(ascii: "n"):
            result.append("\n")
            index += 1
        case UInt8(ascii: "r"):
            result.append("\r")
            index += 1
        case UInt8(ascii: "f"):
            result.unicodeScalars.append(Unicode.Scalar(0x0C))
            index += 1
        case UInt8(ascii: "\""):
            result.append("\"")
            index += 1
        case UInt8(ascii: "'"):
            result.append("'")
            index += 1
        case UInt8(ascii: "\\"):
            result.append("\\")
            index += 1
        case UInt8(ascii: "u"):
            index += 1
            let scalar = try readHexScalar(bytes: bytes, index: &index, width: 4, position: position)
            result.unicodeScalars.append(scalar)
        case UInt8(ascii: "U"):
            index += 1
            let scalar = try readHexScalar(bytes: bytes, index: &index, width: 8, position: position)
            result.unicodeScalars.append(scalar)
        default:
            let sequence = "\\\(Character(UnicodeScalar(next)))"
            throw ParserError.invalidEscape(sequence: sequence, at: position)
        }
    }

    /// Decode a `PN_LOCAL_ESC` sequence. The caller has already consumed
    /// the leading `\`; the next byte must be one of the 20 punctuation
    /// characters enumerated by the production.
    static func decodeLocalEscape(
        bytes: [UInt8],
        index: inout Int,
        position: SourcePosition,
        into result: inout String
    ) throws {
        guard index < bytes.count else {
            throw ParserError.invalidEscape(sequence: "\\", at: position)
        }
        let next = bytes[index]
        if isLocalEscapeCharacter(next) {
            result.unicodeScalars.append(Unicode.Scalar(next))
            index += 1
            return
        }
        let sequence = "\\\(Character(UnicodeScalar(next)))"
        throw ParserError.invalidEscape(sequence: sequence, at: position)
    }

    /// True if `byte` may follow a `\` inside `PN_LOCAL`.
    static func isLocalEscapeCharacter(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "."),
             UInt8(ascii: "-"), UInt8(ascii: "!"), UInt8(ascii: "$"),
             UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "("),
             UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"),
             UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "="),
             UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#"),
             UInt8(ascii: "@"), UInt8(ascii: "%"):
            return true
        default:
            return false
        }
    }

    // MARK: - Internals

    private static func readHexScalar(
        bytes: [UInt8],
        index: inout Int,
        width: Int,
        position: SourcePosition
    ) throws -> Unicode.Scalar {
        guard index + width <= bytes.count else {
            let consumed = bytes[(index - 1)..<min(bytes.count, index - 1 + width + 1)]
            let text = String(decoding: consumed, as: UTF8.self)
            throw ParserError.invalidEscape(sequence: text, at: position)
        }
        var value: UInt32 = 0
        for offset in 0..<width {
            let byte = bytes[index + offset]
            guard let nibble = hexValue(byte) else {
                let lead = (width == 4) ? "u" : "U"
                let slice = bytes[(index - 1)..<(index + offset + 1)]
                let text = "\\\(lead)\(String(decoding: slice, as: UTF8.self))"
                throw ParserError.invalidEscape(sequence: text, at: position)
            }
            value = (value << 4) | UInt32(nibble)
        }
        index += width
        guard let scalar = Unicode.Scalar(value) else {
            let lead = (width == 4) ? "u" : "U"
            throw ParserError.invalidEscape(
                sequence: "\\\(lead)\(String(value, radix: 16, uppercase: true))",
                at: position
            )
        }
        return scalar
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }
}
