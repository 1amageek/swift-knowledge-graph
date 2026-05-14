import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("Warm-restart: snapshot prefix stability (condition 14)")
struct WarmRestartTests {

    // MARK: - Turtle

    @Test("Turtle: re-parsing a longer prefix preserves the previous snapshot's edges")
    func turtleWarmRestart() throws {
        let firstHalf = """
        @prefix ex: <http://example.org/> .
        ex:s1 ex:p "v1" .
        ex:s2 ex:p "v2" .
        """
        let extended = firstHalf + "\nex:s3 ex:p \"v3\" .\nex:s4 ex:p \"v4\" .\n"

        var parserA = TurtleParser(context: ParsingContext(blankScopeID: "warm"))
        var parserB = TurtleParser(context: ParsingContext(blankScopeID: "warm"))

        let graphA = try parserA.parse(firstHalf)
        let graphB = try parserB.parse(extended)
        // Every edge from the first parse must still exist in the second.
        let setA = Set(graphA.edges.map(\.id))
        let setB = Set(graphB.edges.map(\.id))
        #expect(setA.isSubset(of: setB),
                "Warm-restart violation: \(setA.subtracting(setB)) was lost")
        #expect(setB.count > setA.count)
    }

    @Test("Turtle: incremental parseChunk on the same instance matches one-shot parse")
    func turtleIncrementalSingleInstance() throws {
        // Comparing two separate parser instances only proves that
        // identifiers are deterministic for the same scope. The streaming
        // contract is stronger: a single parser instance that receives the
        // document in pieces — interleaved at arbitrary byte offsets,
        // including mid-token boundaries — must converge on the same edge
        // set as a one-shot parseAll. This test exercises that promise on
        // one instance.
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s1 ex:p "v1" .
        ex:s2 ex:p _:b .
        _:b ex:q "v2" .
        ex:s3 ex:r "v3"@en .
        """
        let bytes = Array(text.utf8)

        var oneShot = TurtleParser(context: ParsingContext(blankScopeID: "incr"))
        var oneShotBuilder = KnowledgeGraphBuilder()
        try oneShot.parseAll(bytes, into: &oneShotBuilder)
        let oneShotEdges = Set(oneShotBuilder.build().edges.map(\.id))

        // Feed the same instance in irregular slices that intentionally
        // split tokens (the boundary after the `@`, mid-IRI, mid-literal).
        var incremental = TurtleParser(context: ParsingContext(blankScopeID: "incr"))
        var incrementalBuilder = KnowledgeGraphBuilder()
        let cutpoints = [1, 5, 12, 17, 30, 45, 60, 80, 95, bytes.count]
        var previous = 0
        for cut in cutpoints {
            let next = min(cut, bytes.count)
            if next <= previous { continue }
            try incremental.parseChunk(bytes[previous..<next], into: &incrementalBuilder)
            previous = next
        }
        if previous < bytes.count {
            try incremental.parseChunk(bytes[previous..<bytes.count], into: &incrementalBuilder)
        }
        try incremental.finish(into: &incrementalBuilder)
        let incrementalEdges = Set(incrementalBuilder.build().edges.map(\.id))

        #expect(!oneShotEdges.isEmpty)
        #expect(oneShotEdges == incrementalEdges,
                "Incremental stream and one-shot diverged at: \(oneShotEdges.symmetricDifference(incrementalEdges))")
    }

    @Test("Turtle: blank labels are stable across re-parse with same scope")
    func turtleBlankStable() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        _:a ex:knows _:b .
        """
        var parserA = TurtleParser(context: ParsingContext(blankScopeID: "blank-warm"))
        var parserB = TurtleParser(context: ParsingContext(blankScopeID: "blank-warm"))
        let a = try parserA.parse(text)
        let b = try parserB.parse(text)
        #expect(Set(a.edges.map(\.id)) == Set(b.edges.map(\.id)))
    }

    // MARK: - TriG

    @Test("TriG: re-parsing a longer prefix preserves named-graph edges")
    func trigWarmRestart() throws {
        let firstHalf = """
        @prefix ex: <http://example.org/> .
        ex:g1 {
            ex:s1 ex:p "v1" .
        }
        """
        let extended = firstHalf + """

        ex:g2 {
            ex:s2 ex:p "v2" .
        }
        """
        var pA = TriGParser(context: ParsingContext(blankScopeID: "trig-warm"))
        var pB = TriGParser(context: ParsingContext(blankScopeID: "trig-warm"))
        let a = try pA.parse(firstHalf)
        let b = try pB.parse(extended)
        let setA = Set(a.edges.map(\.id))
        let setB = Set(b.edges.map(\.id))
        #expect(setA.isSubset(of: setB))
    }

    // MARK: - JSON-LD

    @Test("JSON-LD: same payload + same scope produces identical edge identifiers")
    func jsonldStable() throws {
        let json = #"""
        {
          "@context": {"@vocab": "http://example.org/"},
          "@id": "http://example.org/s",
          "p": "v",
          "nested": {"q": "x"}
        }
        """#
        var pA = JSONLDParser(context: ParsingContext(blankScopeID: "jsonld-warm"))
        var pB = JSONLDParser(context: ParsingContext(blankScopeID: "jsonld-warm"))
        let a = try pA.parse(json)
        let b = try pB.parse(json)
        #expect(Set(a.edges.map(\.id)) == Set(b.edges.map(\.id)))
    }

    // MARK: - RDF/XML

    @Test("RDF/XML: same payload + same scope produces identical edge identifiers")
    func rdfxmlStable() throws {
        let xml = """
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
                 xmlns:ex="http://example.org/">
          <rdf:Description rdf:about="http://example.org/s">
            <ex:p>v</ex:p>
          </rdf:Description>
        </rdf:RDF>
        """
        var pA = RDFXMLParser(context: ParsingContext(blankScopeID: "xml-warm"))
        var pB = RDFXMLParser(context: ParsingContext(blankScopeID: "xml-warm"))
        var bA = KnowledgeGraphBuilder()
        var bB = KnowledgeGraphBuilder()
        try pA.parseAll(xml, into: &bA)
        try pB.parseAll(xml, into: &bB)
        let a = bA.build()
        let b = bB.build()
        #expect(Set(a.edges.map(\.id)) == Set(b.edges.map(\.id)))
    }
}
