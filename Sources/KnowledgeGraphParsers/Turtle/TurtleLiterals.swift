import Foundation
import KnowledgeGraph

/// Datatype IRI constants and `Token` → `NodeIdentifier.literal` mapping
/// for the Turtle / TriG literal lexical forms.
///
/// Centralising this conversion keeps the grammar layer focused on
/// structure: when it sees `integer("42")` it asks `TurtleLiterals` for
/// the corresponding RDF term, and the answer is always shaped according
/// to RDF 1.1 §4.4 ("Native Lexical Forms").
enum TurtleLiterals {

    /// `xsd:integer` — RDF 1.1 §6.2.2 native datatype for `INTEGER`.
    static let xsdInteger = "http://www.w3.org/2001/XMLSchema#integer"

    /// `xsd:decimal` — for `DECIMAL`.
    static let xsdDecimal = "http://www.w3.org/2001/XMLSchema#decimal"

    /// `xsd:double` — for `DOUBLE`.
    static let xsdDouble = "http://www.w3.org/2001/XMLSchema#double"

    /// `xsd:boolean` — for `'true' | 'false'`.
    static let xsdBoolean = "http://www.w3.org/2001/XMLSchema#boolean"

    /// `xsd:string` — the implicit datatype of any plain string literal in
    /// RDF 1.1 (§3.3). A literal with a language tag still has datatype
    /// `rdf:langString`, but `NodeIdentifier.literal` encodes the language
    /// tag inline and does not store the datatype IRI in that case.
    static let xsdString = "http://www.w3.org/2001/XMLSchema#string"

    /// `rdf:langString` — the datatype assigned to language-tagged plain
    /// strings. Provided here for documentation; the encoding rule in
    /// `NodeIdentifier.literalKey` already implies it.
    static let rdfLangString = "http://www.w3.org/1999/02/22-rdf-syntax-ns#langString"

    /// Build a literal node identifier for an `integer` token.
    static func integer(_ lexeme: String) -> NodeIdentifier {
        NodeIdentifier.literal(value: lexeme, datatype: xsdInteger)
    }

    /// Build a literal node identifier for a `decimal` token.
    static func decimal(_ lexeme: String) -> NodeIdentifier {
        NodeIdentifier.literal(value: lexeme, datatype: xsdDecimal)
    }

    /// Build a literal node identifier for a `double` token.
    static func double(_ lexeme: String) -> NodeIdentifier {
        NodeIdentifier.literal(value: lexeme, datatype: xsdDouble)
    }

    /// Build a literal node identifier for a boolean token.
    static func boolean(_ value: Bool) -> NodeIdentifier {
        NodeIdentifier.literal(value: value ? "true" : "false", datatype: xsdBoolean)
    }

    /// Build a literal node identifier for a plain string. RDF 1.1 §3.3
    /// makes `xsd:string` the implicit datatype — but to keep the same
    /// `key` regardless of how the same literal was written in different
    /// source forms (a literal without a datatype IRI and a literal
    /// explicitly typed `^^xsd:string` round-trip to the same node), we
    /// always store plain strings *without* an explicit datatype.
    static func plainString(_ value: String) -> NodeIdentifier {
        NodeIdentifier.literal(value: value)
    }

    /// Build a literal node identifier for a language-tagged string.
    static func langTagged(_ value: String, language: String) -> NodeIdentifier {
        NodeIdentifier.literal(value: value, language: language)
    }

    /// Build a literal node identifier for an explicitly typed string.
    /// Pass `xsd:string` exactly here when the source wrote the type
    /// explicitly and you want the typed form preserved — the grammar
    /// layer chooses which entry point to call.
    static func typed(_ value: String, datatype: String) -> NodeIdentifier {
        if datatype == xsdString {
            // Canonicalise — see `plainString(_:)`.
            return plainString(value)
        }
        return NodeIdentifier.literal(value: value, datatype: datatype)
    }
}
