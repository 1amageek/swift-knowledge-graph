import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD graph presentation extraction")
struct JSONLDGraphPresentationExtractorTests {

    @Test
    func extractsNestedGroupsWithTransitiveMembership() throws {
        let payload = #"""
        {
          "@context": {
            "ex": "http://example.org/"
          },
          "view": {
            "groups": [
              {
                "id": "group:layer/context",
                "kind": "layer",
                "title": "Context",
                "children": [
                  {
                    "id": "group:category/context/market",
                    "kind": "category",
                    "title": "Market",
                    "members": ["ex:alice", "ex:bob"]
                  },
                  {
                    "id": "group:category/context/demand",
                    "kind": "category",
                    "title": "Demand",
                    "members": ["ex:carol"]
                  }
                ]
              }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.groups.count == 1)
        let layer = try #require(presentation.groups.first)
        #expect(layer.id == "group:layer/context")
        #expect(layer.title == "Context")
        #expect(layer.kind == "layer")
        #expect(layer.members == [
            .node(.iri("http://example.org/alice")),
            .node(.iri("http://example.org/bob")),
            .node(.iri("http://example.org/carol"))
        ])
        #expect(layer.children.map(\.id) == [
            "group:category/context/market",
            "group:category/context/demand"
        ])
    }

    @Test
    func extractsShapeAndEdgeStyles() throws {
        let payload = #"""
        {
          "@context": {
            "ex": "http://example.org/"
          },
          "view": {
            "styles": [
              {
                "id": "style:node",
                "target": { "type": "node", "id": "ex:alice" },
                "shape": "capsule",
                "fill": "#22AA88",
                "stroke": "#115544",
                "strokeWidth": 2,
                "textColor": "#FFFFFF"
              },
              {
                "id": "style:route",
                "target": { "type": "kind", "id": "airRoute" },
                "lineStyle": "dashed",
                "stroke": "#7C5CFF",
                "edgeMarker": "arrow",
                "edgeRoute": "orthogonal"
              }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.styles.count == 2)
        let nodeStyle = presentation.styles[0]
        #expect(nodeStyle.target == .node(.iri("http://example.org/alice")))
        #expect(nodeStyle.style.shape == .capsule)
        #expect(nodeStyle.style.fill == .color(GraphColor(
            red: 34.0 / 255.0,
            green: 170.0 / 255.0,
            blue: 136.0 / 255.0
        )))
        #expect(nodeStyle.style.stroke?.width == 2)

        let routeStyle = presentation.styles[1]
        #expect(routeStyle.target == .kind("airRoute"))
        #expect(routeStyle.style.stroke?.line == .dashed(pattern: nil))
        #expect(routeStyle.style.edge?.targetMarker == .arrow)
        #expect(routeStyle.style.edge?.route == .orthogonal)
    }

    @Test
    func extractsStackLayoutDirective() throws {
        let payload = #"""
        {
          "@context": {
            "ex": "http://example.org/"
          },
          "view": {
            "layouts": [
              {
                "id": "layout:stages",
                "type": "stack",
                "direction": "leftToRight",
                "alignment": "center",
                "spacing": 48,
                "items": [
                  { "type": "group", "id": "group:source" },
                  { "type": "group", "id": "group:dc" },
                  { "type": "node", "id": "ex:final" }
                ]
              }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))
        let layout = try #require(presentation.layouts.first)

        #expect(layout.id == "layout:stages")
        #expect(layout.items == [
            .group("group:source"),
            .group("group:dc"),
            .node(.iri("http://example.org/final"))
        ])
        guard case .stack(let stack) = layout.arrangement else {
            Issue.record("Expected stack arrangement")
            return
        }
        #expect(stack.axis == .horizontal)
        #expect(stack.direction == .leftToRight)
        #expect(stack.alignment == .center)
        #expect(stack.spacing == 48)
    }
}
