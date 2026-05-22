import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD graph presentation layout extraction")
struct JSONLDGraphPresentationLayoutExtractionTests {

    @Test
    func extractsAllLayoutArrangements() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "layouts": [
              {
                "id": "layout:stack",
                "type": "stack",
                "direction": "bottomToTop",
                "alignment": "trailing",
                "spacing": 18,
                "scope": { "type": "group", "id": "group:root" },
                "items": ["ex:a", { "type": "group", "id": "group:b" }],
                "priority": "required"
              },
              {
                "id": "layout:order",
                "type": "order",
                "items": ["ex:a"]
              },
              {
                "id": "layout:rank",
                "type": "rank",
                "axis": "horizontal",
                "items": ["ex:a"]
              },
              {
                "id": "layout:grid",
                "type": "grid",
                "columns": 4,
                "items": ["ex:a"]
              },
              {
                "id": "layout:pin",
                "type": "pin",
                "point": { "x": 10, "y": 20 },
                "items": ["ex:a"]
              },
              {
                "id": "layout:align",
                "type": "align",
                "alignment": "stretch",
                "items": ["ex:a"]
              }
            ]
          }
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.layouts.count == 6)

        let stackLayout = presentation.layouts[0]
        #expect(stackLayout.id == "layout:stack")
        #expect(stackLayout.scope == .group("group:root"))
        #expect(stackLayout.items == [
            .node(.iri("http://example.org/a")),
            .group("group:b")
        ])
        #expect(stackLayout.priority == .required)
        guard case .stack(let stack) = stackLayout.arrangement else {
            Issue.record("Expected stack arrangement")
            return
        }
        #expect(stack.axis == .vertical)
        #expect(stack.direction == .bottomToTop)
        #expect(stack.alignment == .trailing)
        #expect(stack.spacing == 18)

        #expect(presentation.layouts[1].arrangement == .order)
        #expect(presentation.layouts[2].arrangement == .rank(.horizontal))
        #expect(presentation.layouts[3].arrangement == .grid(columns: 4))
        #expect(presentation.layouts[4].arrangement == .pin(GraphPoint(x: 10, y: 20)))
        #expect(presentation.layouts[5].arrangement == .align(.stretch))
    }

    @Test
    func appliesLayoutDefaultsAndFallbacks() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "layouts": [
              {
                "type": "stack",
                "direction": "not-direction",
                "alignment": "not-alignment",
                "items": ["ex:a"],
                "priority": "not-priority"
              },
              {
                "arrangement": "align",
                "alignment": "not-alignment",
                "items": ["ex:a"]
              },
              {
                "type": "unknown",
                "items": ["ex:a"]
              },
              {
                "type": "pin",
                "point": { "x": "invalid", "y": 20 },
                "items": ["ex:a"]
              },
              {
                "type": "grid",
                "items": ["ex:a"]
              }
            ]
          }
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.layouts.count == 5)
        #expect(presentation.layouts[0].id == "layout:0")
        #expect(presentation.layouts[0].priority == .preferred)
        guard case .stack(let stack) = presentation.layouts[0].arrangement else {
            Issue.record("Expected stack arrangement")
            return
        }
        #expect(stack.axis == .horizontal)
        #expect(stack.direction == .leftToRight)
        #expect(stack.alignment == .center)
        #expect(stack.spacing == nil)
        #expect(presentation.layouts[1].arrangement == .align(.center))
        #expect(presentation.layouts[2].arrangement == .order)
        #expect(presentation.layouts[3].arrangement == .pin(nil))
        #expect(presentation.layouts[4].arrangement == .grid(columns: nil))
    }

    @Test
    func dropsLayoutsWithoutResolvableItemsAndKeepsMixedValidItems() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "layouts": [
              {
                "id": "layout:invalid-only",
                "items": ["bare", { "type": "node", "id": "missing" }]
              },
              {
                "id": "layout:mixed",
                "items": [
                  "bare",
                  "ex:a",
                  {
                    "type": "edge",
                    "source": "ex:a",
                    "predicate": "http://example.org/p",
                    "target": "ex:b"
                  },
                  { "type": "namedGraph", "id": "http://example.org/g" },
                  { "type": "group", "id": "group:g" }
                ]
              }
            ]
          }
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.layouts.count == 1)
        #expect(presentation.layouts[0].id == "layout:mixed")
        #expect(presentation.layouts[0].items == [
            .node(.iri("http://example.org/a")),
            .edge(EdgeIdentifier(
                source: .iri("http://example.org/a"),
                predicate: "http://example.org/p",
                target: .iri("http://example.org/b")
            )),
            .namedGraph("http://example.org/g"),
            .group("group:g")
        ])
    }
}
