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
    case align(GraphStackAlignment)

    private enum CodingKeys: String, CodingKey {
        case type
        case stack
        case axis
        case columns
        case point
        case alignment
    }

    private enum Kind: String, Codable {
        case stack
        case order
        case rank
        case grid
        case pin
        case align
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        switch type {
        case .stack:
            self = .stack(try container.decode(GraphStackArrangement.self, forKey: .stack))
        case .order:
            self = .order
        case .rank:
            self = .rank(try container.decodeIfPresent(GraphAxis.self, forKey: .axis))
        case .grid:
            self = .grid(columns: try container.decodeIfPresent(Int.self, forKey: .columns))
        case .pin:
            self = .pin(try container.decodeIfPresent(GraphPoint.self, forKey: .point))
        case .align:
            self = .align(try container.decode(GraphStackAlignment.self, forKey: .alignment))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stack(let stack):
            try container.encode(Kind.stack, forKey: .type)
            try container.encode(stack, forKey: .stack)
        case .order:
            try container.encode(Kind.order, forKey: .type)
        case .rank(let axis):
            try container.encode(Kind.rank, forKey: .type)
            try container.encodeIfPresent(axis, forKey: .axis)
        case .grid(let columns):
            try container.encode(Kind.grid, forKey: .type)
            try container.encodeIfPresent(columns, forKey: .columns)
        case .pin(let point):
            try container.encode(Kind.pin, forKey: .type)
            try container.encodeIfPresent(point, forKey: .point)
        case .align(let alignment):
            try container.encode(Kind.align, forKey: .type)
            try container.encode(alignment, forKey: .alignment)
        }
    }
}

public struct GraphStackArrangement: Hashable, Sendable, Codable {
    public let direction: GraphStackDirection
    public let alignment: GraphStackAlignment
    public let spacing: Double?

    public var axis: GraphAxis {
        direction.axis
    }

    public init(
        direction: GraphStackDirection,
        alignment: GraphStackAlignment = .center,
        spacing: Double? = nil
    ) {
        self.direction = direction
        self.alignment = alignment
        self.spacing = spacing
    }
}

public enum GraphAxis: String, Hashable, Sendable, Codable {
    case horizontal
    case vertical
}

public enum GraphStackDirection: String, Hashable, Sendable, Codable {
    case leftToRight
    case rightToLeft
    case topToBottom
    case bottomToTop

    public var axis: GraphAxis {
        switch self {
        case .leftToRight, .rightToLeft:
            return .horizontal
        case .topToBottom, .bottomToTop:
            return .vertical
        }
    }
}

public enum GraphStackAlignment: String, Hashable, Sendable, Codable {
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
