import Foundation
import KnowledgeGraph

/// Streaming TriG 1.1 parser.
///
/// TriG extends Turtle with named graphs. Its grammar embeds Turtle wholesale,
/// adding three new productions at the top level:
///
///     block          ::= triplesOrGraph
///                      | wrappedGraph
///                      | triples2
///                      | "GRAPH" labelOrSubject wrappedGraph
///     triplesOrGraph ::= labelOrSubject (wrappedGraph | predicateObjectList '.')
///     wrappedGraph   ::= '{' triplesBlock? '}'
///     triplesBlock   ::= triples ('.' triples)* '.'?
///
/// Concretely this means: a statement may be a normal Turtle triple, or it
/// may be a `{ ... }` block (default graph), or `<label> { ... }` /
/// `_:label { ... }` / `[] { ... }` / `GRAPH <label> { ... }` (named graph).
/// Inside the braces the trailing `.` of the last `triples` is optional.
///
/// The implementation reuses `TurtleGrammar` for every shared production
/// (subjects, predicate-object lists, blank node property lists, literals,
/// collections) and threads `currentGraph` through that grammar so emitted
/// triples land in the right named graph.
public struct TriGParser: KnowledgeGraphParser {

    public var context: ParsingContext {
        get { grammar.context }
        set { grammar.context = newValue }
    }

    private var tokenizer: TurtleTokenizer
    private var grammar: TurtleGrammar

    public init(context: ParsingContext = ParsingContext()) {
        self.tokenizer = TurtleTokenizer()
        self.grammar = TurtleGrammar(context: context)
    }

    // MARK: - KnowledgeGraphParser

    public mutating func parseChunk(
        _ bytes: ArraySlice<UInt8>,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        tokenizer.append(bytes)
        try pullTokens()
        try drain(into: &builder)
    }

    public mutating func finish(into builder: inout KnowledgeGraphBuilder) throws {
        tokenizer.markEndOfInput()
        try pullTokens()
        try drain(into: &builder)
        if grammar.head < grammar.tokens.count {
            throw ParserError.unexpectedEndOfInput(
                at: grammar.tokens[grammar.head].position,
                expected: "complete statement or graph block"
            )
        }
        if !tokenizer.isExhausted {
            throw ParserError.unexpectedEndOfInput(
                at: tokenizer.currentPosition,
                expected: "end of input"
            )
        }
    }

    // MARK: - Token pump

    private mutating func pullTokens() throws {
        while let token = try tokenizer.nextToken() {
            grammar.tokens.append(token)
        }
    }

    private mutating func drain(into builder: inout KnowledgeGraphBuilder) throws {
        while grammar.head < grammar.tokens.count {
            let savedHead = grammar.head
            let savedContext = grammar.context
            let savedGraph = grammar.currentGraph
            do {
                try parseBlock(into: &builder)
                compactTokenBuffer()
            } catch is TurtleGrammar.NeedMoreInput {
                grammar.head = savedHead
                grammar.context = savedContext
                grammar.currentGraph = savedGraph
                return
            }
        }
    }

    private mutating func compactTokenBuffer() {
        if grammar.head > 512 {
            grammar.tokens.removeFirst(grammar.head)
            grammar.head = 0
        }
    }

    // MARK: - Grammar: top level

    private mutating func parseBlock(into builder: inout KnowledgeGraphBuilder) throws {
        let token = try grammar.peekToken()
        switch token.kind {
        case .prefixDirective:
            grammar.head += 1
            try grammar.parsePrefixDirective(opener: token, requiresDot: true)
        case .baseDirective:
            grammar.head += 1
            try grammar.parseBaseDirective(opener: token, requiresDot: true)
        case .sparqlPrefix:
            grammar.head += 1
            try grammar.parsePrefixDirective(opener: token, requiresDot: false)
        case .sparqlBase:
            grammar.head += 1
            try grammar.parseBaseDirective(opener: token, requiresDot: false)
        case .openBrace:
            grammar.currentGraph = nil
            try parseWrappedGraph(into: &builder)
        case .graphKeyword:
            grammar.head += 1
            try parseGraphKeywordBlock(into: &builder)
        case .openBracket:
            // BlankNodePropertyList in default graph — uses standard Turtle
            // `triples '.'` syntax (no graph block via this form).
            grammar.currentGraph = nil
            try grammar.parseTriples(into: &builder)
        case .openParen:
            // Collection-rooted triple in default graph — `triples2`.
            grammar.currentGraph = nil
            try grammar.parseTriples(into: &builder)
        case .anon, .iriRef, .prefixedName, .blankNodeLabel:
            try parseTriplesOrGraph(opener: token, into: &builder)
        default:
            throw ParserError.grammar(
                production: "block",
                at: token.position,
                detail: "expected directive, '{', 'GRAPH', label, or triple"
            )
        }
    }

