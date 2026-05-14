import Foundation

/// Serialises the body of a `parseType="Literal"` property element back into
/// XML text.
///
/// RDF/XML 1.1 §3.4 says the lexical form of an `rdf:XMLLiteral` literal is
/// the exclusive XML canonicalisation (xml-exc-c14n) of the property's
/// content. Full xml-exc-c14n is out of scope here — the W3C RDF/XML test
/// suite gates equality through *graph isomorphism* over N-Triples, which
/// in turn quotes the literal value verbatim. So we reconstruct a
/// best-effort XML serialisation of the content that round-trips the
/// shapes the tests exercise: nested elements, attributes, character data,
/// and entity-escaped reserved characters.
enum RDFXMLLiteralSerializer {

    /// Walk `events` starting at `start` until the matching end element of
    /// the wrapping property is reached. Return both the serialised body
    /// and the index of that end element (which the caller must consume).
    static func serialize(
        events: [RDFXMLEvent],
        start: Int
    ) throws -> (literal: String, endIndex: Int) {
        var output = ""
        var depth = 0
        var index = start
        while index < events.count {
            let event = events[index]
            switch event {
            case .startElement(_, _, let qName, let attributes):
                output.append("<")
                output.append(qName)
                // Stable attribute ordering — sort by qualified name so that
                // two runs of the same input produce the same serialisation.
                let sorted = attributes.sorted { $0.qualifiedName < $1.qualifiedName }
                for attr in sorted {
                    output.append(" ")
                    output.append(attr.qualifiedName)
                    output.append("=\"")
                    output.append(escapeAttributeValue(attr.value))
                    output.append("\"")
                }
                output.append(">")
                depth += 1
                index += 1
            case .endElement(_, _, let qName):
                if depth == 0 {
                    return (output, index)
                }
                output.append("</")
                output.append(qName)
                output.append(">")
                depth -= 1
                index += 1
            case .text(let text):
                output.append(escapeText(text))
                index += 1
            }
        }
        throw ParserError.xmlSyntax(
            detail: "unterminated parseType=\"Literal\" content",
            at: .start
        )
    }

    private static func escapeText(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for char in text {
            switch char {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case ">": result.append("&gt;")
            default: result.append(char)
            }
        }
        return result
    }

    private static func escapeAttributeValue(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for char in value {
            switch char {
            case "&": result.append("&amp;")
            case "<": result.append("&lt;")
            case "\"": result.append("&quot;")
            default: result.append(char)
            }
        }
        return result
    }
}
