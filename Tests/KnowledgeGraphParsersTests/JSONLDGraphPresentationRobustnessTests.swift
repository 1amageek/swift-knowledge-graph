import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD graph presentation robustness")
struct JSONLDGraphPresentationRobustnessTests {

    @Test
    func throwsForMalformedOrInvalidRootPayloads() {
        do {
            _ = try JSONLDGraphPresentationExtractor.presentation(from: "{")
            Issue.record("Expected malformed JSON to throw")
        } catch JSONLDGraphPresentationExtractionError.invalidJSON(_) {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        do {
            _ = try JSONLDGraphPresentationExtractor.presentation(from: #"[]"#)
            Issue.record("Expected non-object root to throw")
        } catch JSONLDGraphPresentationExtractionError.invalidRoot {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func returnsNilForMissingOrEmptyViewPayloads() throws {
        #expect(try JSONLDGraphPresentationExtractor.presentation(from: #"{"@graph":[]}"#) == nil)
        #expect(try JSONLDGraphPresentationExtractor.presentation(from: #"{"view":{}}"#) == nil)
        #expect(try JSONLDGraphPresentationExtractor.presentation(from: #"{"view":{"groups":{},"styles":{},"layouts":{}}}"#) == nil)
    }

    @Test
    func documentUsesEmptyPresentationListWhenExtractionReturnsNil() throws {
        let graph = KnowledgeGraph(nodes: [Node(id: .iri("http://example.org/a"))])
        let document = try JSONLDGraphPresentationExtractor.document(
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

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(
            from: payload,
            id: "presentation:custom",
            title: "Custom"
        ))

        #expect(presentation.id == "presentation:custom")
        #expect(presentation.title == "Custom")
    }
}
