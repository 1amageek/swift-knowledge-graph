import Foundation

/// The five-tuple decomposition of an IRI per RFC 3986 §3.
///
/// `path` is always present (possibly empty); the other four components are
/// optional, matching the RFC's distinction between "absent" and "empty".
/// That distinction matters during reference resolution: `<scheme://h?>`
/// (empty query) and `<scheme://h>` (no query) recompose differently.
struct IRIComponents: Hashable {
    var scheme: String?
    var authority: String?
    var path: String
    var query: String?
    var fragment: String?

    /// Parse an IRI into its components. This implementation follows the
    /// regular expression in RFC 3986 §B but is written as an explicit
    /// scanner so that we never pull in `NSRegularExpression` and so that
    /// every step is auditable for spec conformance.
    static func parse(_ iri: String) -> IRIComponents {
        var components = IRIComponents(scheme: nil, authority: nil, path: "", query: nil, fragment: nil)
        var remainder = Substring(iri)

        // Fragment is removed first so that '#' inside the fragment cannot
        // be confused with the fragment separator.
        if let hashRange = remainder.range(of: "#") {
            components.fragment = String(remainder[hashRange.upperBound...])
            remainder = remainder[..<hashRange.lowerBound]
        }

        // Then query.
        if let questionRange = remainder.range(of: "?") {
            components.query = String(remainder[questionRange.upperBound...])
            remainder = remainder[..<questionRange.lowerBound]
        }

        // Then scheme. Scheme grammar: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
        // followed by ":". A colon found inside the path (e.g. "g:h" used as
        // a relative reference would have its colon consumed only if the
        // characters before it form a valid scheme).
        if let colonIndex = remainder.firstIndex(of: ":") {
            let candidate = remainder[..<colonIndex]
            if Self.isValidScheme(candidate) {
                components.scheme = String(candidate)
                remainder = remainder[remainder.index(after: colonIndex)...]
            }
        }

        // Then authority. Marked by leading "//".
        if remainder.hasPrefix("//") {
            let afterSlashes = remainder.index(remainder.startIndex, offsetBy: 2)
            // Authority ends at the next "/", "?", or "#" — but we already
            // stripped query and fragment, so only "/" matters here.
            let authorityEnd = remainder[afterSlashes...].firstIndex(of: "/") ?? remainder.endIndex
            components.authority = String(remainder[afterSlashes..<authorityEnd])
            remainder = remainder[authorityEnd...]
        }

        // Everything left is the path. (May be empty.)
        components.path = String(remainder)

        return components
    }

    private static func isValidScheme(_ candidate: Substring) -> Bool {
        guard let first = candidate.first, first.isASCIILetter else { return false }
        for character in candidate.dropFirst() where !character.isSchemeContinuation {
            return false
        }
        return true
    }

    /// Recompose the components back into an IRI string per RFC 3986 §5.3.
    func recomposed() -> String {
        var result = ""
        if let scheme = scheme {
            result.append(scheme)
            result.append(":")
        }
        if let authority = authority {
            result.append("//")
            result.append(authority)
        }
        result.append(path)
        if let query = query {
            result.append("?")
            result.append(query)
        }
        if let fragment = fragment {
            result.append("#")
            result.append(fragment)
        }
        return result
    }
}

extension Character {
    fileprivate var isASCIILetter: Bool {
        guard let ascii = asciiValue else { return false }
        return (0x41...0x5A).contains(ascii) || (0x61...0x7A).contains(ascii)
    }

    fileprivate var isSchemeContinuation: Bool {
        if isASCIILetter { return true }
        guard let ascii = asciiValue else { return false }
        if (0x30...0x39).contains(ascii) { return true } // digit
        return self == "+" || self == "-" || self == "."
    }
}
