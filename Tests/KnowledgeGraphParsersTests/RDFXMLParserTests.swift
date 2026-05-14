import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("RDFXMLParser")
struct RDFXMLParserTests {

    // MARK: - Helpers

    private func parse(_ source: String, base: String? = nil) throws -> KnowledgeGraph {
        var context = ParsingContext(blankScopeID: "test")
        if let base {
            context.setBaseIRI(IRI(base))
        }
        var parser = RDFXMLParser(context: context)
        return try parser.parse(source)
    }

    private func edge(in graph: KnowledgeGraph, subject: String, predicate: String) -> Edge? {
        graph.edges.first { $0.id.source.key == subject && $0.id.predicate == predicate }
    }

    private func edges(in graph: KnowledgeGraph, subject: String) -> [Edge] {
        graph.edges.filter { $0.id.source.key == subject }
    }

    // MARK: - Empty / minimal

    @Test("Empty rdf:RDF root emits no triples")
    func emptyRDF() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        </rdf:RDF>
        """
        let graph = try parse(source)
        #expect(graph.edges.isEmpty)
    }

    // MARK: - Simple rdf:about

    @Test("rdf:Description with rdf:about and one property")
    func simpleAbout() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s">
            <ex:p>hello</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        #expect(graph.edges.count == 1)
        let e = try #require(edge(in: graph, subject: "http://example/s", predicate: "http://example/p"))
        #expect(e.id.target.kind == .literal)
        #expect(e.id.target.key.contains("hello"))
    }

    // MARK: - rdf:type from element name

    @Test("Typed node element emits rdf:type triple")
    func typedNode() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <ex:Person rdf:about="http://example/alice">
            <ex:name>Alice</ex:name>
          </ex:Person>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let typeEdge = edge(
            in: graph,
            subject: "http://example/alice",
            predicate: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        )
        #expect(typeEdge?.id.target.key == "http://example/Person")
    }

    // MARK: - rdf:ID and base IRI

    @Test("rdf:ID is resolved relative to base IRI")
    func rdfIDWithBase() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:ID="thing">
            <ex:p>x</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source, base: "http://example/doc")
        let e = try #require(graph.edges.first)
        #expect(e.id.source.key == "http://example/doc#thing")
    }

    @Test("xml:base resets the base IRI for descendants")
    func xmlBase() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/"
                 xml:base="http://override/">
          <rdf:Description rdf:about="x">
            <ex:p>v</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source, base: "http://example/doc")
        let e = try #require(graph.edges.first)
        #expect(e.id.source.key == "http://override/x")
    }

    // MARK: - xml:lang

    @Test("xml:lang attaches a language tag to literal objects")
    func xmlLang() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/"
                 xml:lang="en">
          <rdf:Description rdf:about="http://example/s">
            <ex:p>hello</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let e = try #require(graph.edges.first)
        #expect(e.id.target.key == "\"hello\"@en")
    }

    // MARK: - rdf:datatype

    @Test("rdf:datatype produces a typed literal")
    func typedLiteral() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/"
                 xmlns:xsd="http://www.w3.org/2001/XMLSchema#">
          <rdf:Description rdf:about="http://example/s">
            <ex:age rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">42</ex:age>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let e = try #require(graph.edges.first)
        #expect(e.id.target.key == "\"42\"^^http://www.w3.org/2001/XMLSchema#integer")
    }

    // MARK: - rdf:resource

    @Test("rdf:resource on empty property element produces an IRI object")
    func resourceAttribute() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s">
            <ex:rel rdf:resource="http://example/o"/>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let e = try #require(graph.edges.first)
        #expect(e.id.target.kind == .iri)
        #expect(e.id.target.key == "http://example/o")
    }

    // MARK: - rdf:nodeID

    @Test("rdf:nodeID re-use links the same blank node")
    func nodeIDReuse() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:nodeID="b">
            <ex:p>a</ex:p>
          </rdf:Description>
          <rdf:Description rdf:about="http://example/s">
            <ex:rel rdf:nodeID="b"/>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        // The second triple's object should equal the first triple's subject.
        let pTriple = try #require(edge(in: graph, subject: "test/b", predicate: "http://example/p"))
        _ = pTriple
        let relTriple = try #require(edge(in: graph, subject: "http://example/s", predicate: "http://example/rel"))
        #expect(relTriple.id.target.kind == .blank)
        #expect(relTriple.id.target.key == "test/b")
    }

    // MARK: - parseType="Resource"

    @Test("parseType=\"Resource\" introduces an implicit blank node")
    func parseTypeResource() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s">
            <ex:rel rdf:parseType="Resource">
              <ex:p>v</ex:p>
            </ex:rel>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        #expect(graph.edges.count == 2)
        let rel = try #require(edge(in: graph, subject: "http://example/s", predicate: "http://example/rel"))
        #expect(rel.id.target.kind == .blank)
        let nested = try #require(graph.edges.first { $0.id.predicate == "http://example/p" })
        #expect(nested.id.source == rel.id.target)
        #expect(nested.id.target.kind == .literal)
    }

    // MARK: - parseType="Collection"

    @Test("Empty parseType=\"Collection\" yields rdf:nil")
    func emptyCollection() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s">
            <ex:items rdf:parseType="Collection"/>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let e = try #require(graph.edges.first)
        #expect(e.id.target.key == "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
    }

    @Test("parseType=\"Collection\" produces an rdf:first / rdf:rest chain")
    func collection() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s">
            <ex:items rdf:parseType="Collection">
              <rdf:Description rdf:about="http://example/a"/>
              <rdf:Description rdf:about="http://example/b"/>
            </ex:items>
          </rdf:Description>
        </rdf:RDF>
        """
        let graph = try parse(source)
        // s -> items -> _:c0; _:c0 first a / rest _:c1; _:c1 first b / rest nil
        let items = try #require(edge(in: graph, subject: "http://example/s", predicate: "http://example/items"))
        #expect(items.id.target.kind == .blank)
        let firstEdges = graph.edges.filter { $0.id.predicate == "http://www.w3.org/1999/02/22-rdf-syntax-ns#first" }
        let restEdges = graph.edges.filter { $0.id.predicate == "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest" }
        #expect(firstEdges.count == 2)
        #expect(restEdges.count == 2)
        let nilRest = restEdges.first { $0.id.target.key == "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil" }
        #expect(nilRest != nil)
    }

    // MARK: - rdf:li

    @Test("rdf:li rewrites to rdf:_1, rdf:_2, ...")
    func rdfLi() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Bag rdf:about="http://example/bag">
            <rdf:li>one</rdf:li>
            <rdf:li>two</rdf:li>
          </rdf:Bag>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let predicates = Set(graph.edges.map(\.id.predicate))
        #expect(predicates.contains("http://www.w3.org/1999/02/22-rdf-syntax-ns#_1"))
        #expect(predicates.contains("http://www.w3.org/1999/02/22-rdf-syntax-ns#_2"))
    }

    // MARK: - Property attributes

    @Test("Property attributes on a node element produce additional triples")
    func propertyAttributes() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s" ex:name="Alice"/>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let e = try #require(edge(in: graph, subject: "http://example/s", predicate: "http://example/name"))
        #expect(e.id.target.kind == .literal)
        #expect(e.id.target.key.contains("Alice"))
    }

    // MARK: - rdf:type as attribute

    @Test("rdf:type attribute value is treated as an IRI")
    func rdfTypeAsAttribute() throws {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:about="http://example/s" rdf:type="http://example/T"/>
        </rdf:RDF>
        """
        let graph = try parse(source)
        let e = try #require(edge(
            in: graph,
            subject: "http://example/s",
            predicate: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        ))
        #expect(e.id.target.kind == .iri)
        #expect(e.id.target.key == "http://example/T")
    }

    // MARK: - Negative cases

    @Test("Core syntax term as node element name is rejected")
    func coreTermAsNodeElement() {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:ID rdf:about="http://example/s"/>
        </rdf:RDF>
        """
        #expect(throws: (any Error).self) { _ = try parse(source) }
    }

    @Test("Old aboutEach term triggers a parse error")
    func aboutEachRejected() {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:aboutEach="http://example/s">
            <ex:p>v</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        #expect(throws: (any Error).self) { _ = try parse(source) }
    }

    @Test("Duplicate rdf:ID under the same base is rejected")
    func duplicateID() {
        let source = """
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example/">
          <rdf:Description rdf:ID="x"><ex:p>1</ex:p></rdf:Description>
          <rdf:Description rdf:ID="x"><ex:p>2</ex:p></rdf:Description>
        </rdf:RDF>
        """
        #expect(throws: (any Error).self) { _ = try parse(source, base: "http://example/doc") }
    }
}
