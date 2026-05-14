import Foundation

/// Discriminator for the three RDF node categories.
///
/// - `iri`: a globally identified resource (e.g. `<http://example.org/Alice>`).
/// - `blank`: a locally scoped resource with no global identity, only a label
///   that is meaningful inside a single document.
/// - `literal`: a data value carrying a lexical form, an optional datatype IRI,
///   and an optional language tag.
public enum NodeKind: String, Hashable, Sendable, CaseIterable, Codable {
    case iri
    case blank
    case literal
}
