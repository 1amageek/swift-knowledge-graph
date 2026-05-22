import Foundation

/// Renderer-agnostic layout intent. Layout engines may ignore unsupported hints.
public struct GraphLayoutDirective: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let scope: GraphElementReference?
    public let items: [GraphElementReference]
    public let arrangement: GraphArrangement
    public let priority: GraphLayoutPriority

    public init(
        id: String,
        scope: GraphElementReference? = nil,
        items: [GraphElementReference],
        arrangement: GraphArrangement,
        priority: GraphLayoutPriority = .preferred
    ) {
        self.id = id
        self.scope = scope
        self.items = items
        self.arrangement = arrangement
        self.priority = priority
    }
}

public enum GraphLayoutPriority: String, Hashable, Sendable, Codable {
    case preferred
    case required
}

public enum GraphArrangement: Hashable, Sendable, Codable {
    case stack(GraphStackArrangement)
    case order
    case rank(GraphAxis?)
    case grid(columns: Int?)
    case pin(GraphPoint?)
    case align(GraphAlignment)
}

public struct GraphStackArrangement: Hashable, Sendable, Codable {
    public let axis: GraphAxis
    public let direction: GraphDirection
    public let alignment: GraphAlignment
    public let gap: Double?

    public init(
        axis: GraphAxis,
        direction: GraphDirection,
        alignment: GraphAlignment = .center,
        gap: Double? = nil
    ) {
        self.axis = axis
        self.direction = direction
        self.alignment = alignment
        self.gap = gap
    }
}

public enum GraphAxis: String, Hashable, Sendable, Codable {
    case horizontal
    case vertical
}

public enum GraphDirection: String, Hashable, Sendable, Codable {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop
}

public enum GraphAlignment: String, Hashable, Sendable, Codable {
    case leading
    case center
    case trailing
    case stretch
}

public struct GraphPoint: Hashable, Sendable, Codable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

