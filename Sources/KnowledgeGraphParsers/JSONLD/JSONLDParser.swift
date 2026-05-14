import Foundation
import KnowledgeGraph

/// JSON-LD 1.1 parser.
///
/// JSON-LD is not amenable to incremental parsing: every value-expansion
/// decision depends on the full `@context`, which itself may appear anywhere
/// in the document. We therefore buffer the entire UTF-8 payload across
/// `parseChunk` calls and run the pipeline in `finish`. The pipeline is:
///
///   bytes → JSONValueDecoder → JSONLDExpansion → JSONLDNodeMapGeneration
///                                              → JSONLDToRDF → builder
///
/// The non-streaming shape preserves the `KnowledgeGraphParser` contract:
/// callers that want a one-shot parse use `parseAll`; callers that want to
/// thread bytes in piecewise still get correct results (only the timing of
/// builder writes changes — they all happen in `finish`).
///
/// Network handling: per the project invariant, remote `@context` (a string
/// `@context` value) is rejected at context-processing time with
/// `ParserError.unsupportedFeature`. Callers needing remote contexts will
/// inject a resolver in a later revision.
public struct JSONLDParser: KnowledgeGraphParser {

    public var context: ParsingContext

    private var buffer: [UInt8] = []

    public init(context: ParsingContext = ParsingContext()) {
        self.context = context
    }

    public mutating func parseChunk(
        _ bytes: ArraySlice<UInt8>,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        buffer.append(contentsOf: bytes)
    }

    public mutating func finish(into builder: inout KnowledgeGraphBuilder) throws {
        if buffer.isEmpty {
            throw ParserError.unexpectedEndOfInput(
                at: .start,
                expected: "JSON-LD document"
            )
        }
        let (value, endPosition) = try JSONValueDecoder.decodeWithEndPosition(buffer)
        var active = JSONLDContext()
        if let base = context.baseIRI {
            active.baseIRI = base.value
        }
        // §3.2: when the top-level value is an object, its `@context` (if any)
        // is the document context. When it is an array, each element's
        // context applies locally — but a top-level `@context` array also
        // sometimes appears. Expansion handles both branches uniformly.
        //
        // The end-position from the decoder is the byte/line where the JSON
        // payload terminated. Seeding the algorithms with it means errors
        // raised after the JSON has been decoded carry "somewhere in this
        // N-byte document" rather than line 1 column 1 — useful while
        // per-node position tracking is still future work.
        var expansion = JSONLDExpansion(position: endPosition)
        let expanded = try expansion.expandDocument(value, context: active)
        var nodeGen = JSONLDNodeMapGeneration(position: endPosition)
        let map = try nodeGen.generate(from: expanded)
        var toRdf = JSONLDToRDF(context: context)
        try toRdf.emit(map, into: &builder)
        context = toRdf.context
    }
}
