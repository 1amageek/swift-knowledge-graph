import Foundation

/// A prefix-to-IRI mapping, e.g. `("foaf", "http://xmlns.com/foaf/0.1/")`.
///
/// Namespaces are not part of the RDF abstract syntax — they exist to make
/// IRIs compact in serializations like Turtle and JSON-LD. The IR keeps them
/// alongside the graph so a renderer can shorten labels (`foaf:name` instead
/// of the full IRI) without re-running the parser.
public struct Namespace: Hashable, Sendable, Codable {
    public let prefix: String
    public let uri: String

    public init(prefix: String, uri: String) {
        self.prefix = prefix
        self.uri = uri
    }
}
