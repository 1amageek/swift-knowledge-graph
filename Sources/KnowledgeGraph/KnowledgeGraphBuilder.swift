import Foundation

/// Incremental, idempotent builder for `KnowledgeGraph`.
///
/// `KnowledgeGraphBuilder` is a value type — mutation is per-instance and
/// each `build()` call returns a fresh `KnowledgeGraph` snapshot. This shape
/// is what makes it usable from a streaming parser: keep one builder around
/// for the whole parse, snapshot after each triple (or batch of triples), and
/// hand the snapshot to a renderer. Because identifiers are content-addressed,
/// re-parsing a longer prefix of the same payload produces a snapshot whose
/// first N elements equal the previous snapshot's — letting a layout engine
/// warm-restart.
///
/// All `insert*` methods are idempotent: inserting the exact same triple
/// twice is a no-op, and inserting a node whose identifier already exists
/// merges metadata under a first-wins policy.
public struct KnowledgeGraphBuilder: Sendable {

    // MARK: - Storage

    private var nodes: [Node] = []
    private var nodeIndex: [NodeIdentifier: Int] = [:]

    private var edges: [Edge] = []
    private var edgeIndex: [EdgeIdentifier: Int] = [:]

    private var namespaces: [Namespace] = []
    private var namespacePrefixIndex: [String: Int] = [:]

    private var namedGraphs: [NamedGraph] = []
    private var namedGraphIndex: [String: Int] = [:]

    public init() {}

    // MARK: - Snapshot

    public func build() -> KnowledgeGraph {
        KnowledgeGraph(
            nodes: nodes,
            edges: edges,
            namespaces: namespaces,
            namedGraphs: namedGraphs
        )
    }

    // MARK: - Nodes

    @discardableResult
    public mutating func insertNode(_ node: Node) throws -> NodeIdentifier {
        try validateNodeIdentifier(node.id)
        if let index = nodeIndex[node.id] {
            nodes[index] = nodes[index].merging(node)
        } else {
            nodeIndex[node.id] = nodes.count
            nodes.append(node)
        }
        return node.id
    }

    // MARK: - Edges

    @discardableResult
    public mutating func insertEdge(_ edge: Edge) throws -> EdgeIdentifier {
        if edge.id.predicate.isEmpty {
            throw KnowledgeGraphError.emptyPredicate
        }
        try ensureNode(edge.id.source)
        try ensureNode(edge.id.target)
        if let index = edgeIndex[edge.id] {
            edges[index] = edges[index].merging(edge)
        } else {
            edgeIndex[edge.id] = edges.count
            edges.append(edge)
        }
        return edge.id
    }

    /// Convenience: construct and insert an edge from a bare triple. Subject
    /// and object nodes are auto-created with no metadata if they have not
    /// been seen yet; if the caller wants to attach labels or types to those
    /// nodes, call `insertNode(_:)` first (or after — first-wins merge means
    /// the order does not matter).
    @discardableResult
    public mutating func insertTriple(
        subject: NodeIdentifier,
        predicate: String,
        object: NodeIdentifier,
        namedGraph: String? = nil,
        label: String? = nil,
        attributes: [Attribute] = []
    ) throws -> EdgeIdentifier {
        let id = EdgeIdentifier(
            source: subject,
            predicate: predicate,
            target: object,
            namedGraph: namedGraph
        )
        return try insertEdge(Edge(id: id, label: label, attributes: attributes))
    }

    // MARK: - Namespaces

    public mutating func insertNamespace(_ namespace: Namespace) throws {
        if namespace.prefix.isEmpty {
            throw KnowledgeGraphError.emptyNamespacePrefix
        }
        if namespace.uri.isEmpty {
            throw KnowledgeGraphError.emptyNamespaceURI
        }
        if let index = namespacePrefixIndex[namespace.prefix] {
            let existing = namespaces[index]
            if existing.uri == namespace.uri {
                return
            }
            throw KnowledgeGraphError.namespacePrefixConflict(
                prefix: namespace.prefix,
                existing: existing.uri,
                attempted: namespace.uri
            )
        }
        namespacePrefixIndex[namespace.prefix] = namespaces.count
        namespaces.append(namespace)
    }

    // MARK: - Named graphs

    public mutating func insertNamedGraph(_ graph: NamedGraph) throws {
        if graph.id.isEmpty {
            throw KnowledgeGraphError.emptyNamedGraphID
        }
        if let index = namedGraphIndex[graph.id] {
            let existing = namedGraphs[index]
            if let existingLabel = existing.label,
               let newLabel = graph.label,
               existingLabel != newLabel {
                throw KnowledgeGraphError.namedGraphLabelConflict(
                    id: graph.id,
                    existing: existingLabel,
                    attempted: newLabel
                )
            }
            namedGraphs[index] = NamedGraph(
                id: graph.id,
                label: existing.label ?? graph.label,
                nodes: Self.mergedNodeIdentifiers(existing.nodes, graph.nodes),
                edges: Self.mergedEdgeIdentifiers(existing.edges, graph.edges)
            )
        } else {
            namedGraphIndex[graph.id] = namedGraphs.count
            namedGraphs.append(graph)
        }
    }

    // MARK: - Helpers

    private mutating func ensureNode(_ id: NodeIdentifier) throws {
        try validateNodeIdentifier(id)
        if nodeIndex[id] == nil {
            nodeIndex[id] = nodes.count
            nodes.append(Node(id: id))
        }
    }

    private func validateNodeIdentifier(_ id: NodeIdentifier) throws {
        switch id.kind {
        case .iri:
            if id.key.isEmpty { throw KnowledgeGraphError.emptyIRI }
        case .blank:
            if id.key.isEmpty { throw KnowledgeGraphError.emptyBlankLabel }
        case .literal:
            // Literal keys are non-empty by construction — the encoding always
            // emits at least the surrounding quotes — so no extra check here.
            break
        }
    }

    private static func mergedNodeIdentifiers(
        _ existing: [NodeIdentifier],
        _ incoming: [NodeIdentifier]
    ) -> [NodeIdentifier] {
        var result = existing
        var seen = Set(existing)
        for id in incoming where !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        return result
    }

    private static func mergedEdgeIdentifiers(
        _ existing: [EdgeIdentifier],
        _ incoming: [EdgeIdentifier]
    ) -> [EdgeIdentifier] {
        var result = existing
        var seen = Set(existing)
        for id in incoming where !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        return result
    }
}
