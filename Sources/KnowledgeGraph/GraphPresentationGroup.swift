import Foundation

/// Visual grouping metadata. Groups are not RDF nodes and do not create edges.
public struct GraphPresentationGroup: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String
    public let kind: String?
    public let members: [GraphElementReference]
    public let children: [GraphPresentationGroup]
    public let attributes: [Attribute]

    public init(
        id: String,
        title: String,
        kind: String? = nil,
        members: [GraphElementReference] = [],
        children: [GraphPresentationGroup] = [],
        attributes: [Attribute] = []
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.members = members
        self.children = children
        self.attributes = attributes
    }
}

