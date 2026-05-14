import Foundation
import KnowledgeGraph
@testable import KnowledgeGraphParsers

/// A single entry pulled from `manifest.ttl` in the W3C RDF/XML test
/// bundle.
///
/// The W3C RDF/XML manifest uses `rdft:TestXMLEval` /
/// `rdft:TestXMLNegativeSyntax` and points `mf:action` at a relative
/// path that may include a subdirectory. The loader preserves that path
/// so the input file can be located inside the packaged resource tree.
struct W3CRDFXMLTestEntry: Sendable, CustomStringConvertible, Hashable {
    enum Kind: Sendable, Hashable {
        case eval
        case negativeSyntax
    }

    let name: String
    let kind: Kind
    let inputURL: URL
    /// Only populated for `.eval` — the expected N-Triples result file.
    let expectedURL: URL?
    /// Base IRI to feed the parser. Per the W3C testing convention, this is
    /// the test action IRI resolved against the manifest base.
    let baseIRI: String

    var description: String { name }
}

enum W3CRDFXMLSuite {

    static let baseTestIRI = "http://www.w3.org/2013/RDFXMLTests/"
    static let manifestIRI = baseTestIRI + "manifest.ttl"

    private static let rdfType =
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    private static let mfAction =
        "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action"
    private static let mfResult =
        "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#result"
    private static let rdftEval =
        "http://www.w3.org/ns/rdftest#TestXMLEval"
    private static let rdftNegativeSyntax =
        "http://www.w3.org/ns/rdftest#TestXMLNegativeSyntax"

    static let manifestURL: URL = {
        guard let url = Bundle.module.url(
            forResource: "manifest",
            withExtension: "ttl",
            subdirectory: "rdfxml-tests"
        ) else {
            fatalError("W3C RDF/XML manifest.ttl is not packaged as a test resource")
        }
        return url
    }()

    static let testsDirectory: URL = manifestURL.deletingLastPathComponent()

    static let allEntries: [W3CRDFXMLTestEntry] = {
        do {
            return try loadEntries()
        } catch {
            fatalError("Failed to load W3C RDF/XML manifest: \(error)")
        }
    }()

    static var evalEntries: [W3CRDFXMLTestEntry] {
        allEntries.filter { $0.kind == .eval }
    }

    static var negativeSyntaxEntries: [W3CRDFXMLTestEntry] {
        allEntries.filter { $0.kind == .negativeSyntax }
    }

    // MARK: - Loading

    /// The manifest itself is Turtle, so parse it with `TurtleParser`. The
    /// action / result references resolve relative to the manifest IRI.
    private static func loadEntries() throws -> [W3CRDFXMLTestEntry] {
        let data = try Data(contentsOf: manifestURL)
        let text = String(decoding: data, as: UTF8.self)

        var context = ParsingContext(blankScopeID: "w3c-rdfxml-manifest")
        context.setBaseIRI(IRI(manifestIRI))
        var parser = TurtleParser(context: context)
        let graph = try parser.parse(text)

        var bySubject: [String: [Edge]] = [:]
        for edge in graph.edges where edge.id.source.kind == .iri {
            bySubject[edge.id.source.key, default: []].append(edge)
        }

        var entries: [W3CRDFXMLTestEntry] = []
        for (subjectIRI, edges) in bySubject {
            guard let kind = classify(edges: edges) else { continue }
            guard let action = singleObject(of: edges, predicate: mfAction),
                  action.kind == .iri else { continue }

            // action.key is already an absolute IRI like
            // "http://www.w3.org/2013/RDFXMLTests/amp-in-url/test001.rdf".
            // Take the path component below the manifest base to locate the
            // input file inside the packaged resource directory.
            let relativeInputPath = relativeTo(absolute: action.key, base: baseTestIRI)
            let inputURL = testsDirectory.appendingPathComponent(relativeInputPath)

            var expectedURL: URL?
            if kind == .eval,
               let result = singleObject(of: edges, predicate: mfResult),
               result.kind == .iri {
                let relativeExpectedPath = relativeTo(absolute: result.key, base: baseTestIRI)
                expectedURL = testsDirectory.appendingPathComponent(relativeExpectedPath)
            }

            let name = Self.fragment(of: subjectIRI) ?? subjectIRI
            entries.append(W3CRDFXMLTestEntry(
                name: name,
                kind: kind,
                inputURL: inputURL,
                expectedURL: expectedURL,
                baseIRI: action.key
            ))
        }
        return entries.sorted { $0.name < $1.name }
    }

    private static func classify(edges: [Edge]) -> W3CRDFXMLTestEntry.Kind? {
        for edge in edges where edge.id.predicate == rdfType {
            switch edge.id.target.key {
            case rdftEval: return .eval
            case rdftNegativeSyntax: return .negativeSyntax
            default: continue
            }
        }
        return nil
    }

    private static func singleObject(of edges: [Edge], predicate: String) -> NodeIdentifier? {
        for edge in edges where edge.id.predicate == predicate {
            return edge.id.target
        }
        return nil
    }

    private static func relativeTo(absolute: String, base: String) -> String {
        if absolute.hasPrefix(base) {
            return String(absolute.dropFirst(base.count))
        }
        // Fallback: use the last path component if the absolute IRI does not
        // share the expected base prefix. This should not happen for the
        // vendored manifest, but raising here would make the suite refuse
        // to load over a single odd entry.
        if let lastSlash = absolute.lastIndex(of: "/") {
            let after = absolute.index(after: lastSlash)
            return String(absolute[after...])
        }
        return absolute
    }

    private static func fragment(of iri: String) -> String? {
        if let hash = iri.lastIndex(of: "#") {
            let after = iri.index(after: hash)
            return String(iri[after...])
        }
        return nil
    }
}
