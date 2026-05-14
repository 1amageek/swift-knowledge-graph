import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("Blank-node scope isolation (condition 11)")
struct BlankScopeTests {

    private func parseTurtle(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = TurtleParser(context: context)
        return try parser.parse(text)
    }

    private func parseTriG(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = TriGParser(context: context)
        return try parser.parse(text)
    }

    private func parseRDFXML(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = RDFXMLParser(context: context)
        var builder = KnowledgeGraphBuilder()
        try parser.parseAll(text, into: &builder)
        return builder.build()
    }

    private func parseJSONLD(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = JSONLDParser(context: context)
        return try parser.parse(text)
    }

    private func blanks(_ graph: KnowledgeGraph) -> Set<String> {
        var set: Set<String> = []
        for edge in graph.edges {
            if edge.id.source.kind == .blank { set.insert(edge.id.source.key) }
            if edge.id.target.kind == .blank { set.insert(edge.id.target.key) }
        }
        return set
    }

    @Test("Turtle: two scopes for the same input produce disjoint blank ids")
    func turtleDisjointScopes() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        _:a ex:p _:b .
        _:a ex:q "x" .
        """
        let a = try parseTurtle(text, scope: "scope_alpha")
        let b = try parseTurtle(text, scope: "scope_beta")
        let blanksA = blanks(a)
        let blanksB = blanks(b)
        #expect(!blanksA.isEmpty)
        #expect(!blanksB.isEmpty)
        #expect(blanksA.intersection(blanksB).isEmpty,
                "Different scopes must produce disjoint blank labels — found overlap: \(blanksA.intersection(blanksB))")
    }

    @Test("Turtle: same scope produces identical blank ids (warm-restart precondition)")
    func turtleSameScopeStable() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        _:a ex:p _:b .
        _:a ex:q "x" .
        _:b ex:r _:a .
        """
        let a = try parseTurtle(text, scope: "scope_stable")
        let b = try parseTurtle(text, scope: "scope_stable")
        // Comparing only the set of blank-label strings is too weak: it
        // passes even when `_:a` is mapped to a different target on the
        // second parse, so long as the *set* of labels is unchanged.
        // The warm-restart contract requires every edge — including its
        // subject, predicate, target, and named-graph — to land in the same
        // identifier. Compare the full edge-identifier sets to verify the
        // entire mapping is stable, not just the label population.
        let edgesA = Set(a.edges.map { $0.id })
        let edgesB = Set(b.edges.map { $0.id })
        #expect(!edgesA.isEmpty)
        #expect(edgesA == edgesB,
                "Same-scope reparse must produce identical EdgeIdentifier sets — \(edgesA.symmetricDifference(edgesB)) differ")
    }

    @Test("TriG: scope isolation holds across named graphs")
    func trigDisjointScopes() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        ex:g1 { _:a ex:p "x" . }
        ex:g2 { _:a ex:q "y" . }
        """
        let a = try parseTriG(text, scope: "trig_alpha")
        let b = try parseTriG(text, scope: "trig_beta")
        #expect(blanks(a).intersection(blanks(b)).isEmpty)
    }

    @Test("RDF/XML: scope isolation holds for nodeID")
    func rdfxmlDisjointScopes() throws {
        let xml = """
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example.org/">
          <rdf:Description rdf:nodeID="x">
            <ex:p>v</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        let a = try parseRDFXML(xml, scope: "rdfxml_alpha")
        let b = try parseRDFXML(xml, scope: "rdfxml_beta")
        #expect(!blanks(a).isEmpty)
        #expect(blanks(a).intersection(blanks(b)).isEmpty)
    }

    @Test("JSON-LD: scope isolation holds for anonymous blank nodes")
    func jsonldDisjointScopes() throws {
        let json = #"""
        {
          "@id": "http://example.org/s",
          "http://example.org/p": {"http://example.org/q": "x"}
        }
        """#
        let a = try parseJSONLD(json, scope: "jsonld_alpha")
        let b = try parseJSONLD(json, scope: "jsonld_beta")
        #expect(!blanks(a).isEmpty)
        #expect(blanks(a).intersection(blanks(b)).isEmpty)
    }
}
