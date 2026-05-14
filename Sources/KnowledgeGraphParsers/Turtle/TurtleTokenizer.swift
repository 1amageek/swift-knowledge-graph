import Foundation

/// Incremental Turtle / TriG tokenizer.
///
/// The tokenizer owns a UTF-8 byte buffer and a cursor. The grammar layer
/// drives it through `nextToken`, which returns the next complete token or
/// `nil` when more bytes are needed (and `atEOF` is `false`). Once
/// `markEndOfInput` has been called, `nextToken` will either return a final
/// token or throw on a truncated production.
///
/// The tokenizer never emits a token whose lexical form is still ambiguous.
/// For example, `123` is held back until the next byte arrives because it
/// could still extend into `123.45` or `123e10`. This is what makes the
/// tokenizer safe to drive from a chunked input source — every emitted
/// token is final.
struct TurtleTokenizer {

    // MARK: - State

    private var bytes: [UInt8]
    private var cursor: Int
    private var line: Int
    private var column: Int
    private var atEOF: Bool

    /// Set to `true` after a `stringLiteral` token is emitted. Allows the
    /// next call to recognise a `@langtag` (which is otherwise ambiguous
    /// with `@prefix` / `@base`).
    private var lastWasStringLiteral: Bool

    init() {
        self.bytes = []
        self.cursor = 0
        self.line = 1
        self.column = 1
        self.atEOF = false
        self.lastWasStringLiteral = false
    }

    /// Append a chunk of UTF-8 bytes to the internal buffer. The tokenizer
    /// will surface them on subsequent `nextToken` calls.
    mutating func append(_ chunk: ArraySlice<UInt8>) {
        bytes.append(contentsOf: chunk)
        compact()
    }

    /// Signal that no more input bytes will arrive. Tokens that were being
    /// held back pending a disambiguating lookahead can now be emitted; any
    /// open string / triple-quoted string / `<` IRI / etc. will become a
    /// terminal error.
    mutating func markEndOfInput() {
        atEOF = true
    }

    /// True when the tokenizer has both seen end-of-input *and* consumed
    /// every byte in its buffer.
    var isExhausted: Bool {
        atEOF && cursor >= bytes.count
    }

    /// Current source position — used by the grammar layer when it raises
    /// errors that are about token *absence* rather than a specific token.
    var currentPosition: SourcePosition {
        SourcePosition(line: line, column: column, byteOffset: cursor)
    }

    // MARK: - Tokenization entry point

    /// Pull the next token, or `nil` if more input is required.
    mutating func nextToken() throws -> Token? {
        try skipInsignificant()
        if cursor >= bytes.count {
            return nil
        }
        // If `skipInsignificant` rewound to a `#` because the comment ran
        // off the end of the buffer without a newline, we need more bytes
        // before we can decide what to do with this position. Returning
        // `nil` makes the caller feed another chunk.
        if bytes[cursor] == UInt8(ascii: "#"), !atEOF {
            return nil
        }
        let start = savedState()
        let byte = bytes[cursor]

        switch byte {
        case UInt8(ascii: "<"):
            return try readIRIRef(start: start)
        case UInt8(ascii: "\""):
            return try readDoubleQuoted(start: start)
        case UInt8(ascii: "'"):
            return try readSingleQuoted(start: start)
        case UInt8(ascii: "_"):
            return try readBlankNodeLabel(start: start)
        case UInt8(ascii: "@"):
            return try readAtForm(start: start)
        case UInt8(ascii: "["):
            return try readOpenBracketOrAnon(start: start)
        case UInt8(ascii: "]"):
            advance()
            return Token(kind: .closeBracket, position: position(of: start))
        case UInt8(ascii: "("):
            advance()
            return Token(kind: .openParen, position: position(of: start))
        case UInt8(ascii: ")"):
            advance()
            return Token(kind: .closeParen, position: position(of: start))
        case UInt8(ascii: "{"):
            advance()
            return Token(kind: .openBrace, position: position(of: start))
        case UInt8(ascii: "}"):
            advance()
            return Token(kind: .closeBrace, position: position(of: start))
        case UInt8(ascii: ","):
            advance()
            return Token(kind: .comma, position: position(of: start))
        case UInt8(ascii: ";"):
            advance()
            return Token(kind: .semicolon, position: position(of: start))
        case UInt8(ascii: "^"):
            return try readDoubleCaret(start: start)
        case UInt8(ascii: "."):
            return try readDotOrNumeric(start: start)
        case UInt8(ascii: "+"), UInt8(ascii: "-"):
            return try readSignedNumeric(start: start)
        case 0x30...0x39:
            return try readNumeric(start: start)
        case UInt8(ascii: ":"):
            return try readEmptyPrefixName(start: start)
        default:
            return try readIdentifierLike(start: start)
        }
    }

