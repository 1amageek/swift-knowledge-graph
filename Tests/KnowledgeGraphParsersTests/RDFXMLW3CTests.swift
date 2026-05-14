import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("W3C RDF/XML test suite")
struct RDFXMLW3CTests {

    // MARK: - Sanity checks

    @Test("Suite loaded a non-zero number of test entries")
    func suiteIsPopulated() {
        let eval = W3CRDFXMLSuite.evalEntries.count
        let neg = W3CRDFXMLSuite.negativeSyntaxEntries.count
        #expect(eval > 0)
        #expect(neg > 0)
        // After commented-out entries are dropped, the manifest holds
        // 122 eval + 40 negative-syntax = 162 cases.
        #expect(eval == 122, "expected 122 eval cases, got \(eval)")
        #expect(neg == 40, "expected 40 negative-syntax cases, got \(neg)")
    }

    /// Smoke test: pick the first eval entry and run it end-to-end. If this
    /// fails, the parameterised `eval` suite would also fail — surfacing the
    /// failure here makes debugging much easier than scrolling through the
    /// parameterised stream.
    @Test("Smoke: first eval entry parses isomorphically")
    func smokeFirstEval() throws {
        guard let entry = W3CRDFXMLSuite.evalEntries.first else {
            Issue.record("no eval entries")
            return
        }
        guard let expectedURL = entry.expectedURL else {
            Issue.record("first eval entry has no expected file")
            return
        }
        let actual = try parseRDFXML(url: entry.inputURL, base: entry.baseIRI, scope: "smoke_actual")
        let expected = try parseNTriples(url: expectedURL, scope: "smoke_expected")
        let isomorphic = RDFGraphIsomorphism.areIsomorphic(actual, expected)
        #expect(isomorphic, "smoke isomorphism failed for \(entry.name)")
    }

    // MARK: - Parameterised tests

    @Test("TestXMLEval", arguments: W3CRDFXMLSuite.evalEntries)
    func eval(_ entry: W3CRDFXMLTestEntry) throws {
        guard let expectedURL = entry.expectedURL else {
            Issue.record("Eval test \(entry.name) is missing a result file in the manifest")
            return
        }
        // The isomorphism check reconstructs blank-node identity from named
        // graph keys, so scope IDs must not contain colons (which would make
        // them look like IRIs to that heuristic).
        let actual = try parseRDFXML(
            url: entry.inputURL,
            base: entry.baseIRI,
            scope: "actual_\(entry.name)"
        )
        let expected = try parseNTriples(
            url: expectedURL,
            scope: "expected_\(entry.name)"
        )
        let isomorphic = RDFGraphIsomorphism.areIsomorphic(actual, expected)
        #expect(isomorphic, "Parsed graph is not isomorphic to expected for \(entry.name)")
    }

    @Test("TestXMLNegativeSyntax", arguments: W3CRDFXMLSuite.negativeSyntaxEntries)
    func negativeSyntax(_ entry: W3CRDFXMLTestEntry) throws {
        #expect(throws: (any Error).self) {
            _ = try parseRDFXML(
                url: entry.inputURL,
                base: entry.baseIRI,
                scope: "neg-syn_\(entry.name)"
            )
        }
    }

    // MARK: - Helpers

    private func parseRDFXML(url: URL, base: String, scope: String) throws -> KnowledgeGraph {
        let data = try Data(contentsOf: url)
        var context = ParsingContext(blankScopeID: scope)
        context.setBaseIRI(IRI(base))
        var parser = RDFXMLParser(context: context)
        var builder = KnowledgeGraphBuilder()
        try parser.parseChunk(ArraySlice(Array(data)), into: &builder)
        try parser.finish(into: &builder)
        return builder.build()
    }

    private func parseNTriples(url: URL, scope: String) throws -> KnowledgeGraph {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let context = ParsingContext(blankScopeID: scope)
        var parser = NQuadsParser(context: context)
        return try parser.parse(text)
    }
}
