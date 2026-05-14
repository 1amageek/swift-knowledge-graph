import Foundation
import KnowledgeGraph
@testable import KnowledgeGraphParsers

/// A single entry pulled from `manifest.ttl` in the W3C Turtle test bundle.
struct W3CTurtleTestEntry: Sendable, CustomStringConvertible, Hashable {
    enum Kind: Sendable, Hashable {
        case eval
        case positiveSyntax
        case negativeSyntax
        case negativeEval
    }

    /// Short name (the fragment portion of the test's IRI), used purely for
    /// reporting. Test identity in swift-testing is set from `description`.
    let name: String
    let kind: Kind
    let inputURL: URL
    /// Only populated for `.eval` — the expected N-Triples result file.
    let expectedURL: URL?
    let testIRI: String

    var description: String { name }
}

/// Static index over the bundled W3C Turtle test manifest.
///
/// The manifest itself is parsed with `TurtleParser` — this is a deliberate
/// bootstrap: a regression in the manifest-supported subset of the grammar
/// will surface here long before the individual tests run. The lazy `static`
/// pays the parse cost exactly once.
enum W3CTurtleSuite {

    static let baseTestIRI = "http://www.w3.org/2013/TurtleTests/"
    static let manifestIRI = baseTestIRI + "manifest.ttl"

    private static let rdfType =
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    private static let mfAction =
        "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action"
    private static let mfResult =
        "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#result"
    private static let rdftEval =
        "http://www.w3.org/ns/rdftest#TestTurtleEval"
    private static let rdftPositive =
        "http://www.w3.org/ns/rdftest#TestTurtlePositiveSyntax"
    private static let rdftNegativeSyntax =
        "http://www.w3.org/ns/rdftest#TestTurtleNegativeSyntax"
    private static let rdftNegativeEval =
        "http://www.w3.org/ns/rdftest#TestTurtleNegativeEval"

    static let manifestURL: URL = {
        guard let url = Bundle.module.url(
            forResource: "manifest",
            withExtension: "ttl",
            subdirectory: "turtle-tests"
        ) else {
            fatalError("W3C Turtle manifest.ttl is not packaged as a test resource")
        }
        return url
    }()

    static let testsDirectory: URL = manifestURL.deletingLastPathComponent()

    static let allEntries: [W3CTurtleTestEntry] = {
        do {
            return try loadEntries()
        } catch {
            fatalError("Failed to load W3C Turtle manifest: \(error)")
        }
    }()

    static var evalEntries: [W3CTurtleTestEntry] {
        allEntries.filter { $0.kind == .eval }
    }

    static var positiveSyntaxEntries: [W3CTurtleTestEntry] {
        allEntries.filter { $0.kind == .positiveSyntax }
    }

    static var negativeSyntaxEntries: [W3CTurtleTestEntry] {
        allEntries.filter { $0.kind == .negativeSyntax }
    }

    static var negativeEvalEntries: [W3CTurtleTestEntry] {
        allEntries.filter { $0.kind == .negativeEval }
    }

    // MARK: - Loading

    private static func loadEntries() throws -> [W3CTurtleTestEntry] {
        let data = try Data(contentsOf: manifestURL)
        let text = String(decoding: data, as: UTF8.self)

        var context = ParsingContext(blankScopeID: "w3c-turtle-manifest")
        context.setBaseIRI(IRI(manifestIRI))
        var parser = TurtleParser(context: context)
        let graph = try parser.parse(text)

        var bySubject: [String: [Edge]] = [:]
        for edge in graph.edges where edge.id.source.kind == .iri {
            bySubject[edge.id.source.key, default: []].append(edge)
        }

        var entries: [W3CTurtleTestEntry] = []
        for (subjectIRI, edges) in bySubject {
            guard let kind = classify(edges: edges) else { continue }
            guard let action = singleObject(of: edges, predicate: mfAction),
                  action.kind == .iri else { continue }

            let inputURL = testsDirectory.appendingPathComponent(
                Self.lastPathComponent(of: action.key)
            )

            var expectedURL: URL?
            if kind == .eval,
               let result = singleObject(of: edges, predicate: mfResult),
               result.kind == .iri {
                expectedURL = testsDirectory.appendingPathComponent(
                    Self.lastPathComponent(of: result.key)
                )
            }

            let name = Self.fragment(of: subjectIRI) ?? subjectIRI
            entries.append(W3CTurtleTestEntry(
                name: name,
                kind: kind,
                inputURL: inputURL,
                expectedURL: expectedURL,
                testIRI: subjectIRI
            ))
        }
        return entries.sorted { $0.name < $1.name }
    }

    private static func classify(edges: [Edge]) -> W3CTurtleTestEntry.Kind? {
        for edge in edges where edge.id.predicate == rdfType {
            switch edge.id.target.key {
            case rdftEval: return .eval
            case rdftPositive: return .positiveSyntax
            case rdftNegativeSyntax: return .negativeSyntax
            case rdftNegativeEval: return .negativeEval
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

    private static func lastPathComponent(of absoluteIRI: String) -> String {
        if let lastSlash = absoluteIRI.lastIndex(of: "/") {
            let after = absoluteIRI.index(after: lastSlash)
            return String(absoluteIRI[after...])
        }
        return absoluteIRI
    }

    private static func fragment(of iri: String) -> String? {
        if let hash = iri.lastIndex(of: "#") {
            let after = iri.index(after: hash)
            return String(iri[after...])
        }
        return nil
    }
}