    /// Read a prefixed name with an empty prefix: `:` followed by PN_LOCAL.
    private mutating func readEmptyPrefixName(start: SavedState) throws -> Token? {
        advance() // consume ':'
        let local = try readPNLocal(start: start)
        if local == nil { return nil }
        lastWasStringLiteral = false
        return Token(kind: .prefixedName(prefix: "", local: local!), position: position(of: start))
    }

    // MARK: - Whitespace + comments

    /// Skip whitespace and `#`-comments. Comment consumption is atomic:
    /// if the buffer ends mid-comment with no newline AND end-of-input has
    /// not been signalled, the cursor is rewound to the `#` so that the
    /// comment is reconsumed once more bytes arrive.
    private mutating func skipInsignificant() throws {
        while cursor < bytes.count {
            let byte = bytes[cursor]
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:
                advance()
            case UInt8(ascii: "#"):
                let commentStart = savedState()
                advance() // '#'
                var foundTerminator = false
                while cursor < bytes.count {
                    let inner = bytes[cursor]
                    if inner == 0x0A || inner == 0x0D {
                        foundTerminator = true
                        break
                    }
                    advance()
                }
                if !foundTerminator, !atEOF {
                    restore(commentStart)
                    return
                }
            default:
                return
            }
        }
    }

    // MARK: - <...> IRI reference

    private mutating func readIRIRef(start: SavedState) throws -> Token? {
        advance() // consume '<'
        var value = ""
        while cursor < bytes.count {
            let byte = bytes[cursor]
            switch byte {
            case UInt8(ascii: ">"):
                advance()
                return Token(kind: .iriRef(value), position: position(of: start))
            case UInt8(ascii: "\\"):
                let escapePos = currentPosition
                advance()
                if cursor >= bytes.count {
                    if atEOF {
                        throw ParserError.unexpectedEndOfInput(at: escapePos, expected: "escape sequence")
                    }
                    restore(start)
                    return nil
                }
                let kind = bytes[cursor]
                guard kind == UInt8(ascii: "u") || kind == UInt8(ascii: "U") else {
                    throw ParserError.invalidEscape(
                        sequence: "\\\(Character(UnicodeScalar(kind)))",
                        at: escapePos
                    )
                }
                let width = (kind == UInt8(ascii: "u")) ? 4 : 8
                if cursor + 1 + width > bytes.count {
                    if atEOF {
                        throw ParserError.unexpectedEndOfInput(at: escapePos, expected: "\(width) hex digits")
                    }
                    restore(start)
                    return nil
                }
                advance() // consume 'u' / 'U'
                var arr: [UInt8] = []
                arr.append(UInt8(ascii: "\\"))
                arr.append(kind)
                arr.append(contentsOf: bytes[cursor..<(cursor + width)])
                var local = 1
                let beforeCount = value.unicodeScalars.count
                try TurtleEscapes.decodeStringEscape(
                    bytes: arr,
                    index: &local,
                    position: escapePos,
                    into: &value
                )
                if value.unicodeScalars.count > beforeCount {
                    let decoded = value.unicodeScalars[
                        value.unicodeScalars.index(value.unicodeScalars.startIndex, offsetBy: beforeCount)
                    ]
                    if Self.isIRIRefDisallowedScalar(decoded) {
                        throw ParserError.invalidIRI(
                            value: value,
                            at: escapePos,
                            reason: "decoded escape U+\(String(decoded.value, radix: 16, uppercase: true)) is not allowed in an IRIREF"
                        )
                    }
                }
                for _ in 0..<width {
                    advance()
                }
            case UInt8(ascii: " "), 0x09, 0x0A, 0x0D, UInt8(ascii: "\""),
                 UInt8(ascii: "{"), UInt8(ascii: "}"), UInt8(ascii: "|"),
                 UInt8(ascii: "^"), UInt8(ascii: "`"):
                throw ParserError.unexpectedCharacter(
                    Character(UnicodeScalar(byte)),
                    at: currentPosition,
                    expected: "IRIREF body character"
                )
            default:
                let length = utf8SequenceLength(at: cursor)
                if length == 0 {
                    throw ParserError.unexpectedCharacter(
                        "?",
                        at: currentPosition,
                        expected: "valid UTF-8 byte"
                    )
                }
                if cursor + length > bytes.count {
                    if atEOF {
                        throw ParserError.unexpectedEndOfInput(at: currentPosition, expected: "UTF-8 continuation byte")
                    }
                    restore(start)
                    return nil
                }
                value.append(contentsOf: String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self))
                for _ in 0..<length {
                    advance()
                }
            }
        }
        if atEOF {
            throw ParserError.unexpectedEndOfInput(at: position(of: start), expected: "'>'")
        }
        restore(start)
        return nil
    }

    // MARK: - String literals

    private mutating func readDoubleQuoted(start: SavedState) throws -> Token? {
        return try readQuoted(start: start, quote: UInt8(ascii: "\""))
    }

    private mutating func readSingleQuoted(start: SavedState) throws -> Token? {
        return try readQuoted(start: start, quote: UInt8(ascii: "'"))
    }

    private mutating func readQuoted(start: SavedState, quote: UInt8) throws -> Token? {
        // To distinguish `""` (empty single-line) from `"""..."""` (triple
        // quoted) we need bytes at offsets 1 *and* 2. Under streaming the
        // buffer may end after the first or second quote — return nil and
        // wait for more input, otherwise we would emit a spurious empty
        // string and discard a later third quote.
        let one = peek(offset: 1)
        let two = peek(offset: 2)
        if one == quote {
            if let two {
                if two == quote {
                    return try readTripleQuoted(start: start, quote: quote)
                }
                return try readSingleLineQuoted(start: start, quote: quote)
            }
            if atEOF {
                return try readSingleLineQuoted(start: start, quote: quote)
            }
            restore(start)
            return nil
        }
        return try readSingleLineQuoted(start: start, quote: quote)
    }

    private mutating func readSingleLineQuoted(start: SavedState, quote: UInt8) throws -> Token? {
        advance() // opening quote
        var value = ""
        while cursor < bytes.count {
            let byte = bytes[cursor]
            switch byte {
            case quote:
                advance()
                lastWasStringLiteral = true
                return Token(kind: .stringLiteral(value), position: position(of: start))
            case 0x0A, 0x0D:
                throw ParserError.unterminatedLiteral(at: position(of: start))
            case UInt8(ascii: "\\"):
                if !(try readStringEscape(into: &value, start: start)) {
                    return nil
                }
            default:
                if !(try appendCodepoint(into: &value, start: start)) {
                    return nil
                }
            }
        }
        if atEOF {
            throw ParserError.unterminatedLiteral(at: position(of: start))
        }
        restore(start)
        return nil
    }

    private mutating func readTripleQuoted(start: SavedState, quote: UInt8) throws -> Token? {
        advance(); advance(); advance() // opening triple
        var value = ""
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == quote {
                if peek(offset: 1) == quote, peek(offset: 2) == quote {
                    advance(); advance(); advance()
                    lastWasStringLiteral = true
                    return Token(kind: .stringLiteral(value), position: position(of: start))
                }
                // Could be 1 or 2 quotes inside the literal — but we need
                // to know whether a third quote follows. If we are not at
                // EOF and only 1 byte remains, back off and wait for more.
                if cursor + 3 > bytes.count, !atEOF {
                    restore(start)
                    return nil
                }
                value.unicodeScalars.append(Unicode.Scalar(quote))
                advance()
            } else if byte == UInt8(ascii: "\\") {
                if !(try readStringEscape(into: &value, start: start)) {
                    return nil
                }
            } else {
                if !(try appendCodepoint(into: &value, start: start)) {
                    return nil
                }
            }
        }
        if atEOF {
            throw ParserError.unterminatedLiteral(at: position(of: start))
        }
        restore(start)
        return nil
    }

    /// Consume `\<x>` from the buffer and append the decoded scalar(s) into
    /// `value`. Returns `false` only when more input is required.
    private mutating func readStringEscape(into value: inout String, start: SavedState) throws -> Bool {
        let escapePos = currentPosition
        advance() // consume '\\'
        if cursor >= bytes.count {
            if atEOF {
                throw ParserError.invalidEscape(sequence: "\\", at: escapePos)
            }
            restore(start)
            return false
        }
        let kind = bytes[cursor]
        let required: Int
        switch kind {
        case UInt8(ascii: "u"): required = 4
        case UInt8(ascii: "U"): required = 8
        default: required = 0
        }
        if required > 0 {
            if cursor + 1 + required > bytes.count {
                if atEOF {
                    throw ParserError.unexpectedEndOfInput(at: escapePos, expected: "\(required) hex digits")
                }
                restore(start)
                return false
            }
            var packed: [UInt8] = []
            packed.append(UInt8(ascii: "\\"))
            packed.append(kind)
            for offset in 0..<required {
                packed.append(bytes[cursor + 1 + offset])
            }
            var local = 1
            try TurtleEscapes.decodeStringEscape(
                bytes: packed,
                index: &local,
                position: escapePos,
                into: &value
            )
            // packed cursor advanced past the escape; sync our own cursor.
            for _ in 0..<(1 + required) {
                advance()
            }
            return true
        }
        // Non-unicode escape consumes exactly 1 byte.
        let packed: [UInt8] = [UInt8(ascii: "\\"), kind]
        var local = 1
        try TurtleEscapes.decodeStringEscape(
            bytes: packed,
            index: &local,
            position: escapePos,
            into: &value
        )
        advance()
        return true
    }

    private mutating func appendCodepoint(into value: inout String, start: SavedState) throws -> Bool {
        let length = utf8SequenceLength(at: cursor)
        if length == 0 {
            throw ParserError.unexpectedCharacter(
                "?",
                at: currentPosition,
                expected: "valid UTF-8 byte"
            )
        }
        if cursor + length > bytes.count {
            if atEOF {
                throw ParserError.unexpectedEndOfInput(at: currentPosition, expected: "UTF-8 continuation byte")
            }
            restore(start)
            return false
        }
        value.append(contentsOf: String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self))
        for _ in 0..<length {
            advance()
        }
        return true
    }

    // MARK: - Blank node label, anon, brackets

    private mutating func readBlankNodeLabel(start: SavedState) throws -> Token? {
        // `_` followed by `:` followed by PN_CHARS_U / digit, then body.
        guard let next = peek(offset: 1) else {
            if atEOF {
                // `_` at end of input without `:` — fall back to identifier.
                return try readIdentifierLike(start: start)
            }
            // Need at least one more byte to know whether this is a blank
            // node label. Rewind so the byte is reconsidered on next call.
            restore(start)
            return nil
        }
        guard next == UInt8(ascii: ":") else {
            return try readIdentifierLike(start: start)
        }
        advance() // _
        advance() // :
        guard cursor < bytes.count else {
            if atEOF {
                throw ParserError.unexpectedEndOfInput(at: position(of: start), expected: "blank node label body")
            }
            restore(start)
            return nil
        }
        var label = ""
        // First character: PN_CHARS_U | digit
        guard let firstScalar = try peekScalar(start: start) else {
            return nil
        }
        guard isPNCharsU(firstScalar) || isAsciiDigit(firstScalar) else {
            throw ParserError.unexpectedCharacter(
                Character(firstScalar),
                at: currentPosition,
                expected: "blank node label start character"
            )
        }
        label.unicodeScalars.append(firstScalar)
        advanceScalar(firstScalar)

        // Body: (PN_CHARS | '.')* PN_CHARS — i.e., dots allowed in middle, not at end.
        var tail: [Unicode.Scalar] = []
        while true {
            guard cursor < bytes.count else {
                if atEOF { break }
                // We don't yet know if a continuation character follows; rewind.
                restore(start)
                return nil
            }
            guard let scalar = try peekScalar(start: start) else { return nil }
            if isPNChars(scalar) {
                tail.append(scalar)
                advanceScalar(scalar)
                continue
            }
            if scalar == "." {
                // Tentatively consume; if it's the final byte of the label,
                // we need to roll it back. Use a deferred-flush approach.
                tail.append(scalar)
                advanceScalar(scalar)
                continue
            }
            break
        }
        // Trim trailing dots: they belong to the next token (statement terminator).
        while let last = tail.last, last == "." {
            tail.removeLast()
            retreat()
        }
        for scalar in tail {
            label.unicodeScalars.append(scalar)
        }
        lastWasStringLiteral = false
        return Token(kind: .blankNodeLabel(label), position: position(of: start))
    }

    private mutating func readOpenBracketOrAnon(start: SavedState) throws -> Token? {
        advance() // consume '['
        let savedAfterBracket = savedState()
        // Try to detect ANON: `[` WS* `]`. We must not advance the real
        // cursor until we know.
        var lookahead = cursor
        while lookahead < bytes.count {
            let byte = bytes[lookahead]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                lookahead += 1
                continue
            }
            if byte == UInt8(ascii: "]") {
                // Consume whitespace + ']'.
                while cursor < lookahead {
                    advance()
                }
                advance() // ']'
                lastWasStringLiteral = false
                return Token(kind: .anon, position: position(of: start))
            }
            // Definitely an open-bracket-with-content.
            restore(savedAfterBracket)
            lastWasStringLiteral = false
            return Token(kind: .openBracket, position: position(of: start))
        }
        // Hit end of buffer mid-lookahead.
        if atEOF {
            // No `]` ever comes — emit the open bracket and let grammar fail.
            restore(savedAfterBracket)
            lastWasStringLiteral = false
            return Token(kind: .openBracket, position: position(of: start))
        }
        restore(start)
        return nil
    }

    // MARK: - @-form

    private mutating func readAtForm(start: SavedState) throws -> Token? {
        advance() // consume '@'
        // Read a contiguous run of letters / digits / '-'. Underscore is
        // intentionally excluded — neither LANGTAG nor the `@prefix` / `@base`
        // directives allow it, so terminating early lets us emit a clean
        // error for malformed inputs.
        let bodyStart = cursor
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if isAsciiLetter(byte) || isAsciiDigitByte(byte) || byte == UInt8(ascii: "-") {
                advance()
            } else {
                break
            }
        }
        if cursor == bodyStart {
            if atEOF {
                throw ParserError.grammar(
                    production: "@ directive",
                    at: position(of: start),
                    detail: "expected directive name or language tag"
                )
            }
            restore(start)
            return nil
        }
        // If we ran out of bytes and the next byte hasn't arrived, we cannot
        // tell if more letters follow.
        if cursor >= bytes.count, !atEOF {
            restore(start)
            return nil
        }
        let body = String(decoding: bytes[bodyStart..<cursor], as: UTF8.self)
        if lastWasStringLiteral {
            guard Self.isValidLangTag(body) else {
                throw ParserError.grammar(
                    production: "langtag",
                    at: position(of: start),
                    detail: "language tag '\(body)' does not match [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*"
                )
            }
            lastWasStringLiteral = false
            return Token(kind: .langTag(body), position: position(of: start))
        }
        switch body {
        case "prefix":
            lastWasStringLiteral = false
            return Token(kind: .prefixDirective, position: position(of: start))
        case "base":
            lastWasStringLiteral = false
            return Token(kind: .baseDirective, position: position(of: start))
        default:
            throw ParserError.grammar(
                production: "@ directive",
                at: position(of: start),
                detail: "unknown directive '@\(body)'"
            )
        }
    }

    // MARK: - Numeric / dot

    private mutating func readDotOrNumeric(start: SavedState) throws -> Token? {
        if let next = peek(offset: 1) {
            if isAsciiDigitByte(next) {
                // '.' + digit → decimal/double starting with '.'
                return try readNumericFromDot(start: start)
            }
        } else if !atEOF {
            // Could still extend into a decimal like `.5` once more bytes
            // arrive. Wait instead of committing to `.dot`.
            restore(start)
            return nil
        }
        advance()
        lastWasStringLiteral = false
        return Token(kind: .dot, position: position(of: start))
    }

    private mutating func readSignedNumeric(start: SavedState) throws -> Token? {
        // Consume sign tentatively, then a numeric body must follow.
        let signByte = bytes[cursor]
        advance()
        guard cursor < bytes.count else {
            if atEOF {
                throw ParserError.grammar(
                    production: "numeric literal",
                    at: position(of: start),
                    detail: "expected digit after sign"
                )
            }
            restore(start)
            return nil
        }
        let next = bytes[cursor]
        if isAsciiDigitByte(next) || next == UInt8(ascii: ".") {
            // Reuse the numeric reader, including the sign.
            return try readNumericBody(start: start, signByte: signByte)
        }
        throw ParserError.grammar(
            production: "numeric literal",
            at: position(of: start),
            detail: "expected digit after sign"
        )
    }

    private mutating func readNumeric(start: SavedState) throws -> Token? {
        return try readNumericBody(start: start, signByte: nil)
    }

    private mutating func readNumericFromDot(start: SavedState) throws -> Token? {
        return try readNumericBody(start: start, signByte: nil)
    }

    /// Read an unsigned numeric body. The caller may have already consumed
    /// a leading sign; we use the `start` saved state to know the token's
    /// first byte.
    private mutating func readNumericBody(start: SavedState, signByte: UInt8?) throws -> Token? {
        _ = signByte
        var hasDot = false
        var hasExponent = false
        var hasIntDigits = false
        var hasFracDigits = false

        // Optional integer digits.
        while cursor < bytes.count, isAsciiDigitByte(bytes[cursor]) {
            hasIntDigits = true
            advance()
        }
        // Optional dot + fractional digits.
        if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ".") {
            // Lookahead: only treat '.' as part of number if a digit follows
            // OR an exponent follows (decimal point with no fractional)
            // OR (integer literal): trailing dot is statement terminator.
            let next = peek(offset: 1)
            if let next, isAsciiDigitByte(next) {
                hasDot = true
                advance()
                while cursor < bytes.count, isAsciiDigitByte(bytes[cursor]) {
                    hasFracDigits = true
                    advance()
                }
            } else if next == UInt8(ascii: "e") || next == UInt8(ascii: "E") {
                hasDot = true
                advance()
            } else if next == nil, !atEOF {
                restore(start)
                return nil
            }
            // Otherwise the '.' is a statement terminator — leave it.
        }
        // Optional exponent.
        if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "e") || bytes[cursor] == UInt8(ascii: "E") {
            let expStart = savedState()
            advance()
            if cursor < bytes.count, bytes[cursor] == UInt8(ascii: "+") || bytes[cursor] == UInt8(ascii: "-") {
                advance()
            }
            if cursor >= bytes.count {
                if atEOF {
                    throw ParserError.grammar(
                        production: "numeric literal",
                        at: position(of: start),
                        detail: "exponent requires digits"
                    )
                }
                restore(start)
                return nil
            }
            guard isAsciiDigitByte(bytes[cursor]) else {
                _ = expStart
                throw ParserError.grammar(
                    production: "numeric literal",
                    at: position(of: start),
                    detail: "exponent requires digits"
                )
            }
            while cursor < bytes.count, isAsciiDigitByte(bytes[cursor]) {
                advance()
            }
            hasExponent = true
        }
        // We may need more input to know whether an exponent or dot or
        // additional digits follow.
        if cursor >= bytes.count, !atEOF {
            restore(start)
            return nil
        }
        guard hasIntDigits || hasFracDigits else {
            throw ParserError.grammar(
                production: "numeric literal",
                at: position(of: start),
                detail: "no digits"
            )
        }
        let lexeme = String(decoding: bytes[start.cursor..<cursor], as: UTF8.self)
        lastWasStringLiteral = false
        if hasExponent {
            return Token(kind: .double(lexeme), position: position(of: start))
        }
        if hasDot {
            return Token(kind: .decimal(lexeme), position: position(of: start))
        }
        return Token(kind: .integer(lexeme), position: position(of: start))
    }

    // MARK: - ^^

    private mutating func readDoubleCaret(start: SavedState) throws -> Token? {
        guard peek(offset: 1) == UInt8(ascii: "^") else {
            if atEOF {
                throw ParserError.unexpectedCharacter(
                    "^",
                    at: position(of: start),
                    expected: "'^^' datatype delimiter"
                )
            }
            restore(start)
            return nil
        }
        advance()
        advance()
        lastWasStringLiteral = false
        return Token(kind: .doubleCaret, position: position(of: start))
    }

    // MARK: - Identifier / keyword / prefixed name

    private mutating func readIdentifierLike(start: SavedState) throws -> Token? {
        // Read a "prefix candidate": PN_CHARS_BASE ((PN_CHARS | '.')* PN_CHARS)?
        // If immediately followed by ':' → PNAME_NS / PNAME_LN.
        // Otherwise check keyword / boolean / `a`.

        let firstScalar: Unicode.Scalar
        guard let scanned = try peekScalar(start: start) else { return nil }
        firstScalar = scanned

        if !isPNCharsBase(firstScalar) {
            throw ParserError.unexpectedCharacter(
                Character(firstScalar),
                at: currentPosition,
                expected: "identifier start"
            )
        }

        let firstCursor = cursor
        var ident = String(firstScalar)
        advanceScalar(firstScalar)

        var tailScalars: [Unicode.Scalar] = []
        var lookaheadHit = false
        while cursor < bytes.count {
            guard let scalar = try peekScalar(start: start) else { return nil }
            if isPNChars(scalar) {
                tailScalars.append(scalar)
                advanceScalar(scalar)
                continue
            }
            if scalar == "." {
                tailScalars.append(scalar)
                advanceScalar(scalar)
                continue
            }
            lookaheadHit = true
            break
        }
        if !lookaheadHit, !atEOF {
            restore(start)
            return nil
        }
        // Trim trailing dots from the prefix candidate.
        while let last = tailScalars.last, last == "." {
            tailScalars.removeLast()
            retreat()
        }
        for scalar in tailScalars {
            ident.unicodeScalars.append(scalar)
        }
        _ = firstCursor

        // If the next byte is ':', this is a prefixed name.
        if cursor < bytes.count, bytes[cursor] == UInt8(ascii: ":") {
            advance()
            let local = try readPNLocal(start: start)
            // local nil → need more input
            if local == nil { return nil }
            lastWasStringLiteral = false
            return Token(kind: .prefixedName(prefix: ident, local: local!), position: position(of: start))
        }

        // Not a prefixed name — dispatch keywords / booleans / `a`.
        lastWasStringLiteral = false
        switch ident {
        case "a":
            return Token(kind: .aKeyword, position: position(of: start))
        case "true":
            return Token(kind: .boolean(true), position: position(of: start))
        case "false":
            return Token(kind: .boolean(false), position: position(of: start))
        default:
            break
        }
        if ident.caseInsensitiveCompare("PREFIX") == .orderedSame {
            return Token(kind: .sparqlPrefix, position: position(of: start))
        }
        if ident.caseInsensitiveCompare("BASE") == .orderedSame {
            return Token(kind: .sparqlBase, position: position(of: start))
        }
        if ident.caseInsensitiveCompare("GRAPH") == .orderedSame {
            return Token(kind: .graphKeyword, position: position(of: start))
        }
        throw ParserError.grammar(
            production: "identifier",
            at: position(of: start),
            detail: "unrecognised identifier '\(ident)'"
        )
    }

    /// Read PN_LOCAL after the ':' has been consumed. Returns nil only when
    /// more input is required. Returns "" for an empty local part.
    private mutating func readPNLocal(start: SavedState) throws -> String? {
        var value = ""
        var tail: [Unicode.Scalar] = []
        var first = true
        while cursor < bytes.count {
            let byte = bytes[cursor]
            if byte == UInt8(ascii: "%") {
                let escapePos = currentPosition
                if cursor + 3 > bytes.count {
                    if atEOF {
                        throw ParserError.invalidEscape(sequence: "%", at: escapePos)
                    }
                    restore(start)
                    return nil
                }
                let high = bytes[cursor + 1]
                let low = bytes[cursor + 2]
                guard let h = hexValue(high), let l = hexValue(low) else {
                    let text = String(decoding: bytes[cursor..<min(bytes.count, cursor + 3)], as: UTF8.self)
                    throw ParserError.invalidEscape(sequence: text, at: escapePos)
                }
                _ = h; _ = l
                if first {
                    value.append("%")
                    value.unicodeScalars.append(Unicode.Scalar(high))
                    value.unicodeScalars.append(Unicode.Scalar(low))
                    first = false
                } else {
                    tail.append("%")
                    tail.append(Unicode.Scalar(high))
                    tail.append(Unicode.Scalar(low))
                }
                advance(); advance(); advance()
                continue
            }
            if byte == UInt8(ascii: "\\") {
                let escapePos = currentPosition
                if cursor + 1 >= bytes.count {
                    if atEOF {
                        throw ParserError.invalidEscape(sequence: "\\", at: escapePos)
                    }
                    restore(start)
                    return nil
                }
                let escByte = bytes[cursor + 1]
                guard TurtleEscapes.isLocalEscapeCharacter(escByte) else {
                    throw ParserError.invalidEscape(
                        sequence: "\\\(Character(UnicodeScalar(escByte)))",
                        at: escapePos
                    )
                }
                if first {
                    value.unicodeScalars.append(Unicode.Scalar(escByte))
                    first = false
                } else {
                    tail.append(Unicode.Scalar(escByte))
                }
                advance(); advance()
                continue
            }
            guard let scalar = try peekScalar(start: start) else { return nil }
            if first {
                if scalar == ":" || isPNCharsU(scalar) || isAsciiDigit(scalar) {
                    value.unicodeScalars.append(scalar)
                    advanceScalar(scalar)
                    first = false
                    continue
                }
                // Empty local — break.
                break
            } else {
                if scalar == ":" || isPNChars(scalar) {
                    tail.append(scalar)
                    advanceScalar(scalar)
                    continue
                }
                if scalar == "." {
                    tail.append(scalar)
                    advanceScalar(scalar)
                    continue
                }
                break
            }
        }
        if cursor >= bytes.count, !atEOF {
            // We can't tell if more PN_LOCAL characters are coming.
            restore(start)
            return nil
        }
        // Trim trailing dots from PN_LOCAL (statement terminator).
        while let last = tail.last, last == "." {
            tail.removeLast()
            retreat()
        }
        for scalar in tail {
            value.unicodeScalars.append(scalar)
        }
        return value
    }

    // MARK: - Cursor helpers

    private mutating func advance() {
        let byte = bytes[cursor]
        cursor += 1
        if byte == 0x0A {
            line += 1
            column = 1
        } else {
            column += 1
        }
    }

    private mutating func advanceScalar(_ scalar: Unicode.Scalar) {
        let length = utf8Length(of: scalar)
        if scalar.value == 0x0A {
            cursor += length
            line += 1
            column = 1
            return
        }
        cursor += length
        column += 1
    }

    /// Retreat by one byte. Used only when we tentatively consumed a `.`
    /// that turned out to be a statement terminator. The byte is guaranteed
    /// to not be a newline because '.' is ASCII 0x2E.
    private mutating func retreat() {
        cursor -= 1
        column -= 1
    }

    private func peek(offset: Int) -> UInt8? {
        let position = cursor + offset
        guard position < bytes.count else { return nil }
        return bytes[position]
    }

    private func position(of saved: SavedState) -> SourcePosition {
        SourcePosition(line: saved.line, column: saved.column, byteOffset: saved.cursor)
    }

    private struct SavedState {
        let cursor: Int
        let line: Int
        let column: Int
        let lastWasStringLiteral: Bool
    }

    private func savedState() -> SavedState {
        SavedState(cursor: cursor, line: line, column: column, lastWasStringLiteral: lastWasStringLiteral)
    }

    private mutating func restore(_ state: SavedState) {
        cursor = state.cursor
        line = state.line
        column = state.column
        lastWasStringLiteral = state.lastWasStringLiteral
    }

    private mutating func compact() {
        if cursor == 0 { return }
        if cursor >= bytes.count {
            bytes.removeAll(keepingCapacity: true)
            cursor = 0
            return
        }
        if cursor > 16_384 {
            bytes.removeFirst(cursor)
            cursor = 0
        }
    }

    // MARK: - UTF-8 helpers

    /// Length in bytes of the UTF-8 sequence whose lead byte is at `index`,
    /// or `0` if `bytes[index]` is not a valid lead.
    private func utf8SequenceLength(at index: Int) -> Int {
        let byte = bytes[index]
        if byte < 0x80 { return 1 }
        if byte < 0xC2 { return 0 }
        if byte < 0xE0 { return 2 }
        if byte < 0xF0 { return 3 }
        if byte < 0xF5 { return 4 }
        return 0
    }

    private func utf8Length(of scalar: Unicode.Scalar) -> Int {
        let value = scalar.value
        if value < 0x80 { return 1 }
        if value < 0x800 { return 2 }
        if value < 0x10000 { return 3 }
        return 4
    }

    /// Peek the next Unicode scalar without advancing. Returns nil when
    /// more bytes are needed (rewinds to `start`).
    private mutating func peekScalar(start: SavedState) throws -> Unicode.Scalar? {
        guard cursor < bytes.count else {
            if atEOF { return nil }
            restore(start)
            return nil
        }
        let length = utf8SequenceLength(at: cursor)
        if length == 0 {
            throw ParserError.unexpectedCharacter(
                "?",
                at: currentPosition,
                expected: "valid UTF-8 byte"
            )
        }
        if cursor + length > bytes.count {
            if atEOF {
                throw ParserError.unexpectedEndOfInput(at: currentPosition, expected: "UTF-8 continuation byte")
            }
            restore(start)
            return nil
        }
        var value: UInt32 = 0
        switch length {
        case 1:
            value = UInt32(bytes[cursor])
        case 2:
            value = (UInt32(bytes[cursor] & 0x1F) << 6) | UInt32(bytes[cursor + 1] & 0x3F)
        case 3:
            value = (UInt32(bytes[cursor] & 0x0F) << 12)
                  | (UInt32(bytes[cursor + 1] & 0x3F) << 6)
                  | UInt32(bytes[cursor + 2] & 0x3F)
        case 4:
            value = (UInt32(bytes[cursor] & 0x07) << 18)
                  | (UInt32(bytes[cursor + 1] & 0x3F) << 12)
                  | (UInt32(bytes[cursor + 2] & 0x3F) << 6)
                  | UInt32(bytes[cursor + 3] & 0x3F)
        default:
            value = 0
        }
        guard let scalar = Unicode.Scalar(value) else {
            throw ParserError.unexpectedCharacter(
                "?",
                at: currentPosition,
                expected: "valid Unicode scalar"
            )
        }
        return scalar
    }

    private func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x41 + 10
        case 0x61...0x66: return byte - 0x61 + 10
        default: return nil
        }
    }

    // MARK: - Character classes

    private func isAsciiLetter(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
    }

    private func isAsciiDigitByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte)
    }

    private func isAsciiDigit(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value)
    }

    private func isPNCharsBase(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if (0x41...0x5A).contains(v) { return true }
        if (0x61...0x7A).contains(v) { return true }
        if (0x00C0...0x00D6).contains(v) { return true }
        if (0x00D8...0x00F6).contains(v) { return true }
        if (0x00F8...0x02FF).contains(v) { return true }
        if (0x0370...0x037D).contains(v) { return true }
        if (0x037F...0x1FFF).contains(v) { return true }
        if (0x200C...0x200D).contains(v) { return true }
        if (0x2070...0x218F).contains(v) { return true }
        if (0x2C00...0x2FEF).contains(v) { return true }
        if (0x3001...0xD7FF).contains(v) { return true }
        if (0xF900...0xFDCF).contains(v) { return true }
        if (0xFDF0...0xFFFD).contains(v) { return true }
        if (0x10000...0xEFFFF).contains(v) { return true }
        return false
    }

    private func isPNCharsU(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || isPNCharsBase(scalar)
    }

    private func isPNChars(_ scalar: Unicode.Scalar) -> Bool {
        if isPNCharsU(scalar) { return true }
        let v = scalar.value
        if v == UInt32(("-" as Unicode.Scalar).value) { return true }
        if isAsciiDigit(scalar) { return true }
        if v == 0x00B7 { return true }
        if (0x0300...0x036F).contains(v) { return true }
        if (0x203F...0x2040).contains(v) { return true }
        return false
    }

    // MARK: - IRIREF / LANGTAG validators

    /// A character that the IRIREF grammar excludes even when written as a
    /// `\uXXXX` / `\UXXXXXXXX` escape (per RDF 1.1 §6.4 / W3C Turtle
    /// `turtle-eval-bad-{01,02,03}` test cases).
    static func isIRIRefDisallowedScalar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if v <= 0x20 { return true }
        switch v {
        case 0x22, 0x3C, 0x3E, 0x5C, 0x5E, 0x60, 0x7B, 0x7C, 0x7D:
            return true
        default:
            return false
        }
    }

    /// Validate a language tag body (the part after `@`). Matches the BCP-47
    /// subset that Turtle pins down in its grammar:
    /// `LANGTAG ::= '@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*`.
    static func isValidLangTag(_ body: String) -> Bool {
        if body.isEmpty { return false }
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        guard let first = parts.first, !first.isEmpty else { return false }
        for scalar in first.unicodeScalars {
            let v = scalar.value
            let isLetter = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
            if !isLetter { return false }
        }
        for subtag in parts.dropFirst() {
            if subtag.isEmpty { return false }
            for scalar in subtag.unicodeScalars {
                let v = scalar.value
                let isLetter = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
                let isDigit = (0x30...0x39).contains(v)
                if !(isLetter || isDigit) { return false }
            }
        }
        return true
    }
}
