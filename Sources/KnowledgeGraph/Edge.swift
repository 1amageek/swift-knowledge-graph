import Foundation

/// A directed edge between two nodes.
///
/// The edge carries an optional human-readable label (typically the local
/// name or shortened CURIE of `id.predicate`) and free-form attributes for
/// the renderer / layout engine to consume. The semantic identity lives in
/// `id` — equality and hashing of `Edge` are dominated by it.
public struct Edge: Hashable, Sendable, Identifiable, Codable {
    public let id: EdgeIdentifier
    public let label: String?
    public let attributes: [Attribute]

    public init(
        id: EdgeIdentifier,
        label: String? = nil,
        attributes: [Attribute] = []
    ) {
        self.id = id
        self.label = label
        self.attributes = attributes
    }

    /// Convenience accessor for the source node identifier.
    public var source: NodeIdentifier { id.source }

    /// Convenience accessor for the predicate IRI.
    public var predicate: String { id.predicate }

    /// Convenience accessor for the target node identifier.
    public var target: NodeIdentifier { id.target }

    /// Convenience accessor for the optional named-graph IRI.
    public var namedGraph: String? { id.namedGraph }

    /// Merge metadata using the same first-wins policy as `Node.merging(_:)`.
    public func merging(_ other: Edge) -> Edge {
        let mergedLabel = label ?? other.label
        var mergedAttributes = attributes
        let existingKeys = Set(attributes.map { $0.key })
        for attribute in other.attributes where !existingKeys.contains(attribute.key) {
            mergedAttributes.append(attribute)
        }
        return Edge(id: id, label: mergedLabel, attributes: mergedAttributes)
    }
}
