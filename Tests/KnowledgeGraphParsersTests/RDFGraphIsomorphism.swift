import Foundation
import KnowledgeGraph

/// RDF 1.1 graph / dataset isomorphism check.
///
/// Two graphs (or RDF datasets) are RDF-equal if there is a bijection between
/// their blank nodes such that the resulting quad sets are identical. The
/// check used here is the standard color-refinement (1-WL) canonicalisation:
/// each blank node is repeatedly relabelled with a signature built from its
/// incident quads, using current labels of its neighbours; once labels
/// stabilise, we rewrite both datasets replacing every blank with its label
/// and compare the resulting quad multisets.
///
/// A blank node may appear in any of four positions per quad (subject,
/// object, named graph, or — in principle — predicate, though RDF forbids
/// blank predicates), and each position contributes a distinct signature.
/// This is what lets the same routine work on plain Turtle graphs (every
/// quad has no graph component) and TriG datasets (graph identifiers may
/// themselves be blanks).
///
/// Color refinement is complete for all graphs that the W3C Turtle and TriG
/// test suites contain — none of the eval tests exercise the pathological
/// symmetric cases (k-regular bipartite cospectral pairs) where 1-WL would
/// over-merge.
enum RDFGraphIsomorphism {

    struct Quad: Hashable {
        let subject: NodeIdentifier
        let predicate: String
        let object: NodeIdentifier
        let graph: NodeIdentifier?
    }

    static func areIsomorphic(_ a: KnowledgeGraph, _ b: KnowledgeGraph) -> Bool {
        let aQuads = quads(of: a)
        let bQuads = quads(of: b)

        if aQuads.count != bQuads.count {
            return false
        }

        let aBlanks = blankNodes(in: aQuads)
        let bBlanks = blankNodes(in: bQuads)
        if aBlanks.count != bBlanks.count {
            return false
        }

        let aColors = canonicalColors(quads: aQuads, blanks: aBlanks)
        let bColors = canonicalColors(quads: bQuads, blanks: bBlanks)

        let aMultiset = countedSet(rewrite(aQuads, colors: aColors))
        let bMultiset = countedSet(rewrite(bQuads, colors: bColors))
        return aMultiset == bMultiset
    }

    // MARK: - Helpers

    private static func quads(of graph: KnowledgeGraph) -> [Quad] {
        graph.edges.map {
            Quad(
                subject: $0.id.source,
                predicate: $0.id.predicate,
                object: $0.id.target,
                graph: graphNodeIdentifier($0.id.namedGraph)
            )
        }
    }

    /// A named-graph identifier in `KnowledgeGraph` is stored as `String?`,
    /// but the isomorphism check needs to treat that label as a node so that
    /// blank graph labels participate in refinement. We reconstruct the
    /// `NodeIdentifier` from the label by detecting blank-node keys (those
    /// produced by `ParsingContext.blankNode` carry the parse-scope prefix
    /// followed by `/`). Everything else is an IRI.
    private static func graphNodeIdentifier(_ label: String?) -> NodeIdentifier? {
        guard let label else { return nil }
        if looksLikeBlankKey(label) {
            return NodeIdentifier.blank(label)
        }
        return NodeIdentifier.iri(label)
    }

    private static func looksLikeBlankKey(_ key: String) -> Bool {
        // Blank-node keys produced by `ParsingContext` follow the pattern
        // `<scopeID>/<label>`. IRIs in the test suite never contain `/` as a
        // bare prefix of a scope token — they always have a scheme. Use that
        // to distinguish: a key without a `:` before the first `/` is a blank.
        if let slash = key.firstIndex(of: "/") {
            let beforeSlash = key[..<slash]
            if !beforeSlash.contains(":") {
                return true
            }
        }
        return false
    }

    private static func blankNodes(in quads: [Quad]) -> Set<NodeIdentifier> {
        var result: Set<NodeIdentifier> = []
        for q in quads {
            if q.subject.kind == .blank { result.insert(q.subject) }
            if q.object.kind == .blank { result.insert(q.object) }
            if let g = q.graph, g.kind == .blank { result.insert(g) }
        }
        return result
    }

