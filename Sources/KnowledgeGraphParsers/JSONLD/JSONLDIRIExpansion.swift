import Foundation

/// JSON-LD 1.1 IRI Expansion algorithm (§4.3).
///
/// Takes a source string + active context and decides whether the string
/// names a keyword, a defined term, a compact IRI, an absolute IRI, or a
/// relative IRI against `@base`.
///
/// The two booleans `documentRelative` and `vocab` follow the spec's
/// parameter names — they tune the algorithm based on whether we are in a
/// vocab position (`@type`, a predicate) or a document-relative position
/// (`@id`).
enum JSONLDIRIExpansion {

    static func expand(
        _ value: String,
        context: JSONLDContext,
        documentRelative: Bool,
        vocab: Bool
    ) -> String? {
        if JSONLDKeyword.isKnown(value) {
            return value
        }
        if JSONLDKeyword.looksLikeKeyword(value) {
            return nil
        }
        if vocab, let term = context.terms[value], let iri = term.iri {
            return iri
        }
        if let colonIndex = value.firstIndex(of: ":") {
            let prefix = String(value[..<colonIndex])
            let suffix = String(value[value.index(after: colonIndex)...])
            if prefix == "_" {
                return value
            }
            if suffix.hasPrefix("//") {
                return value
            }
            if let term = context.terms[prefix], term.prefix, let iri = term.iri {
                return iri + suffix
            }
            if isAbsoluteIRI(value) {
                return value
            }
        }
        if vocab, let vocabIRI = context.vocab {
            return vocabIRI + value
        }
        if documentRelative, let base = context.baseIRI {
            return IRIResolver.resolve(reference: value, against: base)
        }
        // Per §4.3: a term that resolves to neither a keyword, defined term,
        // compact IRI, absolute IRI, vocab-relative IRI, nor base-relative
        // IRI is not expandable. Returning the raw value here was a silent
        // fallback that let bare strings flow through @id/@type/predicate
        // positions and produce malformed triples downstream. Returning nil
        // lets each caller decide: most drop silently (the spec behaviour),
        // a few throw an explicit error (`@id` must always resolve).
        return nil
    }

    private static func isAbsoluteIRI(_ value: String) -> Bool {
        guard let colon = value.firstIndex(of: ":") else { return false }
        let scheme = value[..<colon]
        guard let first = scheme.first, first.isLetter else { return false }
        for c in scheme.dropFirst() {
            if c.isLetter || c.isNumber || c == "+" || c == "-" || c == "." { continue }
            return false
        }
        return true
    }
}
