import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("TriGParser")
struct TriGParserTests {

    // MARK: - Helpers

    private func parse(_ source: String, base: String? = nil) throws -> KnowledgeGraph {
        var context = ParsingContext(blankScopeID: "test")
        if let base {
            context.setBaseIRI(IRI(base))
        }
        var parser = TriGParser(context: context)
        return try parser.parse(source)
    }

    private func defaultGraphEdges(in graph: KnowledgeGraph) -> [Edge] {
        graph.edges.filter { $0.id.namedGraph == nil }
    }

    private func edges(in graph: KnowledgeGraph, namedGraph: String) -> [Edge] {
        graph.edges.filter { $0.id.namedGraph == namedGraph }
    }

    // MARK: - Top-level forms

    @Test("Bare triple — no graph block — lands in default graph")
    func bareTripleInDefaultGraph() throws {
        let source = "<http://a.example/s> <http://a.example/p> <http://a.example/o> ."
        let graph = try parse(source)
        let edges = defaultGraphEdges(in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].id.namedGraph == nil)
    }

    @Test("Wrapped graph without label — default graph")
    func wrappedGraphWithoutLabel() throws {
        let source = "{ <http://a.example/s> <http://a.example/p> <http://a.example/o> . }"
        let graph = try parse(source)
        let edges = defaultGraphEdges(in: graph)
        #expect(edges.count == 1)
    }

    @Test("Named IRI graph block")
    func iriNamedGraph() throws {
        let source = """
        <http://example/g> {
          <http://a.example/s> <http://a.example/p> <http://a.example/o> .
        }
        """
        let graph = try parse(source)
        let inG = edges(in: graph, namedGraph: "http://example/g")
        #expect(inG.count == 1)
        #expect(graph.namedGraphs.contains(where: { $0.id == "http://example/g" }))
    }

    @Test("GRAPH keyword introduces a named graph")
    func graphKeywordBlock() throws {
        let source = """
        GRAPH <http://example/g> {
          <http://a.example/s> <http://a.example/p> <http://a.example/o> .
        }
        """
        let graph = try parse(source)
        let inG = edges(in: graph, namedGraph: "http://example/g")
        #expect(inG.count == 1)
    }

    @Test("Anonymous blank node graph label — [] { ... }")
    func anonymousBlankNodeGraph() throws {
        let source = "[] { <http://a.example/s> <http://a.example/p> <http://a.example/o> . }"
        let graph = try parse(source)
        #expect(graph.edges.count == 1)
        let edge = graph.edges[0]
        #expect(edge.id.namedGraph != nil)
        // The label is a fresh blank, scoped under "test".
        #expect(edge.id.namedGraph?.hasPrefix("test/") == true)
    }

    @Test("Labeled blank node graph — _:g { ... } — same label re-used keeps graph identity")
    func labeledBlankNodeGraphReuse() throws {
        let source = """
        @prefix : <http://example/> .
        _:g { :a :b :c . }
        _:g { :a :b :d . }
        """
        let graph = try parse(source)
        let inG = graph.edges.filter { $0.id.namedGraph != nil }
        // Both triples should land in the SAME named graph.
        let labels = Set(inG.compactMap { $0.id.namedGraph })
        #expect(inG.count == 2)
        #expect(labels.count == 1)
    }

    @Test("Default graph and named graph coexist in one document")
    func defaultAndNamedCoexist() throws {
        let source = """
        @prefix : <http://example/> .
        :a :b :c .
        :G { :d :e :f . }
        """
        let graph = try parse(source)
        let defaultEdges = defaultGraphEdges(in: graph)
        let named = edges(in: graph, namedGraph: "http://example/G")
        #expect(defaultEdges.count == 1)
        #expect(named.count == 1)
    }

    // MARK: - Inside a graph block

    @Test("Trailing dot before '}' is optional")
    func optionalTrailingDot() throws {
        let withoutDot = "{ <http://a.example/s> <http://a.example/p> <http://a.example/o> }"
        let withDot = "{ <http://a.example/s> <http://a.example/p> <http://a.example/o> . }"
        let a = try parse(withoutDot)
        let b = try parse(withDot)
        #expect(a.edges.count == 1)
        #expect(b.edges.count == 1)
    }

    @Test("Multiple triples separated by '.' inside a wrapped graph")
    func multipleTriplesInsideGraph() throws {
        let source = """
        @prefix : <http://example/> .
        :G {
          :a :p :b .
          :c :p :d .
          :e :p :f
        }
        """
        let graph = try parse(source)
        let inG = edges(in: graph, namedGraph: "http://example/G")
        #expect(inG.count == 3)
    }

    @Test("Predicate-object lists and object lists inside a graph block")
    func nestedListsInsideGraph() throws {
        let source = """
        @prefix : <http://example/> .
        :G { :a :p :b , :c ; :q :d . }
        """
        let graph = try parse(source)
        let inG = edges(in: graph, namedGraph: "http://example/G")
        #expect(inG.count == 3)
    }

    // MARK: - Directives

    @Test("@prefix declared before a named graph block")
    func prefixBeforeNamedGraph() throws {
        let source = """
        @prefix : <http://example/> .
        :G { :a :p :b . }
        """
        let graph = try parse(source)
        let inG = edges(in: graph, namedGraph: "http://example/G")
        #expect(inG.count == 1)
        #expect(inG[0].id.source.key == "http://example/a")
    }

    @Test("SPARQL-style PREFIX / BASE keywords accepted at the top level")
    func sparqlStyleDirectives() throws {
        let source = """
        BASE <http://example/>
        PREFIX : <http://example/>
        :G { :a :p :b . }
        """
        let graph = try parse(source)
        let inG = edges(in: graph, namedGraph: "http://example/G")
        #expect(inG.count == 1)
    }

    // MARK: - Negative cases

    @Test("Missing '}' is an error")
    func missingCloseBrace() {
        let source = "{ <http://a.example/s> <http://a.example/p> <http://a.example/o> ."
        #expect(throws: (any Error).self) {
            _ = try parse(source)
        }
    }

    @Test("Bare graph label without block or predicate-object list is an error")
    func bareLabelWithoutBlock() {
        let source = "<http://example/g>"
        #expect(throws: (any Error).self) {
            _ = try parse(source)
        }
    }

    @Test("GRAPH keyword followed by a non-label token is an error")
    func graphKeywordWithoutLabel() {
        let source = "GRAPH { <http://a.example/s> <http://a.example/p> <http://a.example/o> . }"
        #expect(throws: (any Error).self) {
            _ = try parse(source)
        }
    }
}