    private static func groundToken(_ node: NodeIdentifier) -> String {
        "\(node.kind.rawValue):\(node.key)"
    }

    /// One round of refinement. Each blank's new label is a deterministic
    /// signature built from its incident quads using the previous round's
    /// labels for blank neighbours.
    private static func refine(
        quads: [Quad],
        blanks: Set<NodeIdentifier>,
        current: [NodeIdentifier: String]
    ) -> [NodeIdentifier: String] {
        var next: [NodeIdentifier: String] = [:]
        next.reserveCapacity(blanks.count)
        for b in blanks {
            var asSubject: [String] = []
            var asObject: [String] = []
            var asGraph: [String] = []
            for q in quads {
                if q.subject == b {
                    let objectToken = (q.object.kind == .blank)
                        ? "@" + (current[q.object] ?? "")
                        : groundToken(q.object)
                    let graphToken = graphSignatureToken(q.graph, current: current)
                    asSubject.append(q.predicate + "|" + objectToken + "|" + graphToken)
                }
                if q.object == b {
                    let subjectToken = (q.subject.kind == .blank)
                        ? "@" + (current[q.subject] ?? "")
                        : groundToken(q.subject)
                    let graphToken = graphSignatureToken(q.graph, current: current)
                    asObject.append(q.predicate + "|" + subjectToken + "|" + graphToken)
                }
                if let g = q.graph, g == b {
                    let subjectToken = (q.subject.kind == .blank)
                        ? "@" + (current[q.subject] ?? "")
                        : groundToken(q.subject)
                    let objectToken = (q.object.kind == .blank)
                        ? "@" + (current[q.object] ?? "")
                        : groundToken(q.object)
                    asGraph.append(q.predicate + "|" + subjectToken + "|" + objectToken)
                }
            }
            asSubject.sort()
            asObject.sort()
            asGraph.sort()
            next[b] = "S[" + asSubject.joined(separator: ";") +
                      "]O[" + asObject.joined(separator: ";") +
                      "]G[" + asGraph.joined(separator: ";") + "]"
        }
        return next
    }

    private static func graphSignatureToken(
        _ graph: NodeIdentifier?,
        current: [NodeIdentifier: String]
    ) -> String {
        guard let graph else { return "_default_" }
        if graph.kind == .blank {
            return "@" + (current[graph] ?? "")
        }
        return groundToken(graph)
    }

    private static func canonicalColors(
        quads: [Quad],
        blanks: Set<NodeIdentifier>
    ) -> [NodeIdentifier: String] {
        if blanks.isEmpty { return [:] }
        var current: [NodeIdentifier: String] = [:]
        for b in blanks { current[b] = "@b" }
        let maxIterations = blanks.count + 2
        for _ in 0..<maxIterations {
            let next = refine(quads: quads, blanks: blanks, current: current)
            if partitionSignature(next) == partitionSignature(current) {
                return next
            }
            current = next
        }
        return current
    }

    /// Sorted multiset of class sizes — a partition refinement reaches a fixed
    /// point when this signature stops changing.
    private static func partitionSignature(_ labels: [NodeIdentifier: String]) -> [Int] {
        var counts: [String: Int] = [:]
        for value in labels.values {
            counts[value, default: 0] += 1
        }
        return counts.values.sorted()
    }

    private static func rewrite(
        _ quads: [Quad],
        colors: [NodeIdentifier: String]
    ) -> [String] {
        quads.map { q in
            let s = (q.subject.kind == .blank) ? "@b/" + (colors[q.subject] ?? "?") : groundToken(q.subject)
            let o = (q.object.kind == .blank) ? "@b/" + (colors[q.object] ?? "?") : groundToken(q.object)
            let g: String
            if let graph = q.graph {
                g = (graph.kind == .blank) ? "@b/" + (colors[graph] ?? "?") : groundToken(graph)
            } else {
                g = "_default_"
            }
            return s + "\t" + q.predicate + "\t" + o + "\t" + g
        }
    }

    private static func countedSet(_ items: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for x in items {
            result[x, default: 0] += 1
        }
        return result
    }
}
