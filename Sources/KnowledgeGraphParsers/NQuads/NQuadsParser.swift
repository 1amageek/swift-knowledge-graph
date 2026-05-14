import Foundation
import KnowledgeGraph

/// Minimal N-Quads parser used to load expected result graphs in the W3C
/// TriG test suite.
///
/// N-Quads (RFC 7064 / W3C Recommendation) is a strict line-based syntax:
/// every line is `subject predicate object [graph] .` terminated by `.\n`.
/// IRIs are always `<...>`, blanks are always `_:label`, and literals use
/// double-quoted strings with optional `@lang` or `^^<iri>` suffixes — no
/// prefixes, no PNAME, no triple-quoted strings, no list / collection
/// abbreviations.
///
/// This parser is intentionally non-streaming: the test driver reads the
/// whole file into memory before calling `parse`. The shape mirrors
/// `TurtleParser` for callsite convenience but the implementation walks the
/// byte buffer directly rather than going through a token layer — N-Quads
/// is regular enough that doing so is simpler than threading a tokenizer.
public struct NQuadsParser {

    public var context: ParsingContext

    public init(context: ParsingContext = ParsingContext()) {
        self.context = context
    }

    public mutating func parse(_ text: String) throws -> KnowledgeGraph {
        var builder = KnowledgeGraphBuilder()
        try parseAll(text, into: &builder)
        return builder.build()
    }

