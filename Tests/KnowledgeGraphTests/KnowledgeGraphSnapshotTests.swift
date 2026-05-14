import Foundation
import Testing
@testable import KnowledgeGraph

@Suite("KnowledgeGraph snapshot")
struct KnowledgeGraphSnapshotTests {

    @Test("Empty snapshot has empty arrays")
    func emptySnapshot() {
        let snapshot = KnowledgeGraph.empty
        #expect(snapshot.nodes.isEmpty)
        #expect(snapshot.edges.isEmpty)
        #expect(snapshot.namespaces.isEmpty)
        #expect(snapshot.namedGraphs.isEmpty)
    }

    @Test("Node lookup returns the inserted node")
    func nodeLookup() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertNode(Node(id: .iri("http://example.org/A"), label: "A"))
        let snapshot = builder.build()
        let node = try #require(snapshot.node(with: .iri("http://example.org/A")))
        #expect(node.label == "A")
    }

    @Test("Edge lookup returns the inserted edge")
    func edgeLookup() throws {
        var builder = KnowledgeGraphBuilder()
        let id = EdgeIdentifier(
            source: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            target: .iri("http://example.org/B")
        )
        try builder.insertEdge(Edge(id: id, label: "p"))
        let snapshot = builder.build()
        let edge = try #require(snapshot.edge(with: id))
        #expect(edge.label == "p")
        #expect(edge.source == .iri("http://example.org/A"))
        #expect(edge.target == .iri("http://example.org/B"))
        #expect(edge.predicate == "http://example.org/p")
        #expect(edge.namedGraph == nil)
    }

    @Test("Snapshot is Hashable and Equatable")
    func hashableAndEquatable() throws {
        var a = KnowledgeGraphBuilder()
        var b = KnowledgeGraphBuilder()
        try a.insertTriple(
            subject: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            object: .iri("http://example.org/B")
        )
        try b.insertTriple(
            subject: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            object: .iri("http://example.org/B")
        )
        #expect(a.build() == b.build())
        #expect(a.build().hashValue == b.build().hashValue)
    }

    @Test("Snapshot conforms to Codable round-trip")
    func codableRoundTrip() throws {
        var builder = KnowledgeGraphBuilder()
        try builder.insertTriple(
            subject: .iri("http://example.org/Alice"),
            predicate: "http://xmlns.com/foaf/0.1/knows",
            object: .iri("http://example.org/Bob")
        )
        try builder.insertNamespace(Namespace(prefix: "foaf", uri: "http://xmlns.com/foaf/0.1/"))
        let snapshot = builder.build()
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(KnowledgeGraph.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test("All IR value types are Sendable (compile-time)")
    func sendable() {
        let node: any Sendable = Node(id: .iri("http://example.org/A"))
        let edge: any Sendable = Edge(id: EdgeIdentifier(
            source: .iri("http://example.org/A"),
            predicate: "http://example.org/p",
            target: .iri("http://example.org/B")
        ))
        let ns: any Sendable = Namespace(prefix: "x", uri: "http://example.org/")
        let ng: any Sendable = NamedGraph(id: "http://example.org/g")
        let attribute: any Sendable = Attribute(key: "k", value: "v")
        let graph: any Sendable = KnowledgeGraph.empty
        let builder: any Sendable = KnowledgeGraphBuilder()
        #expect(node is Node)
        #expect(edge is Edge)
        #expect(ns is Namespace)
        #expect(ng is NamedGraph)
        #expect(attribute is Attribute)
        #expect(graph is KnowledgeGraph)
        #expect(builder is KnowledgeGraphBuilder)
    }
}