    /// Disambiguate `labelOrSubject (wrappedGraph | predicateObjectList '.')`.
    /// We have already peeked at the leading label-or-subject token. Consume
    /// it, then look at the next token: `{` means a wrappedGraph; otherwise
    /// rewind and let `TurtleGrammar.parseTriples` parse a normal triple in
    /// the default graph.
    private mutating func parseTriplesOrGraph(
        opener: Token,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        let labelHead = grammar.head
        grammar.head += 1
        let next = try grammar.peekToken()
        if case .openBrace = next.kind {
            let label = try labelOrSubjectIRI(from: opener)
            grammar.currentGraph = label
            try parseWrappedGraph(into: &builder)
            return
        }
        // Not a graph block — replay the leading token as a normal subject.
        grammar.head = labelHead
        grammar.currentGraph = nil
        try grammar.parseTriples(into: &builder)
    }

    private mutating func parseGraphKeywordBlock(into builder: inout KnowledgeGraphBuilder) throws {
        let labelToken = try grammar.expectToken()
        let label = try labelOrSubjectIRI(from: labelToken)
        grammar.currentGraph = label
        try parseWrappedGraph(into: &builder)
    }

    /// Parse `'{' triplesBlock? '}'`. The trailing `.` of the last `triples`
    /// is optional per the TriG grammar.
    private mutating func parseWrappedGraph(into builder: inout KnowledgeGraphBuilder) throws {
        let brace = try grammar.expectToken()
        guard case .openBrace = brace.kind else {
            throw ParserError.grammar(
                production: "wrappedGraph",
                at: brace.position,
                detail: "expected '{'"
            )
        }
        if let graphID = grammar.currentGraph {
            try builder.insertNamedGraph(NamedGraph(id: graphID))
        }
        while true {
            let next = try grammar.peekToken()
            if case .closeBrace = next.kind {
                grammar.head += 1
                grammar.currentGraph = nil
                return
            }
            try grammar.parseTriplesBody(into: &builder)
            let after = try grammar.peekToken()
            if case .dot = after.kind {
                grammar.head += 1
                continue
            }
            if case .closeBrace = after.kind {
                grammar.head += 1
                grammar.currentGraph = nil
                return
            }
            throw ParserError.grammar(
                production: "triplesBlock",
                at: after.position,
                detail: "expected '.' or '}'"
            )
        }
    }

    /// Convert a label-or-subject token into the graph identifier string used
    /// by `KnowledgeGraphBuilder`. IRIs and prefixed names resolve through the
    /// context; blank-node labels go through the scope-local table; `[]`
    /// allocates a fresh blank node.
    private mutating func labelOrSubjectIRI(from token: Token) throws -> String {
        switch token.kind {
        case .iriRef(let value):
            let resolved = try grammar.context.resolveIRIReference(value, at: token.position)
            return resolved.value
        case .prefixedName(let prefix, let local):
            let resolved = try grammar.context.resolveCURIE(
                prefix: prefix,
                suffix: local,
                at: token.position
            )
            return resolved.value
        case .blankNodeLabel(let label):
            return grammar.context.blankNode(forLabel: label).key
        case .anon:
            return grammar.context.freshBlankNode().key
        default:
            throw ParserError.grammar(
                production: "labelOrSubject",
                at: token.position,
                detail: "expected IRI / prefixed name / blank node"
            )
        }
    }
}