    public mutating func parseAll(_ text: String, into builder: inout KnowledgeGraphBuilder) throws {
        let bytes = Array(text.utf8)
        var index = 0
        var line = 1
        var lineStart = 0
        while index < bytes.count {
            try skipWhitespaceAndComments(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
            if index >= bytes.count { break }
            try parseQuad(
                bytes: bytes,
                index: &index,
                line: &line,
                lineStart: &lineStart,
                into: &builder
            )
        }
    }

    // MARK: - Term parsers

    private mutating func parseQuad(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        let subject = try parseTerm(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        try skipWhitespaceAndComments(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        let predicate = try parseTerm(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        try skipWhitespaceAndComments(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        let object = try parseTerm(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        try skipWhitespaceAndComments(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)

        var graphID: String?
        if index < bytes.count, bytes[index] != UInt8(ascii: ".") {
            let graphTerm = try parseTerm(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
            graphID = graphTerm.key
            try skipWhitespaceAndComments(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        }

        guard index < bytes.count, bytes[index] == UInt8(ascii: ".") else {
            throw ParserError.grammar(
                production: "nquad",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "expected '.' terminator"
            )
        }
        index += 1

        guard case .iri = predicate.kind else {
            throw ParserError.grammar(
                production: "predicate",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "predicate must be an IRI"
            )
        }

        if let graphID {
            try builder.insertNamedGraph(NamedGraph(id: graphID))
        }
        try builder.insertTriple(
            subject: subject,
            predicate: predicate.key,
            object: object,
            namedGraph: graphID
        )
    }

    private mutating func parseTerm(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int
    ) throws -> NodeIdentifier {
        guard index < bytes.count else {
            throw ParserError.unexpectedEndOfInput(
                at: position(line: line, index: index, lineStart: lineStart),
                expected: "term"
            )
        }
        switch bytes[index] {
        case UInt8(ascii: "<"):
            return try parseIRI(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        case UInt8(ascii: "_"):
            return try parseBlankNode(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        case UInt8(ascii: "\""):
            return try parseLiteral(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
        default:
            throw ParserError.grammar(
                production: "term",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "unexpected byte \(bytes[index])"
            )
        }
    }

    private mutating func parseIRI(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int
    ) throws -> NodeIdentifier {
        index += 1 // consume '<'
        var value = ""
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: ">") {
                index += 1
                return NodeIdentifier.iri(value)
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                let pos = position(line: line, index: index, lineStart: lineStart)
                try TurtleEscapes.decodeStringEscape(
                    bytes: bytes,
                    index: &index,
                    position: pos,
                    into: &value
                )
                continue
            }
            try appendUTF8Scalar(
                bytes: bytes,
                index: &index,
                line: &line,
                lineStart: &lineStart,
                into: &value
            )
        }
        throw ParserError.unexpectedEndOfInput(
            at: position(line: line, index: index, lineStart: lineStart),
            expected: "closing '>' in IRI"
        )
    }

    private mutating func parseBlankNode(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int
    ) throws -> NodeIdentifier {
        index += 1 // '_'
        guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else {
            throw ParserError.grammar(
                production: "blankNode",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "expected ':' after '_'"
            )
        }
        index += 1
        var label = ""
        while index < bytes.count {
            let byte = bytes[index]
            if isBlankLabelByte(byte) {
                label.append(Character(UnicodeScalar(byte)))
                index += 1
            } else {
                break
            }
        }
        if label.isEmpty {
            throw ParserError.grammar(
                production: "blankNode",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "empty blank node label"
            )
        }
        return context.blankNode(forLabel: label)
    }

    private mutating func parseLiteral(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int
    ) throws -> NodeIdentifier {
        index += 1 // consume opening '"'
        var value = ""
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\"") {
                index += 1
                break
            }
            if byte == UInt8(ascii: "\\") {
                index += 1
                let pos = position(line: line, index: index, lineStart: lineStart)
                try TurtleEscapes.decodeStringEscape(
                    bytes: bytes,
                    index: &index,
                    position: pos,
                    into: &value
                )
                continue
            }
            try appendUTF8Scalar(
                bytes: bytes,
                index: &index,
                line: &line,
                lineStart: &lineStart,
                into: &value
            )
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "@") {
            index += 1
            var tag = ""
            while index < bytes.count, isLangTagByte(bytes[index]) {
                tag.append(Character(UnicodeScalar(bytes[index])))
                index += 1
            }
            if tag.isEmpty {
                throw ParserError.grammar(
                    production: "langTag",
                    at: position(line: line, index: index, lineStart: lineStart),
                    detail: "empty language tag"
                )
            }
            return TurtleLiterals.langTagged(value, language: tag)
        }
        if index + 1 < bytes.count,
           bytes[index] == UInt8(ascii: "^"),
           bytes[index + 1] == UInt8(ascii: "^") {
            index += 2
            guard index < bytes.count, bytes[index] == UInt8(ascii: "<") else {
                throw ParserError.grammar(
                    production: "datatype",
                    at: position(line: line, index: index, lineStart: lineStart),
                    detail: "expected '<' after '^^'"
                )
            }
            let iri = try parseIRI(bytes: bytes, index: &index, line: &line, lineStart: &lineStart)
            return TurtleLiterals.typed(value, datatype: iri.key)
        }
        return TurtleLiterals.plainString(value)
    }

    // MARK: - UTF-8 / whitespace helpers

    private mutating func appendUTF8Scalar(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int,
        into result: inout String
    ) throws {
        let byte = bytes[index]
        if byte < 0x80 {
            result.append(Character(UnicodeScalar(byte)))
            index += 1
            return
        }
        let width: Int
        if byte & 0xE0 == 0xC0 { width = 2 }
        else if byte & 0xF0 == 0xE0 { width = 3 }
        else if byte & 0xF8 == 0xF0 { width = 4 }
        else {
            throw ParserError.grammar(
                production: "utf8",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "invalid UTF-8 lead byte"
            )
        }
        guard index + width <= bytes.count else {
            throw ParserError.unexpectedEndOfInput(
                at: position(line: line, index: index, lineStart: lineStart),
                expected: "UTF-8 continuation bytes"
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
            let cont = bytes[index + offset]
            if cont & 0xC0 != 0x80 {
                throw ParserError.grammar(
                    production: "utf8",
                    at: position(line: line, index: index, lineStart: lineStart),
                    detail: "invalid UTF-8 continuation byte"
                )
            }
            scalar = (scalar << 6) | UInt32(cont & 0x3F)
        }
        guard let unicode = Unicode.Scalar(scalar) else {
            throw ParserError.grammar(
                production: "utf8",
                at: position(line: line, index: index, lineStart: lineStart),
                detail: "invalid Unicode scalar"
            )
        }
        result.unicodeScalars.append(unicode)
        index += width
    }

    private func skipWhitespaceAndComments(
        bytes: [UInt8],
        index: inout Int,
        line: inout Int,
        lineStart: inout Int
    ) throws {
        while index < bytes.count {
            let byte = bytes[index]
            switch byte {
            case 0x20, 0x09:
                index += 1
            case 0x0A:
                line += 1
                index += 1
                lineStart = index
            case 0x0D:
                index += 1
                if index < bytes.count, bytes[index] == 0x0A {
                    index += 1
                }
                line += 1
                lineStart = index
            case UInt8(ascii: "#"):
                while index < bytes.count, bytes[index] != 0x0A, bytes[index] != 0x0D {
                    index += 1
                }
            default:
                return
            }
        }
    }

    private func position(line: Int, index: Int, lineStart: Int) -> SourcePosition {
        SourcePosition(line: line, column: max(1, index - lineStart + 1), byteOffset: index)
    }

    private func isBlankLabelByte(_ byte: UInt8) -> Bool {
        if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return true }
        if byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") { return true }
        if byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z") { return true }
        if byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".") {
            return true
        }
        if byte >= 0x80 { return true } // accept UTF-8 continuation / multi-byte
        return false
    }

    private func isLangTagByte(_ byte: UInt8) -> Bool {
        if byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z") { return true }
        if byte >= UInt8(ascii: "a") && byte <= UInt8(ascii: "z") { return true }
        if byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9") { return true }
        if byte == UInt8(ascii: "-") { return true }
        return false
    }
}
