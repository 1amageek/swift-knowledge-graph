import Foundation

/// Simplified XML event stream that the RDF/XML grammar layer consumes.
///
/// Foundation's `XMLParser` is class-based and uses an inherited delegate;
/// rather than thread RDF semantics directly through the delegate methods
/// (where errors are hard to propagate and the stripe state is hard to
/// reason about), the delegate flattens every callback into an
/// `RDFXMLEvent` and the grammar layer consumes that linear stream.
///
/// CDATA and character data are merged into adjacent `.text` events so the
/// grammar never has to combine them itself.
enum RDFXMLEvent {

    /// One XML attribute, with the resolved-to-absolute namespace URI and
    /// local name. The `qualified` field preserves the source spelling so
    /// the parseType=Literal serializer can reconstruct the original XML
    /// when emitting the literal value.
    struct Attribute: Equatable {
        let namespaceURI: String
        let localName: String
        let qualifiedName: String
        let value: String

        /// Absolute IRI for this attribute (`namespaceURI + localName`).
        /// This is what the RDF/XML grammar tests against the
        /// `coreSyntaxTerms` / `oldTerms` / etc. partitions.
        var absoluteIRI: String { namespaceURI + localName }
    }

    case startElement(
        namespaceURI: String,
        localName: String,
        qualifiedName: String,
        attributes: [Attribute]
    )
    case endElement(
        namespaceURI: String,
        localName: String,
        qualifiedName: String
    )
    case text(String)
}
