import Foundation
import KnowledgeGraph

/// Mutable per-parse state shared by every concrete parser.
///
/// `ParsingContext` collects everything that is *about* the parse but is not
/// the input itself: the base IRI, the prefix map, the blank-node scope,
/// and the current source position. Concrete parsers thread one of these
/// through every grammar rule, mutating it as `@prefix` / `@base` /
/// `<rdf:RDF xml:base=...>` / `@context` declarations come in.
///
/// Blank nodes are scoped by `blankScopeID`. Two parses that use different
/// scope ids will never produce colliding `NodeIdentifier` values for blank
/// labels — even if both documents call them `_:b0`. The default scope id
/// is a UUID so distinct parses are isolated by default; callers that need
/// warm-restart (re-parse a payload and obtain the same blank ids as before)
/// pass an explicit, stable scope id.
public struct ParsingContext: Sendable {

    public var baseIRI: IRI?
    public var prefixes: [String: IRI]
    public let blankScopeID: String
    public var position: SourcePosition

    private var blankCounter: Int
    private var blankLabelMap: [String: NodeIdentifier]

    public init(
        baseIRI: IRI? = nil,
        blankScopeID: String = UUID().uuidString
    ) {
        self.baseIRI = baseIRI
        self.prefixes = [:]
        self.blankScopeID = blankScopeID
        self.position = .start
        self.blankCounter = 0
        self.blankLabelMap = [:]
    }

    // MARK: - Prefix / base declarations

    public mutating func declarePrefix(_ prefix: String, iri: IRI) {
        prefixes[prefix] = iri
    }

    public mutating func setBaseIRI(_ iri: IRI) {
        baseIRI = iri
    }

    // MARK: - IRI resolution

    /// Resolve a reference (absolute or relative) into a full IRI.
    ///
    /// Absolute references are normalised through the resolver's
    /// `removeDotSegments` step and returned. Relative references require a
    /// base IRI to be in scope — if none has been declared, this throws
    /// `ParserError.noBaseIRI`.
    public func resolveIRIReference(
        _ reference: String,
        at position: SourcePosition
    ) throws -> IRI {
        let components = IRIComponents.parse(reference)
        if components.scheme != nil {
            return IRI(IRIResolver.resolve(reference: reference, against: ""))
        }
        guard let baseIRI else {
            throw ParserError.noBaseIRI(at: position)
        }
        return IRI(IRIResolver.resolve(reference: reference, against: baseIRI.value))
    }

    /// Resolve a CURIE (`prefix:suffix`) into a full IRI by concatenating
    /// the registered namespace IRI with the suffix.
    ///
    /// Note: this implementation matches the Turtle / TriG / SPARQL rule
    /// that the namespace IRI is treated as a *literal prefix* rather than
    /// being merged through RFC 3986 reference resolution. RDF/XML and
    /// JSON-LD use the same rule.
    public func resolveCURIE(
        prefix: String,
        suffix: String,
        at position: SourcePosition
    ) throws -> IRI {
        guard let namespace = prefixes[prefix] else {
            throw ParserError.undefinedPrefix(prefix: prefix, at: position)
        }
        return IRI(namespace.value + suffix)
    }

    // MARK: - Blank nodes

    /// Map a Turtle / TriG-style blank label (`b0`, without the `_:`
    /// prefix) to a `NodeIdentifier`. Repeated lookups of the same label
    /// in the same context return the same identifier — that is the
    /// document-local semantics of blank nodes per RDF 1.1 §3.4.
    public mutating func blankNode(forLabel label: String) -> NodeIdentifier {
        if let existing = blankLabelMap[label] {
            return existing
        }
        let scopedLabel = scopedBlankLabel(label)
        let identifier = NodeIdentifier.blank(scopedLabel)
        blankLabelMap[label] = identifier
        return identifier
    }

    /// Generate a fresh anonymous blank node. RDF/XML, JSON-LD, and the
    /// Turtle `[ ... ]` form all need one of these whenever the input does
    /// not name a blank label explicitly.
    public mutating func freshBlankNode() -> NodeIdentifier {
        blankCounter += 1
        let label = "_anon\(blankCounter)"
        return NodeIdentifier.blank(scopedBlankLabel(label))
    }

    private func scopedBlankLabel(_ label: String) -> String {
        "\(blankScopeID)/\(label)"
    }
}
