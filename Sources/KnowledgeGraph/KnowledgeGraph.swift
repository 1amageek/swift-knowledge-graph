import Foundation

/// Immutable snapshot of a knowledge graph.
///
/// `KnowledgeGraph` is the consumer-facing IR value: it is what a renderer or
/// layout engine receives, and it never mutates. Use `KnowledgeGraphBuilder`
/// to construct one incrementally; call `build()` as often as you need to
/// pull intermediate snapshots out for a streaming renderer.
///
/// Arrays are kept in insertion order so that a layout engine can perform a
/// warm restart: when a new snapshot arrives, the previously seen prefix of
/// `nodes` and `edges` is guaranteed to be in the same order, which is what
/// makes "preserve the position of nodes I already laid out" easy to
/// implement.
public struct KnowledgeGraph: Hashable, Sendable, Codable {
    public let nodes: [Node]
    public let edges: [Edge]
    public let namespaces: [Namespace]
    public let namedGraphs: [NamedGraph]

    public init(
        nodes: [Node] = [],
        edges: [Edge] = [],
        namespaces: [Namespace] = [],
        namedGraphs: [NamedGraph] = []
    ) {
        self.nodes = nodes
        self.edges = edges
        self.namespaces = namespaces
        self.namedGraphs = namedGraphs
    }

    /// Convenience: an empty graph with no nodes, edges, namespaces, or named
    /// graphs.
    public static let empty = KnowledgeGraph()

    /// Look up a node by identifier. `O(n)` — for hot paths build a
    /// `[NodeIdentifier: Node]` from `nodes` and reuse it.
    public func node(with id: NodeIdentifier) -> Node? {
        nodes.first { $0.id == id }
    }

    /// Look up an edge by identifier. `O(n)` — same caveat as `node(with:)`.
    public func edge(with id: EdgeIdentifier) -> Edge? {
        edges.first { $0.id == id }
    }
}
