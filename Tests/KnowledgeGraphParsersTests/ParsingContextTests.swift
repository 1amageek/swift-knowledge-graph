import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("ParsingContext")
struct ParsingContextTests {

    // MARK: - Prefix / base resolution

    @Test("Absolute reference resolves regardless of base")
    func absoluteReferenceWithoutBase() throws {
        let context = ParsingContext()
        let iri = try context.resolveIRIReference("http://example.org/Alice", at: .start)
        #expect(iri.value == "http://example.org/Alice")
    }

    @Test("Relative reference without base throws .noBaseIRI")
    func relativeReferenceWithoutBaseThrows() {
        let context = ParsingContext()
        #expect(throws: ParserError.noBaseIRI(at: .start)) {
            _ = try context.resolveIRIReference("relative", at: .start)
        }
    }

    @Test("Relative reference uses declared base")
    func relativeReferenceUsesBase() throws {
        var context = ParsingContext()
        context.setBaseIRI(IRI("http://example.org/base/"))
        let iri = try context.resolveIRIReference("Alice", at: .start)
        #expect(iri.value == "http://example.org/base/Alice")
    }

    @Test("Undefined prefix throws .undefinedPrefix")
    func undefinedPrefixThrows() {
        let context = ParsingContext()
        #expect(throws: ParserError.undefinedPrefix(prefix: "foaf", at: .start)) {
            _ = try context.resolveCURIE(prefix: "foaf", suffix: "name", at: .start)
        }
    }

    @Test("CURIE resolves through declared prefix")
    func curieResolves() throws {
        var context = ParsingContext()
        context.declarePrefix("foaf", iri: IRI("http://xmlns.com/foaf/0.1/"))
        let iri = try context.resolveCURIE(prefix: "foaf", suffix: "name", at: .start)
        #expect(iri.value == "http://xmlns.com/foaf/0.1/name")
    }

    // MARK: - Blank node scoping

    @Test("Same blank label in the same context maps to the same identifier")
    func blankLabelMemoised() {
        var context = ParsingContext(blankScopeID: "fixed")
        let first = context.blankNode(forLabel: "b0")
        let second = context.blankNode(forLabel: "b0")
        #expect(first == second)
    }

    @Test("Different contexts produce different identifiers for the same blank label")
    func blankScopeIsolation() {
        var alpha = ParsingContext(blankScopeID: "alpha")
        var beta = ParsingContext(blankScopeID: "beta")
        let inAlpha = alpha.blankNode(forLabel: "b0")
        let inBeta = beta.blankNode(forLabel: "b0")
        #expect(inAlpha != inBeta)
    }

    @Test("Fresh blank nodes are unique within a context")
    func freshBlankUniqueness() {
        var context = ParsingContext(blankScopeID: "scope")
        let a = context.freshBlankNode()
        let b = context.freshBlankNode()
        #expect(a != b)
    }

    @Test("Identical scope id reproduces blank identifiers (warm-restart)")
    func blankReplayStable() {
        var first = ParsingContext(blankScopeID: "fixed")
        var second = ParsingContext(blankScopeID: "fixed")
        let one = first.blankNode(forLabel: "x")
        let two = second.blankNode(forLabel: "x")
        #expect(one == two)
    }
}
