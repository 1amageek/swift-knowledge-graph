import Foundation

/// Renderer-agnostic view metadata for a `KnowledgeGraph`.
public struct GraphPresentation: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let title: String?
    public let groups: [GraphPresentationGroup]
    public let layouts: [GraphLayoutDirective]
    public let styles: [GraphStyleRule]

    public init(
        id: String,
        title: String? = nil,
        groups: [GraphPresentationGroup] = [],
        layouts: [GraphLayoutDirective] = [],
        styles: [GraphStyleRule] = []
    ) {
        self.id = id
        self.title = title
        self.groups = groups
        self.layouts = layouts
        self.styles = styles
    }
}

