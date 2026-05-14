import Foundation

/// Constants for the RDF/XML 1.1 grammar.
///
/// RDF/XML reserves a small vocabulary inside the
/// `http://www.w3.org/1999/02/22-rdf-syntax-ns#` namespace as
/// *syntactic* — these names cannot be used as user property /
/// resource names because the grammar gives them special meaning
/// (W3C RDF/XML 1.1 §6.1.2).
///
/// Centralising the partition here lets the parser test membership
/// with a single set lookup instead of reproducing the predicate
/// at every callsite.
enum RDFXMLConstants {

    /// The RDF namespace URI prefix.
    static let rdfNS = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    // Core syntax terms — never allowed as a node element URI, property
    // element URI, or property attribute URI.
    static let rdfRDF = rdfNS + "RDF"
    static let rdfID = rdfNS + "ID"
    static let rdfAbout = rdfNS + "about"
    static let rdfParseType = rdfNS + "parseType"
    static let rdfResource = rdfNS + "resource"
    static let rdfNodeID = rdfNS + "nodeID"
    static let rdfDatatype = rdfNS + "datatype"

    // Other RDF syntax terms with special treatment.
    static let rdfDescription = rdfNS + "Description"
    static let rdfLi = rdfNS + "li"
    static let rdfType = rdfNS + "type"

    // RDF Collection / List vocabulary.
    static let rdfFirst = rdfNS + "first"
    static let rdfRest = rdfNS + "rest"
    static let rdfNil = rdfNS + "nil"

    // Reification vocabulary.
    static let rdfStatement = rdfNS + "Statement"
    static let rdfSubject = rdfNS + "subject"
    static let rdfPredicate = rdfNS + "predicate"
    static let rdfObject = rdfNS + "object"

    // XML Literal datatype (W3C RDF 1.1 §3.4).
    static let rdfXMLLiteral = rdfNS + "XMLLiteral"

    // Old / deprecated RDF/XML terms — recognised only to raise an error
    // (the W3C tests assert that these names trigger a syntax error).
    static let rdfAboutEach = rdfNS + "aboutEach"
    static let rdfAboutEachPrefix = rdfNS + "aboutEachPrefix"
    static let rdfBagID = rdfNS + "bagID"

    /// True for `coreSyntaxTerms`: names that have grammar meaning and may
    /// not appear as node element / property element / property attribute
    /// names.
    static func isCoreSyntaxTerm(_ iri: String) -> Bool {
        switch iri {
        case rdfRDF, rdfID, rdfAbout, rdfParseType, rdfResource, rdfNodeID, rdfDatatype:
            return true
        default:
            return false
        }
    }

    /// True for `oldTerms`: deprecated names that must trigger a syntax
    /// error wherever they appear.
    static func isOldTerm(_ iri: String) -> Bool {
        switch iri {
        case rdfAboutEach, rdfAboutEachPrefix, rdfBagID:
            return true
        default:
            return false
        }
    }

    /// True for a valid `nodeElementURI`. Excludes the core syntax terms,
    /// `rdf:li`, and the deprecated `oldTerms`.
    static func isValidNodeElement(_ iri: String) -> Bool {
        if isCoreSyntaxTerm(iri) { return false }
        if iri == rdfLi { return false }
        if isOldTerm(iri) { return false }
        return true
    }

    /// True for a valid `propertyElementURI`. Excludes the core syntax
    /// terms, `rdf:Description`, and the deprecated `oldTerms`. `rdf:li`
    /// *is* allowed and is rewritten by the parser into `rdf:_N`.
    static func isValidPropertyElement(_ iri: String) -> Bool {
        if isCoreSyntaxTerm(iri) { return false }
        if iri == rdfDescription { return false }
        if isOldTerm(iri) { return false }
        return true
    }

    /// True for a valid `propertyAttributeURI`. Same as the property
    /// element rules plus `rdf:li` is also forbidden (per the grammar).
    static func isValidPropertyAttribute(_ iri: String) -> Bool {
        if isCoreSyntaxTerm(iri) { return false }
        if iri == rdfDescription { return false }
        if iri == rdfLi { return false }
        if isOldTerm(iri) { return false }
        return true
    }

    /// XML namespace URIs that get rejected if used as RDF names.
    static let xmlNS = "http://www.w3.org/XML/1998/namespace"
    static let xmlnsNS = "http://www.w3.org/2000/xmlns/"
}
