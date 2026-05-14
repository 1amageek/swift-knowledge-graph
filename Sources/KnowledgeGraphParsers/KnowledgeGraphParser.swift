import Foundation
import KnowledgeGraph

/// Common contract for every concrete RDF parser in this module.
///
/// The contract is deliberately streaming-first. Even a parser that you
/// hand a whole document to runs through `parseChunk` + `finish` — the
/// "parse everything at once" entry point (`parseAll`) is provided as a
/// default extension and just dispatches into the same two methods. This
/// keeps a single well-tested code path and matches the chunked input
/// semantics required by goal item #7.
///
/// Each parser owns a `ParsingContext` that accumulates state across
/// chunks. The builder is passed `inout` so the parser can append triples
/// as soon as they are syntactically complete — never before.
public protocol KnowledgeGraphParser: Sendable {

    /// Per-parse state. Concrete parsers may seed this from `init(context:)`.
    var context: ParsingContext { get set }

    /// Feed another slice of UTF-8 bytes into the parser. Bytes that
    /// complete one or more triples are flushed to `builder` before the
    /// call returns; bytes that span a chunk boundary remain buffered for
    /// the next call.
    ///
    /// Throws on any spec violation. The parser is left in an
    /// implementation-defined state after a throw — callers must discard
    /// it and start over rather than continue feeding chunks.
    mutating func parseChunk(
        _ bytes: ArraySlice<UInt8>,
        into builder: inout KnowledgeGraphBuilder
    ) throws

    /// Signal end-of-input. Implementations must flush any state that
    /// would otherwise remain buffered, and raise
    /// `ParserError.unexpectedEndOfInput` if the document is
    /// syntactically incomplete.
    mutating func finish(into builder: inout KnowledgeGraphBuilder) throws
}

extension KnowledgeGraphParser {

    /// Convenience: feed a whole UTF-8 byte buffer and finish in one call.
    public mutating func parseAll(
        _ bytes: some Collection<UInt8>,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        try parseChunk(ArraySlice(Array(bytes)), into: &builder)
        try finish(into: &builder)
    }

    /// Convenience: feed a whole `String` and finish in one call.
    public mutating func parseAll(
        _ text: String,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        try parseAll(Array(text.utf8), into: &builder)
    }

    /// Convenience: parse a whole document and return its snapshot directly.
    /// Useful for one-shot parses where the caller does not need to thread
    /// a builder across multiple parse calls.
    public mutating func parse(_ text: String) throws -> KnowledgeGraph {
        var builder = KnowledgeGraphBuilder()
        try parseAll(text, into: &builder)
        return builder.build()
    }
}
