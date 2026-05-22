import Foundation
import Testing
@testable import KnowledgeGraph

@Suite("GraphPresentation Codable")
struct GraphPresentationCodableTests {

    @Test
    func graphPresentationRoundTripsThroughJSON() throws {
        let edge = EdgeIdentifier(
            source: .iri("http://example.org/source"),
            predicate: "http://example.org/predicate",
            target: .blank("target"),
            namedGraph: "http://example.org/graph"
        )
        let presentation = GraphPresentation(
            id: "presentation:test",
            title: "Test presentation",
            groups: [
                GraphPresentationGroup(
                    id: "group:root",
                    title: "Root",
                    kind: "stage",
                    members: [
                        .node(.iri("http://example.org/source")),
                        .edge(edge),
                        .namedGraph("http://example.org/graph"),
                        .group("group:child")
                    ],
                    children: [
                        GraphPresentationGroup(
                            id: "group:child",
                            title: "Child",
                            kind: "category",
                            members: [.node(.blank("target"))],
                            attributes: [Attribute(key: "rank", value: "1")]
                        )
                    ],
                    attributes: [Attribute(key: "stage", value: "root")]
                )
            ],
            layouts: [
                GraphLayoutDirective(
                    id: "layout:stack",
                    scope: .group("group:root"),
                    items: [
                        .group("group:child"),
                        .node(.iri("http://example.org/source")),
                        .edge(edge)
                    ],
                    arrangement: .stack(GraphStackArrangement(
                        direction: .leftToRight,
                        alignment: .center,
                        spacing: 32
                    )),
                    priority: .required
                ),
                GraphLayoutDirective(
                    id: "layout:pin",
                    items: [.node(.iri("http://example.org/source"))],
                    arrangement: .pin(GraphPoint(x: 10, y: 20))
                )
            ],
            styles: [
                GraphStyleRule(
                    id: "style:node",
                    target: .node(.iri("http://example.org/source")),
                    style: GraphStyle(
                        shape: .roundedRectangle(radius: 8),
                        fill: .color(GraphColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)),
                        stroke: GraphStroke(
                            paint: .palette("accent"),
                            width: 2,
                            line: .dashed(pattern: [4, 2])
                        ),
                        text: GraphTextStyle(
                            paint: .semantic("onAccent"),
                            weight: "bold",
                            size: 13
                        ),
                        opacity: 0.9
                    ),
                    priority: .override,
                    attributes: [Attribute(key: "source", value: "test")]
                ),
                GraphStyleRule(
                    id: "style:edge",
                    target: .edge(edge),
                    style: GraphStyle(
                        stroke: GraphStroke(
                            paint: .color(GraphColor(red: 0.4, green: 0.5, blue: 0.6)),
                            width: 1.5,
                            line: .dotted
                        ),
                        edge: GraphEdgeStyle(
                            stroke: GraphStroke(line: .solid),
                            sourceMarker: .circle,
                            targetMarker: .diamond,
                            route: .orthogonal
                        )
                    ),
                    priority: .theme
                )
            ]
        )

        let data = try JSONEncoder().encode(presentation)
        let decoded = try JSONDecoder().decode(GraphPresentation.self, from: data)

        #expect(decoded == presentation)
    }

    @Test
    func individualLayoutArrangementsRoundTripThroughJSON() throws {
        let directives = [
            GraphLayoutDirective(
                id: "layout:order",
                items: [.node(.iri("http://example.org/a"))],
                arrangement: .order
            ),
            GraphLayoutDirective(
                id: "layout:rank",
                items: [.node(.iri("http://example.org/a"))],
                arrangement: .rank(.vertical)
            ),
            GraphLayoutDirective(
                id: "layout:grid",
                items: [.node(.iri("http://example.org/a"))],
                arrangement: .grid(columns: 3)
            ),
            GraphLayoutDirective(
                id: "layout:align",
                items: [.node(.iri("http://example.org/a"))],
                arrangement: .align(.stretch)
            )
        ]

        let data = try JSONEncoder().encode(directives)
        let decoded = try JSONDecoder().decode([GraphLayoutDirective].self, from: data)

        #expect(decoded == directives)
    }

    @Test
    func stackArrangementCodableSchemaDoesNotStoreAxis() throws {
        let directive = GraphLayoutDirective(
            id: "layout:stack",
            items: [.node(.iri("http://example.org/a"))],
            arrangement: .stack(GraphStackArrangement(
                direction: .topToBottom,
                alignment: .stretch,
                spacing: 12
            ))
        )

        let data = try JSONEncoder().encode(directive)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let arrangement = try #require(root["arrangement"] as? [String: Any])
        let stack = try #require(arrangement["stack"] as? [String: Any])

        #expect(arrangement["type"] as? String == "stack")
        #expect(stack["direction"] as? String == "topToBottom")
        #expect(stack["alignment"] as? String == "stretch")
        #expect(stack["spacing"] as? Double == 12)
        #expect(stack["axis"] == nil)
    }

    @Test
    func styleCodableSchemaUsesExplicitTypeFields() throws {
        let rule = GraphStyleRule(
            id: "style:schema",
            target: .rdfType("http://example.org/Type"),
            style: GraphStyle(
                shape: .roundedRectangle(radius: 10),
                fill: .palette("stage"),
                stroke: GraphStroke(line: .dashed(pattern: [4, 2]))
            )
        )

        let data = try JSONEncoder().encode(rule)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let target = try #require(root["target"] as? [String: Any])
        let style = try #require(root["style"] as? [String: Any])
        let shape = try #require(style["shape"] as? [String: Any])
        let fill = try #require(style["fill"] as? [String: Any])
        let stroke = try #require(style["stroke"] as? [String: Any])
        let line = try #require(stroke["line"] as? [String: Any])

        #expect(target["type"] as? String == "rdfType")
        #expect(target["id"] as? String == "http://example.org/Type")
        #expect(shape["type"] as? String == "roundedRectangle")
        #expect(shape["radius"] as? Double == 10)
        #expect(fill["type"] as? String == "palette")
        #expect(fill["value"] as? String == "stage")
        #expect(line["type"] as? String == "dashed")
        #expect(line["pattern"] as? [Double] == [4, 2])
    }
}
