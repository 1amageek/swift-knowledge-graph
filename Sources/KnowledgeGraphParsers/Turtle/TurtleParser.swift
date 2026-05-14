import Foundation
import KnowledgeGraph

/// Streaming Turtle 1.1 parser.
///
/// The parser maintains:
/// - a `TurtleTokenizer` for incremental lexical analysis
/// - a reusable `TurtleGrammar` instance that owns the token buffer and the
///   `ParsingContext`, exposing the productions shared with TriG
///
/// Each call to `parseChunk` runs the lexer over newly buffered bytes,
/// drains as many complete statements as possible into `builder`, and
/// stops at the first statement that needs more input. Triples that have
/// already been emitted remain in the builder — re-parsing on the next
/// chunk will repeat the work, but the builder's idempotent `insert*`
/// methods make this safe.
public struct TurtleParser: KnowledgeGraphParser {

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
                expected: "complete statement"
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
            do {
                try grammar.parseStatement(into: &builder)
                compactTokenBuffer()
            } catch is TurtleGrammar.NeedMoreInput {
                grammar.head = savedHead
                grammar.context = savedContext
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
}
