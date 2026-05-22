import Foundation

/// A renderer-agnostic style rule applied to a graph element or class of elements.
public struct GraphStyleRule: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let target: GraphStyleTarget
    public let style: GraphStyle
    public let priority: GraphStylePriority
    public let attributes: [Attribute]

    public init(
        id: String,
        target: GraphStyleTarget,
        style: GraphStyle,
        priority: GraphStylePriority = .explicit,
        attributes: [Attribute] = []
    ) {
        self.id = id
        self.target = target
        self.style = style
        self.priority = priority
        self.attributes = attributes
    }
}

public enum GraphStyleTarget: Hashable, Sendable, Codable {
    case element(GraphElementReference)
    case kind(String)
    case type(String)
    case allNodes
    case allEdges
    case allGroups
}

public enum GraphStylePriority: String, Hashable, Sendable, Codable {
    case `default`
    case theme
    case explicit
    case override
}

/// Optional visual properties. Renderers ignore fields that do not apply.
public struct GraphStyle: Hashable, Sendable, Codable {
    public let shape: GraphShape?
    public let fill: GraphPaint?
    public let stroke: GraphStroke?
    public let text: GraphTextStyle?
    public let edge: GraphEdgeStyle?
    public let opacity: Double?

    public init(
        shape: GraphShape? = nil,
        fill: GraphPaint? = nil,
        stroke: GraphStroke? = nil,
        text: GraphTextStyle? = nil,
        edge: GraphEdgeStyle? = nil,
        opacity: Double? = nil
    ) {
        self.shape = shape
        self.fill = fill
        self.stroke = stroke
        self.text = text
        self.edge = edge
        self.opacity = opacity
    }
}

public enum GraphShape: Hashable, Sendable, Codable {
    case rectangle
    case roundedRectangle(radius: Double?)
    case capsule
    case ellipse
}

public enum GraphPaint: Hashable, Sendable, Codable {
    case color(GraphColor)
    case palette(String)
    case semantic(String)
}

public struct GraphColor: Hashable, Sendable, Codable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct GraphStroke: Hashable, Sendable, Codable {
    public let paint: GraphPaint?
    public let width: Double?
    public let line: GraphLineStyle?

    public init(
        paint: GraphPaint? = nil,
        width: Double? = nil,
        line: GraphLineStyle? = nil
    ) {
        self.paint = paint
        self.width = width
        self.line = line
    }
}

public enum GraphLineStyle: Hashable, Sendable, Codable {
    case solid
    case dashed(pattern: [Double]?)
    case dotted
}

public struct GraphTextStyle: Hashable, Sendable, Codable {
    public let paint: GraphPaint?
    public let weight: String?
    public let size: Double?

    public init(
        paint: GraphPaint? = nil,
        weight: String? = nil,
        size: Double? = nil
    ) {
        self.paint = paint
        self.weight = weight
        self.size = size
    }
}

public struct GraphEdgeStyle: Hashable, Sendable, Codable {
    public let stroke: GraphStroke?
    public let sourceMarker: GraphMarker?
    public let targetMarker: GraphMarker?
    public let route: GraphEdgeRouteStyle?

    public init(
        stroke: GraphStroke? = nil,
        sourceMarker: GraphMarker? = nil,
        targetMarker: GraphMarker? = nil,
        route: GraphEdgeRouteStyle? = nil
    ) {
        self.stroke = stroke
        self.sourceMarker = sourceMarker
        self.targetMarker = targetMarker
        self.route = route
    }
}

public enum GraphMarker: String, Hashable, Sendable, Codable {
    case none
    case arrow
    case circle
    case diamond
}

public enum GraphEdgeRouteStyle: String, Hashable, Sendable, Codable {
    case automatic
    case orthogonal
    case straight
    case curved
}

