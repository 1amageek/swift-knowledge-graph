import Foundation

/// A named subgraph carved out of the overall `KnowledgeGraph`.
///
/// TriG and JSON-LD both support multiple named graphs in a single payload.
/// Each named graph references nodes and edges by identifier — the canonical
/// `Node` and `Edge` values live in the parent `KnowledgeGraph` so the same
/// node can participate in several named graphs without duplication.
public struct NamedGraph: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let label: String?
    public let nodes: [NodeIdentifier]
    public let edges: [EdgeIdentifier]

    public init(
        id: String,
        label: String? = nil,
        nodes: [NodeIdentifier] = [],
        edges: [EdgeIdentifier] = []
    ) {
        self.id = id
        self.label = label
        self.nodes = nodes
        self.edges = edges
    }
}
