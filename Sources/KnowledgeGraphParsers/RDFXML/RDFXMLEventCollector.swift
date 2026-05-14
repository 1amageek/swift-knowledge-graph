import Foundation

/// `XMLParserDelegate` adapter that flattens Foundation's callback stream
/// into an array of `RDFXMLEvent` values.
///
/// The grammar layer wants a linear event sequence, not the spread of
/// `parser(_:didStartElement:...)` / `parser(_:foundCharacters:)` /
/// `parser(_:foundCDATA:)` callbacks Foundation emits. This collector
/// performs three jobs:
///
/// 1. Maps each delegate callback to one `RDFXMLEvent`.
/// 2. Merges runs of `.text` (character data + CDATA) into one event so
///    that `parseType="Literal"` sees a single content stream.
/// 3. Records the first XML parse error so the driving struct can rethrow
///    it as a typed `ParserError` rather than swallowing it.
///
/// The class itself is intentionally `final` and used only on the calling
/// thread during a single `parse()` call.
final class RDFXMLEventCollector: NSObject, XMLParserDelegate {

    private(set) var events: [RDFXMLEvent] = []
    private(set) var parseError: Error?
    private var pendingText: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        flushPendingText()
        pushNamespaceFrame()
        let attributes = collectAttributes(
            qName: qName ?? elementName,
            attributes: attributeDict
        )
        let ns: String
        if let namespaceURI { ns = namespaceURI } else { ns = "" }
        events.append(.startElement(
            namespaceURI: ns,
            localName: elementName,
            qualifiedName: qName ?? elementName,
            attributes: attributes
        ))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        flushPendingText()
        let ns: String
        if let namespaceURI { ns = namespaceURI } else { ns = "" }
        events.append(.endElement(
            namespaceURI: ns,
            localName: elementName,
            qualifiedName: qName ?? elementName
        ))
        popNamespaceFrame()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if pendingText == nil {
            pendingText = string
        } else {
            pendingText! += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        let string = String(decoding: CDATABlock, as: UTF8.self)
        if pendingText == nil {
            pendingText = string
        } else {
            pendingText! += string
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        if parseError == nil {
            parseError = error
        }
    }

    func parser(_ parser: XMLParser, validationErrorOccurred error: Error) {
        if parseError == nil {
            parseError = error
        }
    }

    private func flushPendingText() {
        if let text = pendingText {
            events.append(.text(text))
            pendingText = nil
        }
    }

    /// Foundation's `XMLParser` exposes attributes as a flat `[String:
    /// String]` keyed by the qualified name. To classify each attribute
    /// per the RDF/XML grammar we need its absolute namespace URI — which
    /// Foundation has, but only emits via the `shouldProcessNamespaces /
    /// shouldReportNamespacePrefixes` delegate hooks during element start.
    /// Those hooks come *before* `didStartElement`, and Foundation does
    /// not surface a per-attribute namespace map directly.
    ///
    /// To recover the namespace URI we keep a stack of in-scope prefix
    /// bindings (`namespaceStack`), updated by `didStartMappingPrefix` /
    /// `didEndMappingPrefix`, and rewrite each `prefix:local` attribute
    /// into its absolute form using that stack.
    private func collectAttributes(
        qName: String,
        attributes attributeDict: [String : String]
    ) -> [RDFXMLEvent.Attribute] {
        var result: [RDFXMLEvent.Attribute] = []
        for (name, value) in attributeDict {
            let resolved = resolveQName(name, isAttribute: true)
            result.append(RDFXMLEvent.Attribute(
                namespaceURI: resolved.namespaceURI,
                localName: resolved.localName,
                qualifiedName: name,
                value: value
            ))
        }
        return result
    }

    // MARK: - Namespace stack

    /// In-scope prefix → namespace URI bindings, innermost first.
    private var namespaceStack: [[String: String]] = [[:]]

    func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
        // Foundation calls this *before* `didStartElement`. Stage the binding
        // in a pending frame that will be merged when the element actually
        // starts.
        if pendingNamespaceFrame == nil {
            pendingNamespaceFrame = [:]
        }
        pendingNamespaceFrame![prefix] = namespaceURI
    }

    func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
        // Bindings unwind in element-end order. Since we push one frame per
        // element on `didStartElement`, no per-prefix bookkeeping is needed
        // here.
        _ = prefix
    }

    private var pendingNamespaceFrame: [String: String]?

    /// Merge the pending mapping prefix events into a new frame.
    private func pushNamespaceFrame() {
        if let frame = pendingNamespaceFrame {
            namespaceStack.append(frame)
            pendingNamespaceFrame = nil
        } else {
            namespaceStack.append([:])
        }
    }

    private func popNamespaceFrame() {
        if namespaceStack.count > 1 {
            namespaceStack.removeLast()
        }
    }

    func parserDidStartDocument(_ parser: XMLParser) {
        // Reset state in case the same collector is reused.
        events.removeAll()
        parseError = nil
        pendingText = nil
        namespaceStack = [[:]]
        pendingNamespaceFrame = nil
    }

    private func resolveQName(_ qName: String, isAttribute: Bool) -> (namespaceURI: String, localName: String) {
        if let colon = qName.firstIndex(of: ":") {
            let prefix = String(qName[..<colon])
            let localStart = qName.index(after: colon)
            let local = String(qName[localStart...])
            if let uri = lookupPrefix(prefix) {
                return (uri, local)
            }
            // xml: is always bound by spec.
            if prefix == "xml" {
                return (RDFXMLConstants.xmlNS, local)
            }
            // Unbound prefix on an attribute — leave the namespace empty
            // and let the grammar reject if it cares.
            return ("", local)
        }
        // No prefix: default namespace applies only to elements, not
        // attributes (XML Namespaces §6.2).
        if isAttribute {
            return ("", qName)
        }
        if let defaultNS = lookupPrefix("") {
            return (defaultNS, qName)
        }
        return ("", qName)
    }

    private func lookupPrefix(_ prefix: String) -> String? {
        // Search innermost first.
        for frame in namespaceStack.reversed() {
            if let uri = frame[prefix] {
                return uri
            }
        }
        // Also consult the pending frame (the one Foundation is staging for
        // the element we're about to enter).
        if let pending = pendingNamespaceFrame, let uri = pending[prefix] {
            return uri
        }
        return nil
    }
}
