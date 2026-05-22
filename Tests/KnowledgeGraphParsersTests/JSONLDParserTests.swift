import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD 1.1 hand-written parser tests")
struct JSONLDParserTests {

    // MARK: - Helpers

    private func parse(_ json: String, base: String? = nil, scope: String = "jsonld_test") throws -> KnowledgeGraph {
        var context = ParsingContext(blankScopeID: scope)
        if let base { context.setBaseIRI(IRI(base)) }
        var parser = JSONLDParser(context: context)
        return try parser.parse(json)
    }

    private func collectTriples(_ graph: KnowledgeGraph) -> Set<String> {
        Set(graph.edges.map { "\($0.id.source.key) | \($0.id.predicate) | \($0.id.target.key)" })
    }

    // MARK: - Basic node objects

    @Test("Empty object produces no triples")
    func emptyObject() throws {
        let g = try parse("{}")
        #expect(g.edges.isEmpty)
    }

    @Test("Object with @id only produces no triples (no predicates)")
    func idOnly() throws {
        let g = try parse(#"{"@id": "http://example.org/s"}"#)
        #expect(g.edges.isEmpty)
    }

    @Test("Simple property with absolute IRI key")
    func simpleProperty() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/p": "value"
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/s | http://example.org/p | \"value\""))
    }

