import Testing
@testable import KnowledgeGraph

@Suite("NodeIdentifier")
struct NodeIdentifierTests {

    @Test("IRI identifiers are stable across constructions")
    func iriStability() {
        let a = NodeIdentifier.iri("http://example.org/Alice")
        let b = NodeIdentifier.iri("http://example.org/Alice")
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        #expect(a.kind == .iri)
        #expect(a.key == "http://example.org/Alice")
    }

    @Test("Blank identifiers depend on the local label")
    func blankStability() {
        let a = NodeIdentifier.blank("b0")
        let b = NodeIdentifier.blank("b0")
        let c = NodeIdentifier.blank("b1")
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Literal identifiers distinguish qualifier shapes")
    func literalQualifierShapes() {
        let plain = NodeIdentifier.literal(value: "Alice")
        let lang = NodeIdentifier.literal(value: "Alice", language: "en")
        let typed = NodeIdentifier.literal(value: "42", datatype: "http://www.w3.org/2001/XMLSchema#integer")
        #expect(plain != lang)
        #expect(plain != typed)
        #expect(lang != typed)
        #expect(plain.key == "\"Alice\"")
        #expect(lang.key == "\"Alice\"@en")
        #expect(typed.key == "\"42\"^^http://www.w3.org/2001/XMLSchema#integer")
    }

    @Test("Literal language wins over datatype when both are supplied")
    func literalLanguageWins() {
        let id = NodeIdentifier.literal(
            value: "hello",
            datatype: "http://www.w3.org/2001/XMLSchema#string",
            language: "en"
        )
        #expect(id.key == "\"hello\"@en")
    }

    @Test("Different kinds with identical keys are still different identifiers")
    func kindParticipates() {
        let iri = NodeIdentifier(kind: .iri, key: "x")
        let blank = NodeIdentifier(kind: .blank, key: "x")
        #expect(iri != blank)
    }

    @Test("NodeIdentifier is Sendable (compile-time)")
    func sendable() {
        let id: any Sendable = NodeIdentifier.iri("http://example.org/Bob")
        #expect(id is NodeIdentifier)
    }
}
