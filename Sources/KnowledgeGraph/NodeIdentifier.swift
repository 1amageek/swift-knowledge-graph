import Foundation

/// Stable, content-addressed identifier for a `Node`.
///
/// Identity is a pure function of `(kind, key)`. Two identifiers compare equal
/// if and only if both components compare equal — there is no UUID, no
/// timestamp, no insertion counter involved. This is required so that a
/// streaming parser can re-parse the same payload prefix and obtain identical
/// node identifiers, which a layout engine can then use to warm-restart from
/// the previous snapshot.
///
/// Construction helpers (`iri`, `blank`, `literal`) normalize the key for each
/// kind so callers do not have to repeat the encoding rules at every site.
public struct NodeIdentifier: Hashable, Sendable, Codable {
    public let kind: NodeKind
    public let key: String

    public init(kind: NodeKind, key: String) {
        self.kind = kind
        self.key = key
    }

    /// Identifier for a named resource. `iri` should be the absolute IRI; the
    /// builder is responsible for resolving any CURIE / relative form before
    /// the value reaches this constructor.
    public static func iri(_ iri: String) -> NodeIdentifier {
        NodeIdentifier(kind: .iri, key: iri)
    }

    /// Identifier for a blank node. `label` is the document-local label (the
    /// `_:b0` suffix in Turtle, or the `@id` of a `_:` JSON-LD node).
    public static func blank(_ label: String) -> NodeIdentifier {
        NodeIdentifier(kind: .blank, key: label)
    }

    /// Identifier for a literal value.
    ///
    /// The key encodes the lexical form together with whichever qualifier the
    /// literal carries:
    /// - `"value"@lang` when a language tag is present
    /// - `"value"^^datatype` when a datatype IRI is present
    /// - `"value"` when neither is present
    ///
    /// RDF 1.1 says a literal with a language tag always has datatype
    /// `rdf:langString` and a plain literal always has datatype `xsd:string`,
    /// so the encoding above is unambiguous: at most one qualifier is ever
    /// shown.
    public static func literal(
        value: String,
        datatype: String? = nil,
        language: String? = nil
    ) -> NodeIdentifier {
        NodeIdentifier(kind: .literal, key: Self.literalKey(
            value: value,
            datatype: datatype,
            language: language
        ))
    }

    /// Pure helper exposed for tests that need to assert the key shape.
    public static func literalKey(
        value: String,
        datatype: String?,
        language: String?
    ) -> String {
        if let language, !language.isEmpty {
            return "\"\(value)\"@\(language)"
        }
        if let datatype, !datatype.isEmpty {
            return "\"\(value)\"^^\(datatype)"
        }
        return "\"\(value)\""
    }
}