    @Test("@type expanded to rdf:type triple")
    func typeAsRdfType() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "@type": "http://example.org/Type"
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        let rdfType = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        #expect(triples.contains("http://example.org/s | \(rdfType) | http://example.org/Type"))
    }

    // MARK: - Context

    @Test("Context maps a term to an IRI")
    func contextTerm() throws {
        let json = #"""
        {
          "@context": {
            "name": "http://example.org/name"
          },
          "@id": "http://example.org/alice",
          "name": "Alice"
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/alice | http://example.org/name | \"Alice\""))
    }

    @Test("Context @vocab applies to undefined terms")
    func contextVocab() throws {
        let json = #"""
        {
          "@context": {"@vocab": "http://example.org/"},
          "@id": "http://example.org/s",
          "p": "v"
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/s | http://example.org/p | \"v\""))
    }

    @Test("Context @base resolves a relative @id")
    func contextBase() throws {
        let json = #"""
        {
          "@context": {
            "@base": "http://example.org/",
            "p": "http://example.org/p"
          },
          "@id": "alice",
          "p": "Alice"
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/alice | http://example.org/p | \"Alice\""))
    }

    // MARK: - Datatypes

    @Test("Integer becomes xsd:integer-typed literal")
    func integerLiteral() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/age": 42
        }
        """#
        let g = try parse(json)
        let xsdInt = "http://www.w3.org/2001/XMLSchema#integer"
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/s | http://example.org/age | \"42\"^^\(xsdInt)"))
    }

    @Test("Boolean becomes xsd:boolean-typed literal")
    func booleanLiteral() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/active": true
        }
        """#
        let g = try parse(json)
        let xsdBool = "http://www.w3.org/2001/XMLSchema#boolean"
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/s | http://example.org/active | \"true\"^^\(xsdBool)"))
    }

    @Test("Double becomes xsd:double-typed literal")
    func doubleLiteral() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/pi": 3.14
        }
        """#
        let g = try parse(json)
        let xsdDouble = "http://www.w3.org/2001/XMLSchema#double"
        let edge = g.edges.first { $0.id.predicate == "http://example.org/pi" }
        #expect(edge != nil)
        if let edge {
            #expect(edge.id.target.key.contains("^^\(xsdDouble)"))
        }
    }

    @Test("Language-tagged value via context")
    func languageTagged() throws {
        let json = #"""
        {
          "@context": {"name": {"@id": "http://example.org/name", "@language": "en"}},
          "@id": "http://example.org/s",
          "name": "Alice"
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/s | http://example.org/name | \"Alice\"@en"))
    }

    @Test("Explicit typed value object")
    func typedValueObject() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/date": {"@value": "2024-01-01", "@type": "http://www.w3.org/2001/XMLSchema#date"}
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        let xsdDate = "http://www.w3.org/2001/XMLSchema#date"
        #expect(triples.contains("http://example.org/s | http://example.org/date | \"2024-01-01\"^^\(xsdDate)"))
    }

    // MARK: - Object reference

    @Test("Nested node object as predicate value")
    func nestedNode() throws {
        let json = #"""
        {
          "@id": "http://example.org/alice",
          "http://example.org/knows": {
            "@id": "http://example.org/bob",
            "http://example.org/name": "Bob"
          }
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/alice | http://example.org/knows | http://example.org/bob"))
        #expect(triples.contains("http://example.org/bob | http://example.org/name | \"Bob\""))
    }

    @Test("Anonymous nested node receives a blank-node id")
    func anonymousNested() throws {
        let json = #"""
        {
          "@id": "http://example.org/alice",
          "http://example.org/knows": {"http://example.org/name": "Bob"}
        }
        """#
        let g = try parse(json)
        let knows = g.edges.first { $0.id.predicate == "http://example.org/knows" }
        #expect(knows != nil)
        if let knows {
            #expect(knows.id.target.kind == .blank)
        }
    }

    // MARK: - Lists

    @Test("@list value object emits rdf:first/rdf:rest chain")
    func listChain() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/items": {"@list": ["a", "b"]}
        }
        """#
        let g = try parse(json)
        let rdfFirst = "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
        let rdfRest  = "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
        let rdfNil   = "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"
        let firsts = g.edges.filter { $0.id.predicate == rdfFirst }
        let rests  = g.edges.filter { $0.id.predicate == rdfRest }
        #expect(firsts.count == 2)
        #expect(rests.count == 2)
        // One rest must point to rdf:nil.
        #expect(rests.contains { $0.id.target.key == rdfNil })
    }

    @Test("Empty @list maps to rdf:nil")
    func emptyList() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/items": {"@list": []}
        }
        """#
        let g = try parse(json)
        let rdfNil = "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/s | http://example.org/items | \(rdfNil)"))
    }

    // MARK: - Arrays / @set

    @Test("Array values become multiple triples")
    func arrayValues() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/p": ["a", "b"]
        }
        """#
        let g = try parse(json)
        let pEdges = g.edges.filter { $0.id.predicate == "http://example.org/p" }
        #expect(pEdges.count == 2)
    }

    @Test("@set wrapper is transparent")
    func setWrapper() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/p": {"@set": ["a", "b"]}
        }
        """#
        let g = try parse(json)
        let pEdges = g.edges.filter { $0.id.predicate == "http://example.org/p" }
        #expect(pEdges.count == 2)
    }

    // MARK: - Compact IRI

    @Test("CURIE-style prefix expansion")
    func curiePrefix() throws {
        let json = #"""
        {
          "@context": {"ex": "http://example.org/"},
          "@id": "ex:alice",
          "ex:name": "Alice"
        }
        """#
        let g = try parse(json, base: "http://base.example/")
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/alice | http://example.org/name | \"Alice\""))
    }

    // MARK: - @graph

    @Test("Top-level @graph emits triples in the default graph")
    func topLevelGraph() throws {
        let json = #"""
        {
          "@graph": [
            {"@id": "http://example.org/a", "http://example.org/p": "x"},
            {"@id": "http://example.org/b", "http://example.org/p": "y"}
          ]
        }
        """#
        let g = try parse(json)
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/a | http://example.org/p | \"x\""))
        #expect(triples.contains("http://example.org/b | http://example.org/p | \"y\""))
    }

    @Test("Named @graph creates a NamedGraph entry")
    func namedGraph() throws {
        let json = #"""
        {
          "@id": "http://example.org/g1",
          "@graph": [
            {"@id": "http://example.org/s", "http://example.org/p": "v"}
          ]
        }
        """#
        let g = try parse(json)
        #expect(g.namedGraphs.contains { $0.id == "http://example.org/g1" })
        let edge = g.edges.first { $0.id.predicate == "http://example.org/p" }
        #expect(edge?.id.namedGraph == "http://example.org/g1")
    }

    @Test("Named @graph uses graph-name title as NamedGraph label")
    func namedGraphLabelFromTitle() throws {
        let json = #"""
        {
          "@context": {
            "title": "https://schema.org/name"
          },
          "@id": "http://example.org/g1",
          "title": "Context",
          "@graph": [
            {"@id": "http://example.org/s", "http://example.org/p": "v"}
          ]
        }
        """#
        let g = try parse(json)
        let named = try #require(g.namedGraphs.first { $0.id == "http://example.org/g1" })
        #expect(named.label == "Context")
        let triples = collectTriples(g)
        #expect(triples.contains("http://example.org/g1 | https://schema.org/name | \"Context\""))
    }

    // MARK: - Negative cases

    @Test("Malformed JSON throws ParserError.jsonSyntax")
    func malformedJSON() {
        #expect(throws: ParserError.self) {
            _ = try parse(#"{"@id":}"#)
        }
    }

    @Test("Empty buffer throws unexpectedEndOfInput")
    func emptyBuffer() {
        #expect(throws: ParserError.self) {
            _ = try parse("")
        }
    }

    @Test("Remote @context (string form) throws unsupportedFeature")
    func remoteContextRejected() {
        let json = #"""
        {
          "@context": "http://example.org/ctx",
          "@id": "http://example.org/s"
        }
        """#
        #expect(throws: ParserError.self) {
            _ = try parse(json)
        }
    }

    // MARK: - Blank scope isolation (condition 11)

    @Test("Two parser instances do not share blank node ids")
    func blankScopeIsolation() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/p": {"http://example.org/q": "x"}
        }
        """#
        let a = try parse(json, scope: "scope_a")
        let b = try parse(json, scope: "scope_b")
        let blankA = a.edges
            .first { $0.id.predicate == "http://example.org/p" }!
            .id.target
        let blankB = b.edges
            .first { $0.id.predicate == "http://example.org/p" }!
            .id.target
        #expect(blankA.kind == .blank)
        #expect(blankB.kind == .blank)
        #expect(blankA != blankB, "Blank nodes from different scopes must not collide")
    }
}
