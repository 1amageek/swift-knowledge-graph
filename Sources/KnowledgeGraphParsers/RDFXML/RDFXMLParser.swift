import Foundation
import KnowledgeGraph

/// RDF/XML 1.1 parser.
///
/// RDF/XML's XML payload is parsed with Foundation's `XMLParser` (NSXMLParser),
/// which is a SAX-style class-based delegate API and not natively streaming.
/// To preserve the `parseChunk` / `finish` contract of `KnowledgeGraphParser`
/// without introducing two divergent code paths, we accumulate UTF-8 bytes
/// across `parseChunk` calls and run the whole document through `XMLParser`
/// in `finish`. The delegate (`RDFXMLEventCollector`) flattens callbacks into
/// `[RDFXMLEvent]`, and `RDFXMLGrammar` walks that stream to emit triples.
///
/// Why this layering: RDF/XML semantics (stripe grammar, parseType branches,
/// rdf:ID uniqueness, exclusive C14N for parseType="Literal") are easier to
/// reason about against a linear event stream than against the spray of
/// `XMLParserDelegate` callbacks. Decoupling the XML layer from the RDF
/// layer also lets the grammar be tested without spinning up XMLParser.
public struct RDFXMLParser: KnowledgeGraphParser {

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

    public mutating func finish(
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        if buffer.isEmpty {
            throw ParserError.unexpectedEndOfInput(
                at: .start,
                expected: "RDF/XML document"
            )
        }
        let events = try collectEvents()
        var grammar = RDFXMLGrammar(context: context)
        try grammar.run(events: events, into: &builder)
        context = grammar.context
    }

    // MARK: - XML event collection

    private func collectEvents() throws -> [RDFXMLEvent] {
        let data = Data(buffer)
        let xmlParser = XMLParser(data: data)
        xmlParser.shouldProcessNamespaces = true
        xmlParser.shouldReportNamespacePrefixes = true
        xmlParser.shouldResolveExternalEntities = false
        let collector = RDFXMLEventCollector()
        xmlParser.delegate = collector
        let ok = xmlParser.parse()
        if let error = collector.parseError {
            throw ParserError.xmlSyntax(
                detail: String(describing: error),
                at: xmlPosition(parser: xmlParser)
            )
        }
        if !ok {
            throw ParserError.xmlSyntax(
                detail: "XML parse failed without specific error",
                at: xmlPosition(parser: xmlParser)
            )
        }
        return collector.events
    }

    private func xmlPosition(parser: XMLParser) -> SourcePosition {
        SourcePosition(
            line: max(1, parser.lineNumber),
            column: max(1, parser.columnNumber),
            byteOffset: 0
        )
    }
}
