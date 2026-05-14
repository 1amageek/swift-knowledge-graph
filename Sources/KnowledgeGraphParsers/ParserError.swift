import Foundation

/// Every error a knowledge-graph parser raises lands in this single typed
/// enum. The variants distinguish lexical, grammatical, semantic, and
/// IRI-resolution failures so callers can react to specific classes without
/// brittle message-string matching.
///
/// Every variant carries a `SourcePosition` so callers can produce
/// `file:line:column`-style diagnostics. There is no "unknown error" /
/// catch-all variant on purpose — adding a new failure mode should require
/// adding a new case here, which forces an exhaustive review of every
/// switch.
public enum ParserError: Error, Hashable, Sendable {

    // MARK: - Lexical errors

    /// Reached end of input while a syntactic construct was still open
    /// (a quoted literal, a delimited collection, an XML element, etc.).
    case unexpectedEndOfInput(at: SourcePosition, expected: String)

    /// Encountered a character that the current production does not allow.
    case unexpectedCharacter(Character, at: SourcePosition, expected: String)

    /// A `\uXXXX` / `\UXXXXXXXX` / `\\` / `\t` / ... escape sequence is
    /// malformed or names a code point that is not allowed at this position
    /// in the grammar.
    case invalidEscape(sequence: String, at: SourcePosition)

    /// A string-typed literal began but its terminator (`"`, `"""`, etc.)
    /// never arrived before EOF.
    case unterminatedLiteral(at: SourcePosition)

    /// A numeric / boolean / typed literal failed validation rules for its
    /// declared datatype (e.g. `"not-an-integer"^^xsd:integer`).
    case invalidLiteral(value: String, at: SourcePosition, reason: String)

    // MARK: - IRI / prefix errors

    /// A reference IRI failed RFC 3986 syntactic validation.
    case invalidIRI(value: String, at: SourcePosition, reason: String)

    /// A relative IRI was found but no base IRI is in scope.
    case noBaseIRI(at: SourcePosition)

    /// A CURIE used a prefix that has not been declared.
    case undefinedPrefix(prefix: String, at: SourcePosition)

    // MARK: - Grammar errors

    /// A syntactic production could not be satisfied — the parser knows
    /// what it was trying to recognise (`production`) and what input it
    /// found instead.
    case grammar(production: String, at: SourcePosition, detail: String)

    /// The XML payload (RDF/XML) is structurally invalid before any RDF
    /// semantics get a chance to apply.
    case xmlSyntax(detail: String, at: SourcePosition)

    /// The JSON payload (JSON-LD) is structurally invalid as plain JSON.
    case jsonSyntax(detail: String, at: SourcePosition)

    // MARK: - Semantic / spec errors

    /// The document uses a feature that is part of the spec but that this
    /// parser intentionally does not yet implement. Carries the feature
    /// name verbatim from the spec so callers can match on it.
    case unsupportedFeature(name: String, at: SourcePosition)

    /// A blank-node label crossed a scope boundary it should not have.
    case blankScopeLeak(label: String, at: SourcePosition)
}

extension ParserError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unexpectedEndOfInput(let at, let expected):
            return "unexpected end of input at \(at): expected \(expected)"
        case .unexpectedCharacter(let char, let at, let expected):
            return "unexpected character \(String(reflecting: char)) at \(at): expected \(expected)"
        case .invalidEscape(let sequence, let at):
            return "invalid escape sequence \(String(reflecting: sequence)) at \(at)"
        case .unterminatedLiteral(let at):
            return "unterminated literal at \(at)"
        case .invalidLiteral(let value, let at, let reason):
            return "invalid literal \(String(reflecting: value)) at \(at): \(reason)"
        case .invalidIRI(let value, let at, let reason):
            return "invalid IRI \(String(reflecting: value)) at \(at): \(reason)"
        case .noBaseIRI(let at):
            return "relative IRI reference at \(at) but no base IRI is in scope"
        case .undefinedPrefix(let prefix, let at):
            return "undefined prefix \(String(reflecting: prefix)) at \(at)"
        case .grammar(let production, let at, let detail):
            return "grammar error in production \(production) at \(at): \(detail)"
        case .xmlSyntax(let detail, let at):
            return "XML syntax error at \(at): \(detail)"
        case .jsonSyntax(let detail, let at):
            return "JSON syntax error at \(at): \(detail)"
        case .unsupportedFeature(let name, let at):
            return "unsupported feature \(String(reflecting: name)) at \(at)"
        case .blankScopeLeak(let label, let at):
            return "blank node \(String(reflecting: label)) leaked across scope boundary at \(at)"
        }
    }
}

extension ParserError {
    /// Position carried by this error. Convenience for callers that just
    /// want `error.position.line` without unwrapping the enum.
    public var position: SourcePosition {
        switch self {
        case .unexpectedEndOfInput(let at, _),
             .unexpectedCharacter(_, let at, _),
             .invalidEscape(_, let at),
             .unterminatedLiteral(let at),
             .invalidLiteral(_, let at, _),
             .invalidIRI(_, let at, _),
             .noBaseIRI(let at),
             .undefinedPrefix(_, let at),
             .grammar(_, let at, _),
             .xmlSyntax(_, let at),
             .jsonSyntax(_, let at),
             .unsupportedFeature(_, let at),
             .blankScopeLeak(_, let at):
            return at
        }
    }
}
