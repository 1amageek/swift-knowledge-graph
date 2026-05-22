import Foundation

/// Typed reference to an element that can participate in presentation metadata.
public enum GraphElementReference: Hashable, Sendable, Codable {
    case node(NodeIdentifier)
    case edge(EdgeIdentifier)
    case namedGraph(String)
    case group(String)
}

