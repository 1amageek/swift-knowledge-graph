import Foundation

/// Errors thrown by `KnowledgeGraphBuilder` when an invariant would be
/// violated.
///
/// Every error carries enough context for the caller to surface a precise
/// message without resorting to string parsing. Silent fallback is explicitly
/// not an option: a builder that cannot honour a request must throw.
public enum KnowledgeGraphError: Error, Hashable, Sendable {
    /// An IRI-kinded node was inserted with an empty key.
    case emptyIRI
    /// A blank node was inserted with an empty label.
    case emptyBlankLabel
    /// An edge was inserted with an empty predicate IRI.
    case emptyPredicate
    /// A namespace was inserted with an empty prefix.
    case emptyNamespacePrefix
    /// A namespace was inserted with an empty URI.
    case emptyNamespaceURI
    /// A namespace with the same prefix already exists, but its URI differs.
    /// Re-inserting the identical pair is allowed (idempotent); only conflicts
    /// raise.
    case namespacePrefixConflict(prefix: String, existing: String, attempted: String)
    /// A named graph was inserted with an empty IRI.
    case emptyNamedGraphID
    /// A named graph with the same id already exists, but its label differs.
    case namedGraphLabelConflict(id: String, existing: String, attempted: String)
}
