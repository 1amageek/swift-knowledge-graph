import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD graph presentation style extraction")
struct JSONLDGraphPresentationStyleExtractionTests {

    @Test
    func extractsEverySupportedStyleTarget() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "styles": [
              { "target": { "type": "node", "id": "ex:a" }, "shape": "rectangle" },
              {
                "target": {
                  "type": "edge",
                  "source": "ex:a",
                  "predicate": "http://example.org/p",
                  "target": "ex:b"
                },
                "lineStyle": "solid"
              },
              { "target": { "type": "namedGraph", "id": "http://example.org/g" }, "fill": "semantic:graph" },
              { "target": { "type": "group", "id": "group:a" }, "fill": "palette:group" },
              { "target": { "type": "kind", "id": "hub" }, "shape": "capsule" },
              { "target": { "type": "type", "id": "http://example.org/Type" }, "shape": "ellipse" },
              { "target": { "type": "rdfType", "id": "http://example.org/OtherType" }, "shape": "roundedRectangle" },
              { "target": { "type": "allNodes" }, "stroke": "#111111" },
              { "target": { "type": "allEdges" }, "lineStyle": "dotted" },
              { "target": { "type": "allGroups" }, "fill": "#222222" },
              { "target": { "type": "unknown", "id": "x" }, "shape": "rectangle" }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.styles.map(\.target) == [
            .element(.node(.iri("http://example.org/a"))),
            .element(.edge(EdgeIdentifier(
                source: .iri("http://example.org/a"),
                predicate: "http://example.org/p",
                target: .iri("http://example.org/b")
            ))),
            .element(.namedGraph("http://example.org/g")),
            .element(.group("group:a")),
            .kind("hub"),
            .type("http://example.org/Type"),
            .type("http://example.org/OtherType"),
            .allNodes,
            .allEdges,
            .allGroups
        ])
    }

    @Test
    func extractsShapesPaintsStrokeTextOpacityAndPriorities() throws {
        let payload = #"""
        {
          "view": {
            "styles": [
              {
                "id": "style:rounded",
                "priority": "default",
                "target": { "type": "allNodes" },
                "shape": { "type": "roundedRectangle", "radius": 12 },
                "fill": "#33669980",
                "stroke": { "type": "color", "red": 0.1, "green": 0.2, "blue": 0.3, "alpha": 0.4 },
                "strokeWidth": 2.5,
                "lineStyle": { "type": "dashed", "pattern": [6, 3] },
                "textColor": { "type": "semantic", "value": "label" },
                "textWeight": "semibold",
                "textSize": 14,
                "opacity": 0.75
              },
              {
                "id": "style:palette",
                "priority": "theme",
                "target": { "type": "allGroups" },
                "shape": "capsule",
                "fill": { "type": "palette", "value": "stage" },
                "stroke": "palette:border"
              },
              {
                "id": "style:semantic",
                "priority": "override",
                "target": { "type": "allEdges" },
                "stroke": "semantic:route",
                "lineStyle": "dotted"
              },
              {
                "target": { "type": "allNodes" },
                "shape": "ellipse",
                "priority": "not-a-priority"
              }
            ]
          }
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.styles.count == 4)

        let rounded = presentation.styles[0]
        #expect(rounded.id == "style:rounded")
        #expect(rounded.priority == .default)
        #expect(rounded.style.shape == .roundedRectangle(radius: 12))
        #expect(rounded.style.fill == .color(GraphColor(
            red: 0x33 / 255.0,
            green: 0x66 / 255.0,
            blue: 0x99 / 255.0,
            alpha: 0x80 / 255.0
        )))
        #expect(rounded.style.stroke?.paint == .color(GraphColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)))
        #expect(rounded.style.stroke?.width == 2.5)
        #expect(rounded.style.stroke?.line == .dashed(pattern: [6, 3]))
        #expect(rounded.style.edge == nil)
        #expect(rounded.style.text == GraphTextStyle(
            paint: .semantic("label"),
            weight: "semibold",
            size: 14
        ))
        #expect(rounded.style.opacity == 0.75)

        let palette = presentation.styles[1]
        #expect(palette.priority == .theme)
        #expect(palette.style.shape == .capsule)
        #expect(palette.style.fill == .palette("stage"))
        #expect(palette.style.stroke?.paint == .palette("border"))
        #expect(palette.style.edge == nil)

        let semantic = presentation.styles[2]
        #expect(semantic.priority == .override)
        #expect(semantic.style.stroke?.paint == .semantic("route"))
        #expect(semantic.style.stroke?.line == .dotted)
        #expect(semantic.style.edge?.stroke?.line == .dotted)

        let fallback = presentation.styles[3]
        #expect(fallback.id == "style:3")
        #expect(fallback.priority == .explicit)
        #expect(fallback.style.shape == .ellipse)
    }

    @Test
    func extractsEdgeStyleMarkersRoutesAndFallbackMarkerAlias() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "styles": [
              {
                "target": {
                  "type": "edge",
                  "source": "ex:a",
                  "predicate": "http://example.org/p",
                  "target": "ex:b",
                  "namedGraph": "http://example.org/g"
                },
                "stroke": "#7C5CFF",
                "lineStyle": "dashed",
                "sourceMarker": "circle",
                "targetMarker": "diamond",
                "route": "curved"
              },
              {
                "target": { "type": "allEdges" },
                "edgeMarker": "arrow",
                "edgeRoute": "straight"
              },
              {
                "target": { "type": "allEdges" },
                "sourceMarker": "none",
                "targetMarker": "not-a-marker",
                "edgeRoute": "not-a-route",
                "lineStyle": { "type": "solid" }
              }
            ]
          }
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))

        let edge = presentation.styles[0]
        #expect(edge.target == .element(.edge(EdgeIdentifier(
            source: .iri("http://example.org/a"),
            predicate: "http://example.org/p",
            target: .iri("http://example.org/b"),
            namedGraph: "http://example.org/g"
        ))))
        #expect(edge.style.edge?.stroke?.line == .dashed(pattern: nil))
        #expect(edge.style.edge?.sourceMarker == .circle)
        #expect(edge.style.edge?.targetMarker == .diamond)
        #expect(edge.style.edge?.route == .curved)

        let alias = presentation.styles[1]
        #expect(alias.style.edge?.targetMarker == .arrow)
        #expect(alias.style.edge?.route == .straight)

        let invalid = presentation.styles[2]
        #expect(invalid.style.edge?.sourceMarker == GraphMarker.none)
        #expect(invalid.style.edge?.targetMarker == nil)
        #expect(invalid.style.edge?.route == nil)
        #expect(invalid.style.stroke?.line == .solid)
    }

    @Test
    func dropsInvalidTargetsAndEmptyStyles() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "styles": [
              { "target": { "type": "node", "id": "unknown:a" }, "shape": "rectangle" },
              { "target": { "type": "node", "id": "bare" }, "shape": "capsule" },
              { "target": { "type": "allNodes" }, "shape": "not-a-shape" },
              { "target": { "type": "allNodes" }, "fill": "#XYZXYZ" },
              { "target": { "type": "allNodes" }, "stroke": { "type": "color", "value": "#XYZXYZ" } },
              { "target": { "type": "allNodes" }, "shape": "rectangle" }
            ]
          }
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.styles.count == 2)
        #expect(presentation.styles[0].target == .element(.node(.iri("unknown:a"))))
        #expect(presentation.styles[0].style.shape == .rectangle)
        #expect(presentation.styles[1].target == .allNodes)
        #expect(presentation.styles[1].style.shape == .rectangle)
    }

    @Test
    func extractsSortedStyleAttributes() throws {
        let payload = #"""
        {
          "view": {
            "styles": [
              {
                "target": { "type": "allNodes" },
                "shape": "rectangle",
                "attributes": {
                  "z": "last",
                  "a": 2,
                  "ignored": ["x"]
                }
              }
            ]
          }
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))
        let style = try #require(presentation.styles.first)

        #expect(style.attributes == [
            Attribute(key: "a", value: "2"),
            Attribute(key: "z", value: "last")
        ])
    }

    @Test
    func resolvesCuriePredicatesAndRDFTypeTargets() throws {
        let payload = #"""
        {
          "@context": {
            "ex": "http://example.org/"
          },
          "view": {
            "styles": [
              {
                "target": {
                  "type": "edge",
                  "source": "ex:a",
                  "predicate": "ex:p",
                  "target": "ex:b"
                },
                "lineStyle": "solid"
              },
              {
                "target": { "type": "rdfType", "id": "ex:Type" },
                "shape": "roundedRectangle"
              }
            ]
          }
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.styles.map(\.target) == [
            .element(.edge(EdgeIdentifier(
                source: .iri("http://example.org/a"),
                predicate: "http://example.org/p",
                target: .iri("http://example.org/b")
            ))),
            .type("http://example.org/Type")
        ])
    }

    @Test
    func resolvesGeneralAbsoluteIRISchemes() throws {
        let payload = #"""
        {
          "view": {
            "styles": [
              {
                "target": { "type": "node", "id": "did:example:alice" },
                "shape": "rectangle"
              },
              {
                "target": {
                  "type": "edge",
                  "source": "did:example:alice",
                  "predicate": "tag:example.org,2026:knows",
                  "target": "mailto:bob@example.org"
                },
                "lineStyle": "solid"
              },
              {
                "target": { "type": "rdfType", "id": "tag:example.org,2026:Person" },
                "shape": "capsule"
              }
            ]
          }
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.styles.map(\.target) == [
            .element(.node(.iri("did:example:alice"))),
            .element(.edge(EdgeIdentifier(
                source: .iri("did:example:alice"),
                predicate: "tag:example.org,2026:knows",
                target: .iri("mailto:bob@example.org")
            ))),
            .type("tag:example.org,2026:Person")
        ])
    }
}
