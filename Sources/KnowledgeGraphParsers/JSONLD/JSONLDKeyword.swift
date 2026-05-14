import Foundation

/// JSON-LD 1.1 syntax tokens.
///
/// Keywords are the strings beginning with `@` that have special meaning in
/// JSON-LD. Centralising them as constants prevents typos and gives the rest
/// of the parser a single point of truth for the list defined in §1.7.
enum JSONLDKeyword {
    static let id        = "@id"
    static let type      = "@type"
    static let value     = "@value"
    static let language  = "@language"
    static let direction = "@direction"
    static let list      = "@list"
    static let set       = "@set"
    static let reverse   = "@reverse"
    static let index     = "@index"
    static let container = "@container"
    static let context   = "@context"
    static let base      = "@base"
    static let vocab     = "@vocab"
    static let graph     = "@graph"
    static let nest      = "@nest"
    static let propagate = "@propagate"
    static let protected = "@protected"
    static let version   = "@version"
    static let `import`  = "@import"
    static let included  = "@included"
    static let json      = "@json"
    static let none      = "@none"
    static let prefix    = "@prefix"
    static let any       = "@any"
    static let first     = "@first"

    /// `true` if `name` starts with `@` and matches a known keyword.
    static func isKnown(_ name: String) -> Bool {
        Self.known.contains(name)
    }

    /// `true` if `name` looks like a keyword (starts with `@` followed by at
    /// least one letter). Used by §4.3 IRI expansion to reject unknown
    /// keyword-shaped terms.
    static func looksLikeKeyword(_ name: String) -> Bool {
        guard name.hasPrefix("@") else { return false }
        let suffix = name.dropFirst()
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { $0.isLetter }
    }

    private static let known: Set<String> = [
        id, type, value, language, direction, list, set, reverse, index,
        container, context, base, vocab, graph, nest, propagate, protected,
        version, `import`, included, json, none, prefix, any, first
    ]
}
