import Foundation

/// Stable identifier for a directed edge.
///
/// Identity is a pure function of `(source, predicate, target, namedGraph)`,
/// so the same RDF triple — re-emitted on a second parse of the same
/// document — produces the exact same `EdgeIdentifier`. Edges in a named
/// graph and edges in the default graph are distinct even when their other
/// fields match, because `namedGraph` participates in equality.
public struct EdgeIdentifier: Hashable, Sendable, Codable {
    public let source: NodeIdentifier
    public let predicate: String
    public let target: NodeIdentifier
    public let namedGraph: String?

    public init(
        source: NodeIdentifier,
        predicate: String,
        target: NodeIdentifier,
        namedGraph: String? = nil
    ) {
        self.source = source
        self.predicate = predicate
        self.target = target
        self.namedGraph = namedGraph
    }
}
