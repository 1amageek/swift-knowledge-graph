import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("W3C TriG test suite")
struct TriGW3CTests {

    // MARK: - Parameterised tests

    @Test("TestTrigEval", arguments: W3CTriGSuite.evalEntries)
    func eval(_ entry: W3CTriGTestEntry) throws {
        guard let expectedURL = entry.expectedURL else {
            Issue.record("Eval test \(entry.name) is missing a result file in the manifest")
            return
        }
        // The isomorphism check reconstructs blank-node identity from named
        // graph keys, so scope IDs must not contain colons (which would make
        // them look like IRIs to that heuristic).
        let actual = try parseTriG(
            url: entry.inputURL,
            base: actionBaseIRI(for: entry),
            scope: "actual_\(entry.name)"
        )
        let expected = try parseNQuads(
            url: expectedURL,
            scope: "expected_\(entry.name)"
        )
        let isomorphic = RDFGraphIsomorphism.areIsomorphic(actual, expected)
        #expect(isomorphic, "Parsed graph is not isomorphic to expected for \(entry.name)")
    }

    @Test("TestTrigPositiveSyntax", arguments: W3CTriGSuite.positiveSyntaxEntries)
    func positiveSyntax(_ entry: W3CTriGTestEntry) throws {
        _ = try parseTriG(
            url: entry.inputURL,
            base: actionBaseIRI(for: entry),
            scope: "pos_\(entry.name)"
        )
    }

    @Test("TestTrigNegativeSyntax", arguments: W3CTriGSuite.negativeSyntaxEntries)
    func negativeSyntax(_ entry: W3CTriGTestEntry) throws {
        #expect(throws: (any Error).self) {
            _ = try parseTriG(
                url: entry.inputURL,
                base: actionBaseIRI(for: entry),
                scope: "neg-syn_\(entry.name)"
            )
        }
    }

    @Test("TestTrigNegativeEval", arguments: W3CTriGSuite.negativeEvalEntries)
    func negativeEval(_ entry: W3CTriGTestEntry) throws {
        #expect(throws: (any Error).self) {
            _ = try parseTriG(
                url: entry.inputURL,
                base: actionBaseIRI(for: entry),
                scope: "neg-eval_\(entry.name)"
            )
        }
    }

    // MARK: - Helpers

    private func actionBaseIRI(for entry: W3CTriGTestEntry) -> String {
        W3CTriGSuite.baseTestIRI + entry.inputURL.lastPathComponent
    }

    private func parseTriG(url: URL, base: String, scope: String) throws -> KnowledgeGraph {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var context = ParsingContext(blankScopeID: scope)
        context.setBaseIRI(IRI(base))
        var parser = TriGParser(context: context)
        return try parser.parse(text)
    }

    private func parseNQuads(url: URL, scope: String) throws -> KnowledgeGraph {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let context = ParsingContext(blankScopeID: scope)
        var parser = NQuadsParser(context: context)
        return try parser.parse(text)
    }
}
