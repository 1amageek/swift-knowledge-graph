import Foundation

/// An IRI as it appears in an RDF document.
///
/// The IR keeps the raw string verbatim because RDF identity is defined on
/// the IRI's exact character sequence — two IRIs that normalise to the same
/// value but differ in case or percent-encoding are *not* the same RDF
/// resource. Callers that want a canonical form must run normalisation
/// themselves and treat the result as a separate IRI value.
public struct IRI: Hashable, Sendable, Codable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }

    /// `true` when the IRI begins with an unreserved scheme prefix
    /// (RFC 3986 §3.1). Used by the resolver to decide whether the
    /// reference is absolute.
    public var isAbsolute: Bool {
        IRIComponents.parse(value).scheme != nil
    }
}
