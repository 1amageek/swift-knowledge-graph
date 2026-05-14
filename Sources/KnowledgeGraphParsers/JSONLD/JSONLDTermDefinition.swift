import Foundation

/// A single entry in a `JSONLDContext`'s term map.
///
/// JSON-LD §3.1 calls these "term definitions". Each tells the expansion
/// algorithm how to turn the source key into an absolute IRI and how to
/// shape value-objects derived from values associated with that term.
struct JSONLDTermDefinition: Sendable, Hashable {
    /// The IRI this term expands to. `nil` indicates a `@type: @none`-style
    /// term that maps nowhere — JSON-LD expansion drops values for it.
    var iri: String?

    /// The `@type` mapping (`@id`, `@vocab`, `@json`, `@none`, or an IRI).
    var typeMapping: String?

    /// The `@language` mapping. `""` means "explicit no-language", `nil`
    /// means "inherit default".
    var languageMapping: String?

    /// The `@direction` mapping.
    var directionMapping: String?

    /// Set of `@container` values. `[]` means the value is a plain
    /// (non-container) term.
    var container: Set<String>

    /// `@nest` mapping.
    var nestValue: String?

    /// `@prefix` flag — controls whether the term may participate in
    /// compact-IRI expansion (term:suffix).
    var prefix: Bool

    /// Term is defined inside an `@reverse` block.
    var reverse: Bool

    /// `@protected` flag.
    var protected: Bool

    /// `@index` mapping.
    var indexMapping: String?

    /// Local `@context` for this term, evaluated when the term is used.
    var localContext: JSONValue?

    init(
        iri: String? = nil,
        typeMapping: String? = nil,
        languageMapping: String? = nil,
        directionMapping: String? = nil,
        container: Set<String> = [],
        nestValue: String? = nil,
        prefix: Bool = false,
        reverse: Bool = false,
        protected: Bool = false,
        indexMapping: String? = nil,
        localContext: JSONValue? = nil
    ) {
        self.iri = iri
        self.typeMapping = typeMapping
        self.languageMapping = languageMapping
        self.directionMapping = directionMapping
        self.container = container
        self.nestValue = nestValue
        self.prefix = prefix
        self.reverse = reverse
        self.protected = protected
        self.indexMapping = indexMapping
        self.localContext = localContext
    }
}
