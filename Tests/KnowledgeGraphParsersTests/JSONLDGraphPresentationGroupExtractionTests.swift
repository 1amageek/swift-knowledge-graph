import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("JSON-LD graph presentation group extraction")
struct JSONLDGraphPresentationGroupExtractionTests {

    @Test
    func dropsGroupsWithMissingOrEmptyRequiredFields() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "groups": [
              { "title": "Missing ID", "members": ["ex:a"] },
              { "id": "", "title": "Empty ID", "members": ["ex:a"] },
              { "id": "group:no-title", "members": ["ex:a"] },
              { "id": "group:empty-title", "title": "", "members": ["ex:a"] },
              { "id": "group:valid", "title": "Valid", "members": ["ex:a"] }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))

        #expect(presentation.groups.map(\.id) == ["group:valid"])
    }

    @Test
    func resolvesAllReferenceFormsAndDropsInvalidMembers() throws {
        let payload = #"""
        {
          "@context": [
            { "ex": "http://example.org/" },
            { "alt": "urn:alt:" }
          ],
          "view": {
            "groups": [
              {
                "id": "group:refs",
                "title": "References",
                "members": [
                  "ex:a",
                  "http://example.org/absolute",
                  "https://example.org/secure",
                  "urn:item:1",
                  "_:blank",
                  "group:other",
                  "unknown:a",
                  "bare",
                  { "type": "node", "id": "alt:b" },
                  {
                    "type": "edge",
                    "source": "ex:a",
                    "predicate": "http://example.org/p",
                    "target": "_:blank",
                    "namedGraph": "http://example.org/g"
                  },
                  { "type": "namedGraph", "id": "http://example.org/g" },
                  { "type": "group", "id": "group:typed" },
                  { "type": "node", "id": "unregistered:b" },
                  { "type": "node", "id": "missing" },
                  { "type": "edge", "source": "unknown:a", "predicate": "p", "target": "ex:b" }
                ]
              }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))
        let group = try #require(presentation.groups.first)

        #expect(group.members == [
            .node(.iri("http://example.org/a")),
            .node(.iri("http://example.org/absolute")),
            .node(.iri("https://example.org/secure")),
            .node(.iri("urn:item:1")),
            .node(.blank("blank")),
            .group("group:other"),
            .node(.iri("unknown:a")),
            .node(.iri("urn:alt:b")),
            .edge(EdgeIdentifier(
                source: .iri("http://example.org/a"),
                predicate: "http://example.org/p",
                target: .blank("blank"),
                namedGraph: "http://example.org/g"
            )),
            .namedGraph("http://example.org/g"),
            .group("group:typed"),
            .node(.iri("unregistered:b"))
        ])
    }

    @Test
    func deduplicatesDirectAndTransitiveMembersInFirstSeenOrder() throws {
        let payload = #"""
        {
          "@context": { "ex": "http://example.org/" },
          "view": {
            "groups": [
              {
                "id": "group:root",
                "title": "Root",
                "members": ["ex:a", "ex:b", "ex:a"],
                "children": [
                  {
                    "id": "group:child",
                    "title": "Child",
                    "members": ["ex:b", "ex:c", "ex:c"]
                  }
                ]
              }
            ]
          },
          "@graph": []
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))
        let root = try #require(presentation.groups.first)

        #expect(root.members == [
            .node(.iri("http://example.org/a")),
            .node(.iri("http://example.org/b")),
            .node(.iri("http://example.org/c"))
        ])
        #expect(root.children.first?.members == [
            .node(.iri("http://example.org/b")),
            .node(.iri("http://example.org/c"))
        ])
    }

    @Test
    func extractsSortedStringAndNumericAttributes() throws {
        let payload = #"""
        {
          "view": {
            "groups": [
              {
                "id": "group:attributes",
                "title": "Attributes",
                "attributes": {
                  "zeta": "last",
                  "alpha": 3,
                  "ignored": { "nested": true }
                }
              }
            ]
          }
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))
        let group = try #require(presentation.groups.first)

        #expect(group.attributes == [
            Attribute(key: "alpha", value: "3"),
            Attribute(key: "zeta", value: "last")
        ])
    }

    @Test
    func resolvesPrefixesDeclaredAsJSONLDTermDefinitions() throws {
        let payload = #"""
        {
          "@context": {
            "ex": { "@id": "http://example.org/" }
          },
          "view": {
            "groups": [
              {
                "id": "group:term-definition",
                "title": "Term Definition",
                "members": ["ex:a"]
              }
            ]
          }
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))
        let group = try #require(presentation.groups.first)

        #expect(group.members == [
            .node(.iri("http://example.org/a"))
        ])
    }

    @Test
    func typedGroupReferenceAvoidsGroupSchemeAmbiguity() throws {
        let payload = #"""
        {
          "@context": {
            "group": "https://groups.example/"
          },
          "view": {
            "groups": [
              {
                "id": "group:ambiguous",
                "title": "Ambiguous",
                "members": [
                  "group:node",
                  { "type": "group", "id": "group:explicit" }
                ]
              }
            ]
          }
        }
        """#

        let presentation = try #require(try JSONLDGraphPresentationExtractor.presentation(from: payload))
        let group = try #require(presentation.groups.first)

        #expect(group.members == [
            .node(.iri("https://groups.example/node")),
            .group("group:explicit")
        ])
    }
}
