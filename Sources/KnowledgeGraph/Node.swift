import Foundation

/// A vertex in the knowledge graph.
///
/// `Node` is an immutable value type. Mutation always goes through
/// `KnowledgeGraphBuilder`, which produces a fresh `KnowledgeGraph` snapshot;
/// renderers and layout engines can therefore diff two snapshots safely
/// without worrying about shared mutable state.
///
/// `id` is stable across re-parses of the same payload, so a layout engine can
/// preserve the position of a node across snapshots by matching on `id`.
public struct Node: Hashable, Sendable, Identifiable, Codable {
    public let id: NodeIdentifier
    public let label: String?
    public let types: [String]
    public let datatype: String?
    public let language: String?
    public let attributes: [Attribute]

    public init(
        id: NodeIdentifier,
        label: String? = nil,
        types: [String] = [],
        datatype: String? = nil,
        language: String? = nil,
        attributes: [Attribute] = []
    ) {
        self.id = id
        self.label = label
        self.types = types
        self.datatype = datatype
        self.language = language
        self.attributes = attributes
    }

    /// Returns a copy of the node with merged metadata.
    ///
    /// - `label`: replaced only when the receiver does not already have one.
    /// - `types`: union, preserving the receiver's order and appending newly
    ///   seen types.
    /// - `datatype` / `language`: replaced only when the receiver does not
    ///   already have a value.
    /// - `attributes`: union by key, preferring the receiver on conflict.
    ///
    /// The intent is that earlier-seen metadata wins, which matches the
    /// expectations of a streaming parser: the first sighting of a node
    /// usually carries the most authoritative information.
    public func merging(_ other: Node) -> Node {
        Node(
            id: id,
            label: label ?? other.label,
            types: mergedTypes(other.types),
            datatype: datatype ?? other.datatype,
            language: language ?? other.language,
            attributes: mergedAttributes(other.attributes)
        )
    }

    private func mergedTypes(_ incoming: [String]) -> [String] {
        var result = types
        var seen = Set(types)
        for type in incoming where !seen.contains(type) {
            result.append(type)
            seen.insert(type)
        }
        return result
    }

    private func mergedAttributes(_ incoming: [Attribute]) -> [Attribute] {
        var result = attributes
        let existingKeys = Set(attributes.map { $0.key })
        for attribute in incoming where !existingKeys.contains(attribute.key) {
            result.append(attribute)
        }
        return result
    }
}
