import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD graph presentation robustness")
struct JSONLDGraphPresentationRobustnessTests {

    @Test
    func returnsNilForMalformedOrMissingViewPayloads() {
        #expect(JSONLDGraphPresentationExtractor.presentation(from: "{") == nil)
        #expect(JSONLDGraphPresentationExtractor.presentation(from: #"[]"#) == nil)
        #expect(JSONLDGraphPresentationExtractor.presentation(from: #"{"@graph":[]}"#) == nil)
        #expect(JSONLDGraphPresentationExtractor.presentation(from: #"{"view":{}}"#) == nil)
        #expect(JSONLDGraphPresentationExtractor.presentation(from: #"{"view":{"groups":{},"styles":{},"layouts":{}}}"#) == nil)
    }

    @Test
    func documentUsesEmptyPresentationListWhenExtractionReturnsNil() {
        let graph = KnowledgeGraph(nodes: [Node(id: .iri("http://example.org/a"))])
        let document = JSONLDGraphPresentationExtractor.document(
            graph: graph,
            payload: #"{"@graph":[]}"#,
            presentationID: "presentation:missing",
            title: "Missing"
        )

        #expect(document.graph == graph)
        #expect(document.presentations.isEmpty)
    }

    @Test
    func preservesRequestedPresentationIdentityAndTitle() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "styles": [
              {
                "target": { "type": "allNodes" },
                "shape": "rectangle"
              }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(JSONLDGraphPresentationExtractor.presentation(
            from: payload,
            id: "presentation:custom",
            title: "Custom"
        ))

        #expect(presentation.id == "presentation:custom")
        #expect(presentation.title == "Custom")
    }
}
