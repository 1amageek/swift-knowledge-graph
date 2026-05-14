import Testing
@testable import KnowledgeGraph

@Suite("KnowledgeGraphBuilder")
struct KnowledgeGraphBuilderTests {

    // MARK: - Basic insertion

    @Test("insertNode preserves insertion order")
    func insertionOrderForNodes() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNode(Node(id: .iri("http://example.org/A")))
        try builder.insertNode(Node(id: .iri("http://example.org/B")))
        try builder.insertNode(Node(id: .iri("http://example.org/C")))
        let snapshot = builder.build()
        #expect(snapshot.nodes.map(\.id) == [
            .iri("http://example.org/A"),
            .iri("http://example.org/B"),
            .iri("http://example.org/C"),
        ])
    }

    @Test("insertEdge auto-creates subject and object nodes")
    func autoCreateEndpointsForEdge() throws {
        var builder = KnowledgeGraphBuilder()
        let edge = Edge(id: EdgeIdentifier(
            source: .iri("http://example.org/Alice"),
            predicate: "http://example.org/knows",
            target: .iri("http://example.org/Bob")
        ))
        try builder.insertEdge(edge)
        let snapshot = builder.build()
        #expect(snapshot.nodes.count == 2)
        #expect(snapshot.nodes.map(\.id) == [
            .iri("http://example.org/Alice"),
            .iri("http://example.org/Bob"),
        ])
        #expect(snapshot.edges.count == 1)
    }

    @Test("insertTriple convenience produces the same edge identifier")
    func insertTripleEquivalence() throws {
        var direct = KnowledgeGraphBuilder()
        var viaTriple = KnowledgeGraphBuilder()
        let id = try direct.insertEdge(Edge(id: EdgeIdentifier(
            source: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            target: .iri("http://example.org/B")
        )))
        let other = try viaTriple.insertTriple(
            subject: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            object: .iri("http://example.org/B")
        )
        #expect(id == other)
    }

    // MARK: - Idempotency

    @Test("Inserting the same node twice does not produce a duplicate")
    func nodeIdempotency() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNode(Node(id: .iri("http://example.org/A"), label: "first"))
        try builder.insertNode(Node(id: .iri("http://example.org/A"), label: "second"))
        let snapshot = builder.build()
        #expect(snapshot.nodes.count == 1)
        // First-wins merge: the earlier label sticks.
        #expect(snapshot.nodes[0].label == "first")
    }

    @Test("Inserting the same triple twice does not produce a duplicate edge")
    func edgeIdempotency() throws {
        var builder = KnowledgeGraphBuilder()
        let edge = Edge(id: EdgeIdentifier(
            source: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            target: .iri("http://example.org/B")
        ))
        try builder.insertEdge(edge)
        try builder.insertEdge(edge)
        let snapshot = builder.build()
        #expect(snapshot.edges.count == 1)
    }

    @Test("First-wins merge unions types and fills missing fields")
    func mergePolicy() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNode(Node(
            id: .iri("http://example.org/A"),
            label: "Alice",
            types: ["http://xmlns.com/foaf/0.1/Person"]
        ))
        try builder.insertNode(Node(
            id: .iri("http://example.org/A"),
            label: "ALIAS",
            types: ["http://schema.org/Person"],
            attributes: [Attribute(key: "color", value: "blue")]
        ))
        let snapshot = builder.build()
        let node = try #require(snapshot.node(with: .iri("http://example.org/A")))
        #expect(node.label == "Alice")
        #expect(node.types == [
            "http://xmlns.com/foaf/0.1/Person",
            "http://schema.org/Person",
        ])
        #expect(node.attributes == [Attribute(key: "color", value: "blue")])
    }

    // MARK: - Stability across re-parses

    @Test("Re-parsing the same payload produces equal snapshots")
    func snapshotStability() throws {
        func parse() throws -> KnowledgeGraph {
            var b = KnowledgeGraphBuilder()
            try b.insertTriple(
                subject: .iri("http://example.org/Alice"),
                predicate: "http://xmlns.com/foaf/0.1/knows",
                object: .iri("http://example.org/Bob")
            )
            try b.insertTriple(
                subject: .iri("http://example.org/Bob"),
                predicate: "http://xmlns.com/foaf/0.1/age",
                object: .literal(value: "42", datatype: "http://www.w3.org/2001/XMLSchema#integer")
            )
            return b.build()
        }
        let first = try parse()
        let second = try parse()
        #expect(first == second)
    }

    @Test("Streaming prefix snapshots are stable for already-seen elements")
    func warmRestartPrefix() throws {
        var b = KnowledgeGraphBuilder()
        try b.insertTriple(
            subject: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            object: .iri("http://example.org/B")
        )
        let earlier = b.build()
        try b.insertTriple(
            subject: .iri("http://example.org/B"),
            predicate: "http://example.org/p",
            object: .iri("http://example.org/C")
        )
        let later = b.build()
        // Identifiers seen in `earlier` must appear with the same index in
        // `later`: this is what lets a layout engine warm-restart.
        for (offset, node) in earlier.nodes.enumerated() {
            #expect(later.nodes[offset].id == node.id)
        }
        for (offset, edge) in earlier.edges.enumerated() {
            #expect(later.edges[offset].id == edge.id)
        }
    }

    // MARK: - Validation

    @Test("Empty IRI is rejected")
    func rejectEmptyIRI() {
        var builder = KnowledgeGraphBuilder()
        #expect(throws: KnowledgeGraphError.emptyIRI) {
            try builder.insertNode(Node(id: .iri("")))
        }
    }

    @Test("Empty blank label is rejected")
    func rejectEmptyBlankLabel() {
        var builder = KnowledgeGraphBuilder()
        #expect(throws: KnowledgeGraphError.emptyBlankLabel) {
            try builder.insertNode(Node(id: .blank("")))
        }
    }

    @Test("Empty predicate IRI is rejected on edge insert")
    func rejectEmptyPredicate() {
        var builder = KnowledgeGraphBuilder()
        #expect(throws: KnowledgeGraphError.emptyPredicate) {
            try builder.insertEdge(Edge(id: EdgeIdentifier(
                source: .iri("http://example.org/A"),
                predicate: "",
                target: .iri("http://example.org/B")
            )))
        }
    }

    // MARK: - Namespaces

    @Test("Namespace idempotency: identical re-insertion is a no-op")
    func namespaceIdempotency() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNamespace(Namespace(prefix: "foaf", uri: "http://xmlns.com/foaf/0.1/"))
        try builder.insertNamespace(Namespace(prefix: "foaf", uri: "http://xmlns.com/foaf/0.1/"))
        let snapshot = builder.build()
        #expect(snapshot.namespaces.count == 1)
    }

    @Test("Conflicting namespace URI for the same prefix raises")
    func namespacePrefixConflict() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNamespace(Namespace(prefix: "ex", uri: "http://example.org/v1#"))
        #expect(throws: KnowledgeGraphError.self) {
            try builder.insertNamespace(Namespace(prefix: "ex", uri: "http://example.org/v2#"))
        }
    }

    @Test("Empty namespace prefix or URI raises")
    func namespaceEmptyFieldsRejected() {
        var builder = KnowledgeGraphBuilder()
        #expect(throws: KnowledgeGraphError.emptyNamespacePrefix) {
            try builder.insertNamespace(Namespace(prefix: "", uri: "http://example.org/"))
        }
        #expect(throws: KnowledgeGraphError.emptyNamespaceURI) {
            try builder.insertNamespace(Namespace(prefix: "ex", uri: ""))
        }
    }

    // MARK: - Named graphs

    @Test("Named graphs merge nodes/edges in insertion order")
    func namedGraphMerge() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNamedGraph(NamedGraph(
            id: "http://example.org/g1",
            nodes: [.iri("http://example.org/A")]
        ))
        try builder.insertNamedGraph(NamedGraph(
            id: "http://example.org/g1",
            nodes: [.iri("http://example.org/A"), .iri("http://example.org/B")]
        ))
        let snapshot = builder.build()
        let graph = try #require(snapshot.namedGraphs.first { $0.id == "http://example.org/g1" })
        #expect(graph.nodes == [
            .iri("http://example.org/A"),
            .iri("http://example.org/B"),
        ])
    }

    @Test("Conflicting named-graph labels raise")
    func namedGraphLabelConflict() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNamedGraph(NamedGraph(id: "http://example.org/g1", label: "First"))
        #expect(throws: KnowledgeGraphError.self) {
            try builder.insertNamedGraph(NamedGraph(id: "http://example.org/g1", label: "Second"))
        }
    }
}
