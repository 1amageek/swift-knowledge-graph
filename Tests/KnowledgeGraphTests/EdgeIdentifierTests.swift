import Testing
@testable import KnowledgeGraph

@Suite("EdgeIdentifier")
struct EdgeIdentifierTests {

    @Test("Same triple components produce equal identifiers")
    func sameTripleEqual() {
        let a = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://xmlns.com/foaf/0.1/knows",
            target: .iri("http://example.org/Bob")
        )
        let b = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://xmlns.com/foaf/0.1/knows",
            target: .iri("http://example.org/Bob")
        )
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("Different predicates yield different identifiers")
    func predicateParticipates() {
        let knows = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://xmlns.com/foaf/0.1/knows",
            target: .iri("http://example.org/Bob")
        )
        let likes = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://example.org/likes",
            target: .iri("http://example.org/Bob")
        )
        #expect(knows != likes)
    }

    @Test("Named graph participates in identity")
    func namedGraphParticipates() {
        let inDefault = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://example.org/knows",
            target: .iri("http://example.org/Bob"),
            namedGraph: nil
        )
        let inG = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://example.org/knows",
            target: .iri("http://example.org/Bob"),
            namedGraph: "http://example.org/g1"
        )
        #expect(inDefault != inG)
    }

    @Test("Direction matters: subject↔object swap is a different edge")
    func directionMatters() {
        let forward = EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://example.org/knows",
            target: .iri("http://example.org/Bob")
        )
        let reverse = EdgeIdentifier(
            source: .iri("http://example.org/Bob"),
            predicate: "http://example.org/knows",
            target: .iri("http://example.org/Alice")
        )
        #expect(forward != reverse)
    }
}
