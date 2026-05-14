import Foundation

/// Percent-encoding helpers for IRI/URI strings per RFC 3986 §2.1.
///
/// RDF parsers need this for two reasons:
/// 1. RDF/XML and JSON-LD allow IRIs that contain characters which must be
///    percent-encoded before they can become valid URI references.
/// 2. The Turtle / TriG grammars admit Unicode escape sequences inside
///    `<...>` IRIs which must round-trip through percent-encoding when the
///    resulting IRI is exported.
///
/// We treat `unreserved` (ALPHA / DIGIT / "-" / "." / "_" / "~") as the
/// always-safe set and percent-encode everything else.
public enum IRIPercentEncoding {

    /// Percent-encode any byte outside the unreserved set.
    public static func encode(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            if isUnreserved(byte) {
                result.unicodeScalars.append(Unicode.Scalar(byte))
            } else {
                result.append("%")
                result.append(hexDigit(byte >> 4))
                result.append(hexDigit(byte & 0x0F))
            }
        }
        return result
    }

    /// Percent-decode the input. Bytes that are not part of a `%HH` sequence
    /// pass through unchanged. Malformed sequences raise.
    public static func decode(_ value: String) throws -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        var iterator = value.utf8.makeIterator()
        var byteOffset = 0
        while let current = iterator.next() {
            if current == UInt8(ascii: "%") {
                guard let high = iterator.next(), let low = iterator.next() else {
                    throw ParserError.invalidEscape(
                        sequence: "%",
                        at: SourcePosition(line: 1, column: byteOffset + 1, byteOffset: byteOffset)
                    )
                }
                guard let highNibble = hexValue(high), let lowNibble = hexValue(low) else {
                    let triplet = "%\(UnicodeScalar(high))\(UnicodeScalar(low))"
                    throw ParserError.invalidEscape(
                        sequence: triplet,
                        at: SourcePosition(line: 1, column: byteOffset + 1, byteOffset: byteOffset)
                    )
                }
                bytes.append((highNibble << 4) | lowNibble)
                byteOffset += 3
            } else {
                bytes.append(current)
                byteOffset += 1
            }
        }
        guard let decoded = String(bytes: bytes, encoding: .utf8) else {
            throw ParserError.invalidIRI(
                value: value,
                at: .start,
                reason: "percent-decoded bytes are not valid UTF-8"
            )
        }
        return decoded
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        if (0x41...0x5A).contains(byte) { return true } // A-Z
        if (0x61...0x7A).contains(byte) { return true } // a-z
        if (0x30...0x39).contains(byte) { return true } // 0-9
        return byte == 0x2D || byte == 0x2E || byte == 0x5F || byte == 0x7E // - . _ ~
    }

    private static func hexDigit(_ nibble: UInt8) -> Character {
        let value = nibble & 0x0F
        if value < 10 {
            return Character(UnicodeScalar(UInt8(ascii: "0") + value))
        }
        return Character(UnicodeScalar(UInt8(ascii: "A") + value - 10))
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
