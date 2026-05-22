import Foundation
import KnowledgeGraph

public enum JSONLDGraphPresentationExtractionError: Error, Equatable {
    case invalidJSON(String)
    case invalidRoot
}

/// Extracts non-standard top-level JSON-LD `view` metadata into presentation IR.
///
/// This type deliberately sits outside `JSONLDParser`: `view` is renderer
/// metadata, not part of the W3C JSON-LD to RDF algorithm.
public enum JSONLDGraphPresentationExtractor {

    public static func presentation(
        from payload: String,
        id: String = "presentation:default",
        title: String? = nil
    ) throws -> GraphPresentation? {
        let data = Data(payload.utf8)
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw JSONLDGraphPresentationExtractionError.invalidJSON(error.localizedDescription)
        }
        guard let root = object as? [String: Any] else {
            throw JSONLDGraphPresentationExtractionError.invalidRoot
        }
        guard let view = root["view"] as? [String: Any] else { return nil }

        let resolver = IdentifierResolver(context: root["@context"])
        let groups = parseGroups(view["groups"], resolver: resolver)
        let styles = parseStyles(view["styles"], resolver: resolver)
        let layouts = parseLayouts(view["layouts"], resolver: resolver)
        guard !groups.isEmpty || !styles.isEmpty || !layouts.isEmpty else {
            return nil
        }
        return GraphPresentation(
            id: id,
            title: title,
            groups: groups,
            layouts: layouts,
            styles: styles
        )
    }

    public static func document(
        graph: KnowledgeGraph,
        payload: String,
        presentationID: String = "presentation:default",
        title: String? = nil
    ) throws -> KnowledgeGraphDocument {
        KnowledgeGraphDocument(
            graph: graph,
            presentations: try presentation(from: payload, id: presentationID, title: title).map { [$0] } ?? []
        )
    }

    private static func parseGroups(
        _ value: Any?,
        resolver: IdentifierResolver
    ) -> [GraphPresentationGroup] {
        guard let groups = value as? [[String: Any]] else { return [] }
        return groups.compactMap { parseGroup($0, resolver: resolver)?.group }
    }

    private static func parseGroup(
        _ object: [String: Any],
        resolver: IdentifierResolver
    ) -> (group: GraphPresentationGroup, transitiveMembers: [GraphElementReference])? {
        guard let id = object["id"] as? String,
              let title = object["title"] as? String,
              !id.isEmpty,
              !title.isEmpty
        else {
            return nil
        }

        var members = parseReferences(object["members"], resolver: resolver)
        let children = (object["children"] as? [[String: Any]] ?? []).compactMap { child in
            parseGroup(child, resolver: resolver)
        }
        for child in children {
            members.append(contentsOf: child.transitiveMembers)
        }
        members = deduplicated(members)

        let group = GraphPresentationGroup(
            id: id,
            title: title,
            kind: object["kind"] as? String,
            members: members,
            children: children.map(\.group),
            attributes: parseAttributes(object["attributes"])
        )
        return (group, members)
    }

    private static func parseStyles(
        _ value: Any?,
        resolver: IdentifierResolver
    ) -> [GraphStyleRule] {
        guard let styles = value as? [[String: Any]] else { return [] }
        return styles.enumerated().compactMap { offset, object in
            guard let target = parseStyleTarget(object["target"], resolver: resolver) else {
                return nil
            }
            let styleObject = object["style"] as? [String: Any] ?? object
            let style = parseStyle(styleObject, target: target)
            guard style != GraphStyle() else { return nil }
            return GraphStyleRule(
                id: object["id"] as? String ?? "style:\(offset)",
                target: target,
                style: style,
                priority: parseStylePriority(object["priority"]),
                attributes: parseAttributes(object["attributes"])
            )
        }
    }

    private static func parseStyleTarget(
        _ value: Any?,
        resolver: IdentifierResolver
    ) -> GraphStyleTarget? {
        guard let object = value as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "canvas", "graph", "background":
            return .canvas
        case "node":
            guard let id = object["id"] as? String, let node = resolver.resolve(id) else { return nil }
            return .node(node)
        case "edge":
            guard let edge = parseEdgeReference(object, resolver: resolver) else { return nil }
            return .edge(edge)
        case "namedGraph":
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return .namedGraph(id)
        case "group":
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return .group(id)
        case "kind":
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return .kind(id)
        case "rdfType", "type":
            guard let id = object["id"] as? String,
                  let resolved = resolver.resolveIRI(id)
            else { return nil }
            return .rdfType(resolved)
        case "allNodes":
            return .allNodes
        case "allEdges":
            return .allEdges
        case "allGroups":
            return .allGroups
        default:
            return nil
        }
    }

    private static func parseStyle(
        _ object: [String: Any],
        target: GraphStyleTarget
    ) -> GraphStyle {
        let stroke = parseStroke(object)
        let edgeStyle = shouldParseEdgeStyle(target: target, object: object)
            ? parseEdgeStyle(object, stroke: stroke)
            : nil
        return GraphStyle(
            shape: parseShape(object["shape"], radius: object["radius"] ?? object["cornerRadius"]),
            fill: parsePaint(object["fill"]),
            stroke: stroke,
            text: parseTextStyle(object),
            edge: edgeStyle,
            opacity: object["opacity"] as? Double
        )
    }

    private static func shouldParseEdgeStyle(
        target: GraphStyleTarget,
        object: [String: Any]
    ) -> Bool {
        switch target {
        case .edge, .allEdges:
            return true
        case .kind:
            return hasEdgeSpecificProperties(object)
        case .canvas, .node, .namedGraph, .group, .rdfType, .allNodes, .allGroups:
            return false
        }
    }

    private static func hasEdgeSpecificProperties(_ object: [String: Any]) -> Bool {
        object["sourceMarker"] != nil
            || object["targetMarker"] != nil
            || object["edgeMarker"] != nil
            || object["edgeRoute"] != nil
            || object["route"] != nil
            || object["edgeLabel"] != nil
            || object["labelFill"] != nil
            || object["labelStroke"] != nil
            || object["labelTextColor"] != nil
            || object["labelTextWeight"] != nil
            || object["labelTextSize"] != nil
            || object["labelShape"] != nil
            || object["labelOpacity"] != nil
            || object["labelRadius"] != nil
            || object["labelCornerRadius"] != nil
            || object["labelStrokeWidth"] != nil
            || object["labelLineStyle"] != nil
    }

    private static func parseShape(_ value: Any?, radius: Any?) -> GraphShape? {
        if let object = value as? [String: Any],
           let type = object["type"] as? String {
            return parseShape(type, radius: object["radius"] ?? object["cornerRadius"] ?? radius)
        }
        guard let type = value as? String else { return nil }
        return parseShape(type, radius: radius)
    }

    private static func parseShape(_ type: String, radius: Any?) -> GraphShape? {
        switch type {
        case "rectangle":
            return .rectangle
        case "roundedRectangle":
            return .roundedRectangle(radius: radius as? Double)
        case "capsule":
            return .capsule
        case "ellipse":
            return .ellipse
        default:
            return nil
        }
    }

    private static func parseStroke(_ object: [String: Any]) -> GraphStroke? {
        let paint = parsePaint(object["stroke"])
        let width = object["strokeWidth"] as? Double
        let line = parseLineStyle(object["lineStyle"])
        guard paint != nil || width != nil || line != nil else { return nil }
        return GraphStroke(paint: paint, width: width, line: line)
    }

    private static func parseTextStyle(_ object: [String: Any]) -> GraphTextStyle? {
        let paint = parsePaint(object["textColor"])
        let weight = object["textWeight"] as? String
        let size = object["textSize"] as? Double
        guard paint != nil || weight != nil || size != nil else { return nil }
        return GraphTextStyle(paint: paint, weight: weight, size: size)
    }

    private static func parseEdgeStyle(
        _ object: [String: Any],
        stroke: GraphStroke?
    ) -> GraphEdgeStyle? {
        let sourceMarker = parseMarker(object["sourceMarker"])
        let targetMarker = parseMarker(object["targetMarker"] ?? object["edgeMarker"])
        let route = parseRoute(object["edgeRoute"] ?? object["route"])
        let label = parseEdgeLabelStyle(object)
        guard stroke != nil || sourceMarker != nil || targetMarker != nil || route != nil || label != nil else {
            return nil
        }
        return GraphEdgeStyle(
            stroke: stroke,
            sourceMarker: sourceMarker,
            targetMarker: targetMarker,
            route: route,
            label: label
        )
    }

    private static func parseEdgeLabelStyle(_ object: [String: Any]) -> GraphEdgeLabelStyle? {
        let labelObject = object["edgeLabel"] as? [String: Any] ?? object
        let shape = parseShape(
            labelObject["shape"] ?? object["labelShape"],
            radius: labelObject["radius"] ?? labelObject["cornerRadius"] ?? object["labelRadius"] ?? object["labelCornerRadius"]
        )
        let fill = parsePaint(labelObject["fill"] ?? object["labelFill"])
        let stroke = parseLabelStroke(labelObject: labelObject, object: object)
        let text = parseLabelTextStyle(labelObject: labelObject, object: object)
        let opacity = labelObject["opacity"] as? Double ?? object["labelOpacity"] as? Double
        guard shape != nil || fill != nil || stroke != nil || text != nil || opacity != nil else {
            return nil
        }
        return GraphEdgeLabelStyle(
            shape: shape,
            fill: fill,
            stroke: stroke,
            text: text,
            opacity: opacity
        )
    }

    private static func parseLabelStroke(
        labelObject: [String: Any],
        object: [String: Any]
    ) -> GraphStroke? {
        let paint = parsePaint(labelObject["stroke"] ?? object["labelStroke"])
        let width = labelObject["strokeWidth"] as? Double ?? object["labelStrokeWidth"] as? Double
        let line = parseLineStyle(labelObject["lineStyle"] ?? object["labelLineStyle"])
        guard paint != nil || width != nil || line != nil else { return nil }
        return GraphStroke(paint: paint, width: width, line: line)
    }

    private static func parseLabelTextStyle(
        labelObject: [String: Any],
        object: [String: Any]
    ) -> GraphTextStyle? {
        let paint = parsePaint(labelObject["textColor"] ?? object["labelTextColor"])
        let weight = labelObject["textWeight"] as? String ?? object["labelTextWeight"] as? String
        let size = labelObject["textSize"] as? Double ?? object["labelTextSize"] as? Double
        guard paint != nil || weight != nil || size != nil else { return nil }
        return GraphTextStyle(paint: paint, weight: weight, size: size)
    }

    private static func parsePaint(_ value: Any?) -> GraphPaint? {
        if let string = value as? String {
            if let color = parseHexColor(string) {
                return .color(color)
            }
            if string.hasPrefix("palette:") {
                return .palette(String(string.dropFirst("palette:".count)))
            }
            if string.hasPrefix("semantic:") {
                return .semantic(String(string.dropFirst("semantic:".count)))
            }
        }
        guard let object = value as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "color":
            if let hex = object["value"] as? String, let color = parseHexColor(hex) {
                return .color(color)
            }
            guard let red = object["red"] as? Double,
                  let green = object["green"] as? Double,
                  let blue = object["blue"] as? Double
            else { return nil }
            return .color(GraphColor(
                red: red,
                green: green,
                blue: blue,
                alpha: object["alpha"] as? Double ?? 1.0
            ))
        case "palette":
            guard let value = object["value"] as? String else { return nil }
            return .palette(value)
        case "semantic":
            guard let value = object["value"] as? String else { return nil }
            return .semantic(value)
        default:
            return nil
        }
    }

    private static func parseHexColor(_ string: String) -> GraphColor? {
        guard string.hasPrefix("#") else { return nil }
        let hex = String(string.dropFirst())
        guard hex.count == 6 || hex.count == 8,
              let value = UInt64(hex, radix: 16)
        else { return nil }
        if hex.count == 6 {
            return GraphColor(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )
        }
        return GraphColor(
            red: Double((value >> 24) & 0xFF) / 255.0,
            green: Double((value >> 16) & 0xFF) / 255.0,
            blue: Double((value >> 8) & 0xFF) / 255.0,
            alpha: Double(value & 0xFF) / 255.0
        )
    }

    private static func parseLineStyle(_ value: Any?) -> GraphLineStyle? {
        if let object = value as? [String: Any],
           let type = object["type"] as? String {
            switch type {
            case "dashed":
                return .dashed(pattern: object["pattern"] as? [Double])
            default:
                return parseLineStyle(type)
            }
        }
        guard let string = value as? String else { return nil }
        return parseLineStyle(string)
    }

    private static func parseLineStyle(_ string: String) -> GraphLineStyle? {
        switch string {
        case "solid":
            return .solid
        case "dashed":
            return .dashed(pattern: nil)
        case "dotted":
            return .dotted
        default:
            return nil
        }
    }

    private static func parseMarker(_ value: Any?) -> GraphMarker? {
        guard let string = value as? String else { return nil }
        return GraphMarker(rawValue: string)
    }

    private static func parseRoute(_ value: Any?) -> GraphEdgeRouteStyle? {
        guard let string = value as? String else { return nil }
        return GraphEdgeRouteStyle(rawValue: string)
    }

    private static func parseStylePriority(_ value: Any?) -> GraphStylePriority {
        guard let string = value as? String else { return .explicit }
        return GraphStylePriority(rawValue: string) ?? .explicit
    }

    private static func parseLayouts(
        _ value: Any?,
        resolver: IdentifierResolver
    ) -> [GraphLayoutDirective] {
        guard let layouts = value as? [[String: Any]] else { return [] }
        return layouts.enumerated().compactMap { offset, object in
            let items = parseReferences(object["items"], resolver: resolver)
            guard !items.isEmpty else { return nil }
            let arrangement = parseArrangement(object)
            return GraphLayoutDirective(
                id: object["id"] as? String ?? "layout:\(offset)",
                scope: parseReference(object["scope"], resolver: resolver),
                items: items,
                arrangement: arrangement,
                priority: parseLayoutPriority(object["priority"])
            )
        }
    }

    private static func parseArrangement(_ object: [String: Any]) -> GraphArrangement {
        let type = object["type"] as? String ?? object["arrangement"] as? String ?? "order"
        switch type {
        case "stack":
            return .stack(GraphStackArrangement(
                direction: parseDirection(object["direction"]) ?? .leftToRight,
                alignment: parseAlignment(object["alignment"]) ?? .center,
                spacing: object["spacing"] as? Double
            ))
        case "rank":
            return .rank(parseAxis(object["axis"]))
        case "grid":
            return .grid(columns: object["columns"] as? Int)
        case "pin":
            return .pin(parsePoint(object["point"]))
        case "align":
            return .align(parseAlignment(object["alignment"]) ?? .center)
        default:
            return .order
        }
    }

    private static func parseAxis(_ value: Any?) -> GraphAxis? {
        guard let string = value as? String else { return nil }
        return GraphAxis(rawValue: string)
    }

    private static func parseDirection(_ value: Any?) -> GraphStackDirection? {
        guard let string = value as? String else { return nil }
        return GraphStackDirection(rawValue: string)
    }

    private static func parseAlignment(_ value: Any?) -> GraphStackAlignment? {
        guard let string = value as? String else { return nil }
        return GraphStackAlignment(rawValue: string)
    }

    private static func parsePoint(_ value: Any?) -> GraphPoint? {
        guard let object = value as? [String: Any],
              let x = object["x"] as? Double,
              let y = object["y"] as? Double
        else { return nil }
        return GraphPoint(x: x, y: y)
    }

    private static func parseLayoutPriority(_ value: Any?) -> GraphLayoutPriority {
        guard let string = value as? String else { return .preferred }
        return GraphLayoutPriority(rawValue: string) ?? .preferred
    }

    private static func parseReferences(
        _ value: Any?,
        resolver: IdentifierResolver
    ) -> [GraphElementReference] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { parseReference($0, resolver: resolver) }
    }

    private static func parseReference(
        _ value: Any?,
        resolver: IdentifierResolver
    ) -> GraphElementReference? {
        if let string = value as? String {
            if string.hasPrefix("group:") && !resolver.hasPrefix("group") {
                return .group(string)
            }
            return resolver.resolve(string).map(GraphElementReference.node)
        }
        guard let object = value as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        switch type {
        case "node":
            guard let id = object["id"] as? String, let node = resolver.resolve(id) else { return nil }
            return .node(node)
        case "edge":
            return parseEdgeReference(object, resolver: resolver).map(GraphElementReference.edge)
        case "namedGraph":
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return .namedGraph(id)
        case "group":
            guard let id = object["id"] as? String, !id.isEmpty else { return nil }
            return .group(id)
        default:
            return nil
        }
    }

    private static func parseEdgeReference(
        _ object: [String: Any],
        resolver: IdentifierResolver
    ) -> EdgeIdentifier? {
        guard let sourceValue = object["source"] as? String,
              let predicate = object["predicate"] as? String,
              let targetValue = object["target"] as? String,
              let source = resolver.resolve(sourceValue),
              let predicate = resolver.resolveIRI(predicate),
              let target = resolver.resolve(targetValue)
        else { return nil }
        return EdgeIdentifier(
            source: source,
            predicate: predicate,
            target: target,
            namedGraph: object["namedGraph"] as? String
        )
    }

    private static func parseAttributes(_ value: Any?) -> [Attribute] {
        guard let object = value as? [String: Any] else { return [] }
        return object.keys.sorted().compactMap { key in
            guard let raw = object[key] else { return nil }
            if let string = raw as? String {
                return Attribute(key: key, value: string)
            }
            if let number = raw as? NSNumber {
                return Attribute(key: key, value: number.stringValue)
            }
            return nil
        }
    }

    private static func deduplicated(_ references: [GraphElementReference]) -> [GraphElementReference] {
        var result: [GraphElementReference] = []
        var seen: Set<GraphElementReference> = []
        for reference in references where seen.insert(reference).inserted {
            result.append(reference)
        }
        return result
    }

    struct IdentifierResolver {
        let prefixes: [String: String]

        init(context: Any?) {
            self.prefixes = Self.collectPrefixes(from: context)
        }

        func resolve(_ id: String) -> NodeIdentifier? {
            guard !id.isEmpty else { return nil }
            if id.hasPrefix("_:") {
                return .blank(String(id.dropFirst(2)))
            }
            return resolveIRI(id).map(NodeIdentifier.iri)
        }

        func resolveIRI(_ id: String) -> String? {
            guard !id.isEmpty else { return nil }
            if let colon = id.firstIndex(of: ":") {
                let prefix = String(id[..<colon])
                let suffix = String(id[id.index(after: colon)...])
                if let base = prefixes[prefix] {
                    return base + suffix
                }
            }
            guard IRI(id).isAbsolute else { return nil }
            return id
        }

        func hasPrefix(_ prefix: String) -> Bool {
            prefixes[prefix] != nil
        }

        private static func collectPrefixes(from context: Any?) -> [String: String] {
            var result: [String: String] = [:]
            collectPrefixes(from: context, into: &result)
            return result
        }

        private static func collectPrefixes(from context: Any?, into result: inout [String: String]) {
            if let array = context as? [Any] {
                for item in array {
                    collectPrefixes(from: item, into: &result)
                }
                return
            }
            guard let dictionary = context as? [String: Any] else { return }
            for (key, value) in dictionary {
                if let iri = value as? String,
                   iri.hasSuffix("#") || iri.hasSuffix("/") || iri.hasSuffix(":") {
                    result[key] = iri
                    continue
                }
                if let definition = value as? [String: Any],
                   let iri = definition["@id"] as? String,
                   iri.hasSuffix("#") || iri.hasSuffix("/") || iri.hasSuffix(":") {
                    result[key] = iri
                }
            }
        }
    }
}
