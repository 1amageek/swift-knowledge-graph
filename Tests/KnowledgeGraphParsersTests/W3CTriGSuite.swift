import Foundation
import KnowledgeGraph
@testable import KnowledgeGraphParsers

/// A single entry pulled from `manifest.ttl` in the W3C TriG test bundle.
///
/// The W3C TriG manifest reuses the `rdft:Test*` vocabulary from Turtle but
/// substitutes `Trig` (lowercase `g`) for `Turtle` in each class name. The
/// loader translates between the two and otherwise mirrors `W3CTurtleSuite`.
struct W3CTriGTestEntry: Sendable, CustomStringConvertible, Hashable {
    enum Kind: Sendable, Hashable {
        case eval
        case positiveSyntax
        case negativeSyntax
        case negativeEval
    }

    let name: String
    let kind: Kind
    let inputURL: URL
    /// Only populated for `.eval` — the expected N-Quads result file.
    let expectedURL: URL?
    let testIRI: String

    var description: String { name }
}

enum W3CTriGSuite {

    static let baseTestIRI = "http://www.w3.org/2013/TriGTests/"
    static let manifestIRI = baseTestIRI + "manifest.ttl"

    private static let rdfType =
        "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    private static let mfAction =
        "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action"
    private static let mfResult =
        "http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#result"
    private static let rdftEval =
        "http://www.w3.org/ns/rdftest#TestTrigEval"
    private static let rdftPositive =
        "http://www.w3.org/ns/rdftest#TestTrigPositiveSyntax"
    private static let rdftNegativeSyntax =
        "http://www.w3.org/ns/rdftest#TestTrigNegativeSyntax"
    private static let rdftNegativeEval =
        "http://www.w3.org/ns/rdftest#TestTrigNegativeEval"

    static let manifestURL: URL = {
        guard let url = Bundle.module.url(
            forResource: "manifest",
            withExtension: "ttl",
            subdirectory: "trig-tests"
        ) else {
            fatalError("W3C TriG manifest.ttl is not packaged as a test resource")
        }
        return url
    }()

    static let testsDirectory: URL = manifestURL.deletingLastPathComponent()

    static let allEntries: [W3CTriGTestEntry] = {
        do {
            return try loadEntries()
        } catch {
            fatalError("Failed to load W3C TriG manifest: \(error)")
        }
    }()

    static var evalEntries: [W3CTriGTestEntry] {
        allEntries.filter { $0.kind == .eval }
    }

    static var positiveSyntaxEntries: [W3CTriGTestEntry] {
        allEntries.filter { $0.kind == .positiveSyntax }
    }

    static var negativeSyntaxEntries: [W3CTriGTestEntry] {
        allEntries.filter { $0.kind == .negativeSyntax }
    }

    static var negativeEvalEntries: [W3CTriGTestEntry] {
        allEntries.filter { $0.kind == .negativeEval }
    }

    // MARK: - Loading

    /// The manifest itself is written in Turtle (not TriG), so we parse it
    /// with `TurtleParser`. This is the same bootstrap technique used by the
    /// Turtle suite — a regression in the manifest subset of the grammar
    /// surfaces here long before the individual TriG tests run.
    private static func loadEntries() throws -> [W3CTriGTestEntry] {
        let data = try Data(contentsOf: manifestURL)
        let text = String(decoding: data, as: UTF8.self)

        var context = ParsingContext(blankScopeID: "w3c-trig-manifest")
        context.setBaseIRI(IRI(manifestIRI))
        var parser = TurtleParser(context: context)
        let graph = try parser.parse(text)

        var bySubject: [String: [Edge]] = [:]
        for edge in graph.edges where edge.id.source.kind == .iri {
            bySubject[edge.id.source.key, default: []].append(edge)
        }

        var entries: [W3CTriGTestEntry] = []
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
            entries.append(W3CTriGTestEntry(
                name: name,
                kind: kind,
                inputURL: inputURL,
                expectedURL: expectedURL,
                testIRI: subjectIRI
            ))
        }
        return entries.sorted { $0.name < $1.name }
    }

    private static func classify(edges: [Edge]) -> W3CTriGTestEntry.Kind? {
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
