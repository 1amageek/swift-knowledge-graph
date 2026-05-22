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
    case canvas
    case node(NodeIdentifier)
    case edge(EdgeIdentifier)
    case namedGraph(String)
    case group(String)
    case kind(String)
    case rdfType(String)
    case allNodes
    case allEdges
    case allGroups

    private enum CodingKeys: String, CodingKey {
        case type
        case node
        case edge
        case id
    }

    private enum Kind: String, Codable {
        case canvas
        case node
        case edge
        case namedGraph
        case group
        case kind
        case rdfType
        case allNodes
        case allEdges
        case allGroups
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .canvas:
            self = .canvas
        case .node:
            self = .node(try container.decode(NodeIdentifier.self, forKey: .node))
        case .edge:
            self = .edge(try container.decode(EdgeIdentifier.self, forKey: .edge))
        case .namedGraph:
            self = .namedGraph(try container.decode(String.self, forKey: .id))
        case .group:
            self = .group(try container.decode(String.self, forKey: .id))
        case .kind:
            self = .kind(try container.decode(String.self, forKey: .id))
        case .rdfType:
            self = .rdfType(try container.decode(String.self, forKey: .id))
        case .allNodes:
            self = .allNodes
        case .allEdges:
            self = .allEdges
        case .allGroups:
            self = .allGroups
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .canvas:
            try container.encode(Kind.canvas, forKey: .type)
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
        case .kind(let id):
            try container.encode(Kind.kind, forKey: .type)
            try container.encode(id, forKey: .id)
        case .rdfType(let id):
            try container.encode(Kind.rdfType, forKey: .type)
            try container.encode(id, forKey: .id)
        case .allNodes:
            try container.encode(Kind.allNodes, forKey: .type)
        case .allEdges:
            try container.encode(Kind.allEdges, forKey: .type)
        case .allGroups:
            try container.encode(Kind.allGroups, forKey: .type)
        }
    }
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

    private enum CodingKeys: String, CodingKey {
        case type
        case radius
    }

    private enum Kind: String, Codable {
        case rectangle
        case roundedRectangle
        case capsule
        case ellipse
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .rectangle:
            self = .rectangle
        case .roundedRectangle:
            self = .roundedRectangle(radius: try container.decodeIfPresent(Double.self, forKey: .radius))
        case .capsule:
            self = .capsule
        case .ellipse:
            self = .ellipse
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .rectangle:
            try container.encode(Kind.rectangle, forKey: .type)
        case .roundedRectangle(let radius):
            try container.encode(Kind.roundedRectangle, forKey: .type)
            try container.encodeIfPresent(radius, forKey: .radius)
        case .capsule:
            try container.encode(Kind.capsule, forKey: .type)
        case .ellipse:
            try container.encode(Kind.ellipse, forKey: .type)
        }
    }
}

public enum GraphPaint: Hashable, Sendable, Codable {
    case color(GraphColor)
    case palette(String)
    case semantic(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case color
        case value
    }

    private enum Kind: String, Codable {
        case color
        case palette
        case semantic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .color:
            self = .color(try container.decode(GraphColor.self, forKey: .color))
        case .palette:
            self = .palette(try container.decode(String.self, forKey: .value))
        case .semantic:
            self = .semantic(try container.decode(String.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let color):
            try container.encode(Kind.color, forKey: .type)
            try container.encode(color, forKey: .color)
        case .palette(let value):
            try container.encode(Kind.palette, forKey: .type)
            try container.encode(value, forKey: .value)
        case .semantic(let value):
            try container.encode(Kind.semantic, forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
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

    private enum CodingKeys: String, CodingKey {
        case type
        case pattern
    }

    private enum Kind: String, Codable {
        case solid
        case dashed
        case dotted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .solid:
            self = .solid
        case .dashed:
            self = .dashed(pattern: try container.decodeIfPresent([Double].self, forKey: .pattern))
        case .dotted:
            self = .dotted
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solid:
            try container.encode(Kind.solid, forKey: .type)
        case .dashed(let pattern):
            try container.encode(Kind.dashed, forKey: .type)
            try container.encodeIfPresent(pattern, forKey: .pattern)
        case .dotted:
            try container.encode(Kind.dotted, forKey: .type)
        }
    }
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
    public let label: GraphEdgeLabelStyle?

    public init(
        stroke: GraphStroke? = nil,
        sourceMarker: GraphMarker? = nil,
        targetMarker: GraphMarker? = nil,
        route: GraphEdgeRouteStyle? = nil,
        label: GraphEdgeLabelStyle? = nil
    ) {
        self.stroke = stroke
        self.sourceMarker = sourceMarker
        self.targetMarker = targetMarker
        self.route = route
        self.label = label
    }
}

public struct GraphEdgeLabelStyle: Hashable, Sendable, Codable {
    public let shape: GraphShape?
    public let fill: GraphPaint?
    public let stroke: GraphStroke?
    public let text: GraphTextStyle?
    public let opacity: Double?

    public init(
        shape: GraphShape? = nil,
        fill: GraphPaint? = nil,
        stroke: GraphStroke? = nil,
        text: GraphTextStyle? = nil,
        opacity: Double? = nil
    ) {
        self.shape = shape
        self.fill = fill
        self.stroke = stroke
        self.text = text
        self.opacity = opacity
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
