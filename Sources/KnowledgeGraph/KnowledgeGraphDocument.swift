import Foundation

/// A semantic graph bundled with optional renderer-agnostic presentation data.
///
/// `KnowledgeGraph` stays pure semantic IR. Presentation metadata such as
/// groups, styles, and layout hints lives here so multiple renderers can share
/// the same view intent without turning it into RDF triples.
public struct KnowledgeGraphDocument: Hashable, Sendable, Codable {
    public let graph: KnowledgeGraph
    public let presentations: [GraphPresentation]

    public init(
        graph: KnowledgeGraph,
        presentations: [GraphPresentation] = []
    ) {
        self.graph = graph
        self.presentations = presentations
    }
}

