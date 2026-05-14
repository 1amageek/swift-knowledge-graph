import Foundation

/// One Turtle / TriG lexical token together with the source position of its
/// first byte. The grammar layer consumes a stream of these values; the
/// tokenizer is responsible for handling whitespace, comments, escapes, and
/// numeric / string lexical forms.
///
/// Tokens carry only the raw lexical form — translation into RDF values
/// (resolving prefixes, attaching `xsd:integer` to integers, etc.) happens
/// during grammar evaluation, where the `ParsingContext` is in scope.
struct Token: Hashable, Sendable {
    let kind: Kind
    let position: SourcePosition

    enum Kind: Hashable, Sendable {

        // MARK: - Resource references

        /// `<...>` IRI reference, after escape processing.
        case iriRef(String)

        /// `prefix:local` form. Either component may be empty (`:foo`,
        /// `prefix:`, `:`). `local` is the *decoded* local part with all
        /// `PN_LOCAL_ESC` sequences resolved.
        case prefixedName(prefix: String, local: String)

        /// `_:label` blank-node label, without the leading `_:`.
        case blankNodeLabel(String)

        /// `[ ]` (with arbitrary whitespace between) — the anonymous blank
        /// node shortcut.
        case anon

        // MARK: - Literals

        /// Quoted string literal, after escape processing.
        case stringLiteral(String)

        /// `@lang-subtag` — emitted directly after a `stringLiteral` token
        /// when present, otherwise the lexical form is just a plain string.
        case langTag(String)

        /// `^^` datatype IRI delimiter, used between a `stringLiteral` and
        /// an `iriRef` / `prefixedName`.
        case doubleCaret

        /// `[+-]?[0-9]+` matched literally — datatype assignment is the
        /// grammar's job.
        case integer(String)

        /// `[+-]?[0-9]*'.'[0-9]+` matched literally.
        case decimal(String)

        /// `[+-]?(...) EXPONENT` matched literally.
        case double(String)

        /// `true` or `false` keyword.
        case boolean(Bool)

        // MARK: - Punctuation

        /// `.` — end of a statement (NOT the decimal point — the tokenizer
        /// distinguishes those by lookahead).
        case dot

        /// `,` — object-list separator.
        case comma

        /// `;` — predicate-object-list separator.
        case semicolon

        /// `[` — start of `blankNodePropertyList`.
        case openBracket

        /// `]` — end of `blankNodePropertyList`.
        case closeBracket

        /// `(` — start of `collection`.
        case openParen

        /// `)` — end of `collection`.
        case closeParen

        /// `{` — start of TriG `wrappedGraph`.
        case openBrace

        /// `}` — end of TriG `wrappedGraph`.
        case closeBrace

        // MARK: - Keywords

        /// The bare `a` predicate (rdf:type shortcut).
        case aKeyword

        /// `@prefix` directive opener.
        case prefixDirective

        /// `@base` directive opener.
        case baseDirective

        /// SPARQL-style `PREFIX` opener (case-insensitive).
        case sparqlPrefix

        /// SPARQL-style `BASE` opener (case-insensitive).
        case sparqlBase

        /// TriG `GRAPH` keyword (case-insensitive).
        case graphKeyword
    }
}
