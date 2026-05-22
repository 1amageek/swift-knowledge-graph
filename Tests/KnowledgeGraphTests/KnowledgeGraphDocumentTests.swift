import Foundation
import Testing
@testable import KnowledgeGraph

@Suite("KnowledgeGraphDocument")
struct KnowledgeGraphDocumentTests {

    @Test
    func documentKeepsSemanticGraphAndPresentationsSeparate() throws {
        let graph = KnowledgeGraph(
            nodes: [Node(id: .iri("http://example.org/a"), label: "A")],
            edges: [
                Edge(id: EdgeIdentifier(
                    source: .iri("http://example.org/a"),
                    predicate: "http://example.org/relatesTo",
                    target: .iri("http://example.org/b")
                ))
            ]
        )
        let presentation = GraphPresentation(
            id: "presentation:main",
            title: "Main",
            groups: [
                GraphPresentationGroup(
                    id: "group:visual",
                    title: "Visual group",
                    members: [.node(.iri("http://example.org/a"))]
                )
            ],
            styles: [
                GraphStyleRule(
                    id: "style:visual",
                    target: .group("group:visual"),
                    style: GraphStyle(fill: .semantic("groupFill"))
                )
            ]
        )

        let document = KnowledgeGraphDocument(
            graph: graph,
            presentations: [presentation]
        )

        #expect(document.graph == graph)
        #expect(document.presentations == [presentation])
        #expect(document.graph.nodes.count == 1)
        #expect(document.graph.edges.count == 1)
    }

    @Test
    func documentRoundTripsThroughJSON() throws {
        let document = KnowledgeGraphDocument(
            graph: KnowledgeGraph(nodes: [Node(id: .blank("a"))]),
            presentations: [
                GraphPresentation(
                    id: "presentation:empty",
                    layouts: [
                        GraphLayoutDirective(
                            id: "layout:empty",
                            items: [.node(.blank("a"))],
                            arrangement: .order
                        )
                    ]
                )
            ]
        )

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(KnowledgeGraphDocument.self, from: data)

        #expect(decoded == document)
    }
}
