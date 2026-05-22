import Foundation

/// Typed reference to an element that can participate in presentation metadata.
public enum GraphElementReference: Hashable, Sendable, Codable {
    case node(NodeIdentifier)
    case edge(EdgeIdentifier)
    case namedGraph(String)
    case group(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case node
        case edge
        case id
    }

    private enum Kind: String, Codable {
        case node
        case edge
        case namedGraph
        case group
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .node:
            self = .node(try container.decode(NodeIdentifier.self, forKey: .node))
        case .edge:
            self = .edge(try container.decode(EdgeIdentifier.self, forKey: .edge))
        case .namedGraph:
            self = .namedGraph(try container.decode(String.self, forKey: .id))
        case .group:
            self = .group(try container.decode(String.self, forKey: .id))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .node(let node):
            try container.encode(Kind.node, forKey: .type)
            try container.encode(node, forKey: .node)
        case .edge(let edge):
            try container.encode(Kind.edge, forKey: .type)
            try container.encode(edge, forKey: .edge)
        case .namedGraph(let id):
            try container.encode(Kind.namedGraph, forKey: .type)
            try container.encode(id, forKey: .id)
        case .group(let id):
            try container.encode(Kind.group, forKey: .type)
            try container.encode(id, forKey: .id)
        }
    }
}
