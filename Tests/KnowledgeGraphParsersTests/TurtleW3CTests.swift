import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("W3C Turtle test suite")
struct TurtleW3CTests {

    // MARK: - Parameterised tests

    @Test("TestTurtleEval", arguments: W3CTurtleSuite.evalEntries)
    func eval(_ entry: W3CTurtleTestEntry) throws {
        guard let expectedURL = entry.expectedURL else {
            Issue.record("Eval test \(entry.name) is missing a result file in the manifest")
            return
        }
        let actual = try parse(
            url: entry.inputURL,
            base: actionBaseIRI(for: entry),
            scope: "actual:\(entry.name)"
        )
        let expected = try parse(
            url: expectedURL,
            base: actionBaseIRI(for: entry),
            scope: "expected:\(entry.name)"
        )
        let isomorphic = RDFGraphIsomorphism.areIsomorphic(actual, expected)
        #expect(isomorphic, "Parsed graph is not isomorphic to expected for \(entry.name)")
    }

    @Test("TestTurtlePositiveSyntax", arguments: W3CTurtleSuite.positiveSyntaxEntries)
    func positiveSyntax(_ entry: W3CTurtleTestEntry) throws {
        _ = try parse(
            url: entry.inputURL,
            base: actionBaseIRI(for: entry),
            scope: "pos:\(entry.name)"
        )
    }

    @Test("TestTurtleNegativeSyntax", arguments: W3CTurtleSuite.negativeSyntaxEntries)
    func negativeSyntax(_ entry: W3CTurtleTestEntry) throws {
        #expect(throws: (any Error).self) {
            _ = try parse(
                url: entry.inputURL,
                base: actionBaseIRI(for: entry),
                scope: "neg-syn:\(entry.name)"
            )
        }
    }

    @Test("TestTurtleNegativeEval", arguments: W3CTurtleSuite.negativeEvalEntries)
    func negativeEval(_ entry: W3CTurtleTestEntry) throws {
        #expect(throws: (any Error).self) {
            _ = try parse(
                url: entry.inputURL,
                base: actionBaseIRI(for: entry),
                scope: "neg-eval:\(entry.name)"
            )
        }
    }

    // MARK: - Helpers

    private func actionBaseIRI(for entry: W3CTurtleTestEntry) -> String {
        W3CTurtleSuite.baseTestIRI + entry.inputURL.lastPathComponent
    }

    private func parse(url: URL, base: String, scope: String) throws -> KnowledgeGraph {
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        var context = ParsingContext(blankScopeID: scope)
        context.setBaseIRI(IRI(base))
        var parser = TurtleParser(context: context)
        return try parser.parse(text)
    }
}
