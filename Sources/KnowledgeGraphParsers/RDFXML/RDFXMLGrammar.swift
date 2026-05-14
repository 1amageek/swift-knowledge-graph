import Foundation
import KnowledgeGraph

/// Recursive-descent driver for the RDF/XML 1.1 grammar (W3C §6).
///
/// The XML parsing layer is handled by Foundation's `XMLParser` via
/// `RDFXMLEventCollector`, which produces a flat `[RDFXMLEvent]` stream.
/// This struct walks that stream and emits triples through the supplied
/// `KnowledgeGraphBuilder`.
///
/// Why recursive descent over a state-machine implementation: RDF/XML
/// content is naturally tree-shaped (stripe grammar: subject / property /
/// subject / property / ...), and each production maps cleanly to one
/// method. The alternative — a single state machine driven by the event
/// stream — collapses the per-production constraints into a single
/// table, which makes it much harder to enforce things like "rdf:resource
/// requires an empty body" at the right point.
///
/// State threaded through the recursion:
/// - `scopeStack`: per-element `(xml:base, xml:lang)` bindings. Pushed
///   in `pushScope`, popped in `popScope`. Initialised from the parser's
///   `ParsingContext.baseIRI`.
/// - `seenIDs`: the set of fully-resolved IRIs already produced by
///   `rdf:ID` attributes. RDF/XML 1.1 §5.1.3 requires uniqueness within
///   the document.
/// - `context`: a `ParsingContext` for blank-node generation. The same
///   blank-node scope is shared across the whole parse so `rdf:nodeID`
///   re-uses map identically.
struct RDFXMLGrammar {

    var context: ParsingContext

    private var events: [RDFXMLEvent] = []
    private var index: Int = 0

    private struct Scope {
        var base: String?
        var lang: String?
    }
    private var scopeStack: [Scope] = []

    private var seenIDs: Set<String> = []

    init(context: ParsingContext) {
        self.context = context
    }

    // MARK: - Entry point

    mutating func run(
        events: [RDFXMLEvent],
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        self.events = events
        self.index = 0
        self.scopeStack = [Scope(base: context.baseIRI?.value, lang: nil)]
        try parseDocument(into: &builder)
    }

    // MARK: - Document level

    private mutating func parseDocument(
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        skipText()
        guard let event = peek() else {
            // Empty document — nothing to do.
            return
        }
        guard case .startElement(let ns, let local, _, _) = event else {
            throw ParserError.xmlSyntax(
                detail: "expected root element",
                at: .start
            )
        }
        if ns == RDFXMLConstants.rdfNS && local == "RDF" {
            try parseRDFRoot(into: &builder)
        } else {
            // RDF/XML 1.1 permits a single nodeElement as the document root
            // when an `rdf:RDF` wrapper would be redundant.
            _ = try parseNodeElement(into: &builder)
        }
        // Any further significant content is invalid.
        skipText()
        if let trailing = peek() {
            if case .startElement = trailing {
                throw ParserError.xmlSyntax(
                    detail: "extra element after document root",
                    at: .start
                )
            }
        }
    }

    private mutating func parseRDFRoot(
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        guard case .startElement(_, _, _, let attrs) = consume() else {
            throw ParserError.xmlSyntax(detail: "expected <rdf:RDF>", at: .start)
        }
        pushScope(attrs: attrs)
        defer { popScope() }

        // The rdf:RDF element itself carries no RDF semantics beyond
        // xml:base / xml:lang / namespace declarations. Anything else
        // (an rdf:ID attribute, a property attribute) is a spec violation.
        for attr in attrs where !isAllowedOnRDFRoot(attr) {
            throw ParserError.grammar(
                production: "rdf:RDF",
                at: .start,
                detail: "unexpected attribute \(attr.qualifiedName) on rdf:RDF"
            )
        }

        while true {
            skipText()
            guard let event = peek() else {
                throw ParserError.xmlSyntax(
                    detail: "unterminated rdf:RDF",
                    at: .start
                )
            }
            if case .endElement(let ns, let local, _) = event {
                if ns == RDFXMLConstants.rdfNS && local == "RDF" {
                    index += 1
                    return
                }
                throw ParserError.xmlSyntax(
                    detail: "mismatched end element </\(local)>",
                    at: .start
                )
            }
            _ = try parseNodeElement(into: &builder)
        }
    }

    private func isAllowedOnRDFRoot(_ attr: RDFXMLEvent.Attribute) -> Bool {
        if attr.namespaceURI == RDFXMLConstants.xmlNS { return true }
        if attr.namespaceURI == RDFXMLConstants.xmlnsNS { return true }
        if attr.qualifiedName == "xmlns" { return true }
        if attr.qualifiedName.hasPrefix("xmlns:") { return true }
        return false
    }

    // MARK: - Node elements

    /// Parse one nodeElement and return its subject. The element's start
    /// tag has already been peeked; both start and matching end are
    /// consumed inside this method.
    @discardableResult
    private mutating func parseNodeElement(
        into builder: inout KnowledgeGraphBuilder
    ) throws -> NodeIdentifier {
        guard case .startElement(let ns, let local, _, let attrs) = consume() else {
            throw ParserError.xmlSyntax(
                detail: "expected node element",
                at: .start
            )
        }
        let elementIRI = ns + local
        guard RDFXMLConstants.isValidNodeElement(elementIRI) else {
            throw ParserError.grammar(
                production: "nodeElementURI",
                at: .start,
                detail: "name not allowed as a node element: \(elementIRI)"
            )
        }

        pushScope(attrs: attrs)
        defer { popScope() }

        let subject = try identifySubject(attrs: attrs)

        // Emit rdf:type for the element name (unless rdf:Description).
        if elementIRI != RDFXMLConstants.rdfDescription {
            try builder.insertTriple(
                subject: subject,
                predicate: RDFXMLConstants.rdfType,
                object: .iri(elementIRI)
            )
        }

        // Property attributes on the node element.
        for attr in attrs {
            try maybeEmitNodePropertyAttribute(
                attr: attr,
                subject: subject,
                into: &builder
            )
        }

        // Property element list.
        var liCounter = 0
        while true {
            skipText()
            guard let event = peek() else {
                throw ParserError.xmlSyntax(
                    detail: "unterminated node element",
                    at: .start
                )
            }
            if case .endElement = event {
                index += 1
                return subject
            }
            try parsePropertyElement(
                parentSubject: subject,
                liCounter: &liCounter,
                into: &builder
            )
        }
    }

    private mutating func identifySubject(
        attrs: [RDFXMLEvent.Attribute]
    ) throws -> NodeIdentifier {
        var subject: NodeIdentifier?
        var sources: Set<String> = []
        for attr in attrs {
            switch attr.absoluteIRI {
            case RDFXMLConstants.rdfAbout:
                sources.insert("rdf:about")
                let resolved = try resolveIRI(attr.value)
                subject = .iri(resolved)
            case RDFXMLConstants.rdfID:
                sources.insert("rdf:ID")
                guard RDFXMLNCName.isValid(attr.value) else {
                    throw ParserError.grammar(
                        production: "rdf:ID",
                        at: .start,
                        detail: "not a valid NCName: \(attr.value)"
                    )
                }
                let resolved = try resolveIRI("#" + attr.value)
                try requireUniqueID(resolved)
                subject = .iri(resolved)
            case RDFXMLConstants.rdfNodeID:
                sources.insert("rdf:nodeID")
                guard RDFXMLNCName.isValid(attr.value) else {
                    throw ParserError.grammar(
                        production: "rdf:nodeID",
                        at: .start,
                        detail: "not a valid NCName: \(attr.value)"
                    )
                }
                subject = context.blankNode(forLabel: attr.value)
            default:
                break
            }
        }
        if sources.count > 1 {
            throw ParserError.grammar(
                production: "nodeElement",
                at: .start,
                detail: "conflicting subject attributes: \(sources.sorted().joined(separator: ", "))"
            )
        }
        return subject ?? context.freshBlankNode()
    }

    // MARK: - Property elements

    private mutating func parsePropertyElement(
        parentSubject: NodeIdentifier,
        liCounter: inout Int,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        guard case .startElement(let ns, let local, _, let attrs) = consume() else {
            throw ParserError.xmlSyntax(
                detail: "expected property element",
                at: .start
            )
        }
        var predicateIRI = ns + local
        guard RDFXMLConstants.isValidPropertyElement(predicateIRI) else {
            throw ParserError.grammar(
                production: "propertyElementURI",
                at: .start,
                detail: "name not allowed as a property element: \(predicateIRI)"
            )
        }
        if predicateIRI == RDFXMLConstants.rdfLi {
            liCounter += 1
            predicateIRI = RDFXMLConstants.rdfNS + "_\(liCounter)"
        }
        pushScope(attrs: attrs)
        defer { popScope() }

        // Pull out the syntactic attributes once so each branch can decide
        // independently whether their presence makes sense.
        let attrIndex = PropertyAttributeIndex(attrs: attrs)

        // Reject syntactically incompatible combinations up front.
        if attrIndex.parseType != nil {
            // parseType implies no rdf:resource / rdf:nodeID / rdf:datatype.
            if attrIndex.resource != nil
                || attrIndex.nodeID != nil
                || attrIndex.datatype != nil {
                throw ParserError.grammar(
                    production: "propertyElt",
                    at: .start,
                    detail: "parseType cannot combine with rdf:resource / rdf:nodeID / rdf:datatype"
                )
            }
        }
        if attrIndex.resource != nil && attrIndex.nodeID != nil {
            throw ParserError.grammar(
                production: "propertyElt",
                at: .start,
                detail: "rdf:resource and rdf:nodeID are mutually exclusive"
            )
        }
        if attrIndex.datatype != nil && (attrIndex.resource != nil || attrIndex.nodeID != nil) {
            throw ParserError.grammar(
                production: "propertyElt",
                at: .start,
                detail: "rdf:datatype cannot combine with rdf:resource / rdf:nodeID"
            )
        }

        switch attrIndex.parseType {
        case "Resource":
            try parseParseTypeResource(
                parentSubject: parentSubject,
                predicate: predicateIRI,
                rdfID: attrIndex.rdfID,
                into: &builder
            )
        case "Collection":
            try parseParseTypeCollection(
                parentSubject: parentSubject,
                predicate: predicateIRI,
                rdfID: attrIndex.rdfID,
                into: &builder
            )
        case "Literal", .some(_):
            // The spec says any value other than "Resource" / "Collection"
            // is treated as "Literal".
            try parseParseTypeLiteral(
                parentSubject: parentSubject,
                predicate: predicateIRI,
                rdfID: attrIndex.rdfID,
                into: &builder
            )
        case nil:
            try parseRegularProperty(
                parentSubject: parentSubject,
                predicate: predicateIRI,
                attrIndex: attrIndex,
                into: &builder
            )
        }
    }

    // MARK: - parseType="Resource"

    private mutating func parseParseTypeResource(
        parentSubject: NodeIdentifier,
        predicate: String,
        rdfID: String?,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        let object = context.freshBlankNode()
        try builder.insertTriple(
            subject: parentSubject,
            predicate: predicate,
            object: object
        )
        try maybeReify(
            rdfID: rdfID,
            s: parentSubject,
            p: predicate,
            o: object,
            into: &builder
        )
        var liCounter = 0
        while true {
            skipText()
            guard let event = peek() else {
                throw ParserError.xmlSyntax(
                    detail: "unterminated parseType=\"Resource\"",
                    at: .start
                )
            }
            if case .endElement = event {
                index += 1
                return
            }
            try parsePropertyElement(
                parentSubject: object,
                liCounter: &liCounter,
                into: &builder
            )
        }
    }

    // MARK: - parseType="Collection"

    private mutating func parseParseTypeCollection(
        parentSubject: NodeIdentifier,
        predicate: String,
        rdfID: String?,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        var members: [NodeIdentifier] = []
        while true {
            skipText()
            guard let event = peek() else {
                throw ParserError.xmlSyntax(
                    detail: "unterminated parseType=\"Collection\"",
                    at: .start
                )
            }
            if case .endElement = event {
                index += 1
                break
            }
            let member = try parseNodeElement(into: &builder)
            members.append(member)
        }
        let head = try buildCollectionList(members: members, into: &builder)
        try builder.insertTriple(
            subject: parentSubject,
            predicate: predicate,
            object: head
        )
        try maybeReify(
            rdfID: rdfID,
            s: parentSubject,
            p: predicate,
            o: head,
            into: &builder
        )
    }

    private mutating func buildCollectionList(
        members: [NodeIdentifier],
        into builder: inout KnowledgeGraphBuilder
    ) throws -> NodeIdentifier {
        if members.isEmpty {
            return .iri(RDFXMLConstants.rdfNil)
        }
        var cells: [NodeIdentifier] = []
        cells.reserveCapacity(members.count)
        for _ in members {
            cells.append(context.freshBlankNode())
        }
        for i in 0..<members.count {
            try builder.insertTriple(
                subject: cells[i],
                predicate: RDFXMLConstants.rdfFirst,
                object: members[i]
            )
            let rest: NodeIdentifier
            if i + 1 < cells.count {
                rest = cells[i + 1]
            } else {
                rest = .iri(RDFXMLConstants.rdfNil)
            }
            try builder.insertTriple(
                subject: cells[i],
                predicate: RDFXMLConstants.rdfRest,
                object: rest
            )
        }
        return cells[0]
    }

    // MARK: - parseType="Literal" (and unknown parseType)

    private mutating func parseParseTypeLiteral(
        parentSubject: NodeIdentifier,
        predicate: String,
        rdfID: String?,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        let (literal, endIndex) = try RDFXMLLiteralSerializer.serialize(
            events: events,
            start: index
        )
        index = endIndex + 1
        let object = NodeIdentifier.literal(
            value: literal,
            datatype: RDFXMLConstants.rdfXMLLiteral
        )
        try builder.insertTriple(
            subject: parentSubject,
            predicate: predicate,
            object: object
        )
        try maybeReify(
            rdfID: rdfID,
            s: parentSubject,
            p: predicate,
            o: object,
            into: &builder
        )
    }

    // MARK: - Property with no parseType

    private mutating func parseRegularProperty(
        parentSubject: NodeIdentifier,
        predicate: String,
        attrIndex: PropertyAttributeIndex,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        // Collect text up to the first start-of-child-element or end-of-property.
        var accumulatedText = ""
        while case .text(let s)? = peek() {
            accumulatedText += s
            index += 1
        }

        let nextEvent = peek()

        // Case 1: empty content (whitespace allowed) — emptyPropertyElt.
        if case .endElement? = nextEvent {
            index += 1
            let object = try buildEmptyPropertyObject(
                attrIndex: attrIndex,
                textContent: accumulatedText,
                into: &builder
            )
            try builder.insertTriple(
                subject: parentSubject,
                predicate: predicate,
                object: object
            )
            try maybeReify(
                rdfID: attrIndex.rdfID,
                s: parentSubject,
                p: predicate,
                o: object,
                into: &builder
            )
            return
        }

        // Case 2: child element follows — resourcePropertyElt. Leading text
        // must be whitespace-only.
        if case .startElement? = nextEvent {
            if !isAllWhitespace(accumulatedText) {
                throw ParserError.grammar(
                    production: "resourcePropertyElt",
                    at: .start,
                    detail: "mixed text and element content"
                )
            }
            // resourcePropertyElt rejects most syntactic attributes — only
            // rdf:ID may co-occur, since it reifies the produced triple.
            if attrIndex.resource != nil
                || attrIndex.nodeID != nil
                || attrIndex.datatype != nil
                || !attrIndex.propertyAttrs.isEmpty {
                throw ParserError.grammar(
                    production: "resourcePropertyElt",
                    at: .start,
                    detail: "resource property element cannot carry syntactic or property attributes"
                )
            }
            let object = try parseNodeElement(into: &builder)
            // After the child node element, only whitespace is allowed
            // before the closing tag.
            while case .text(let s)? = peek() {
                if !isAllWhitespace(s) {
                    throw ParserError.grammar(
                        production: "resourcePropertyElt",
                        at: .start,
                        detail: "trailing text after node element"
                    )
                }
                index += 1
            }
            guard case .endElement? = peek() else {
                throw ParserError.xmlSyntax(
                    detail: "expected </\(predicate)>",
                    at: .start
                )
            }
            index += 1
            try builder.insertTriple(
                subject: parentSubject,
                predicate: predicate,
                object: object
            )
            try maybeReify(
                rdfID: attrIndex.rdfID,
                s: parentSubject,
                p: predicate,
                o: object,
                into: &builder
            )
            return
        }

        throw ParserError.xmlSyntax(
            detail: "unterminated property element",
            at: .start
        )
    }

    /// Build the object for an empty propertyElement (one whose body
    /// contains no child elements). The decision tree comes straight from
    /// the spec algorithm in §7.2.16 / §7.2.21.
    private mutating func buildEmptyPropertyObject(
        attrIndex: PropertyAttributeIndex,
        textContent: String,
        into builder: inout KnowledgeGraphBuilder
    ) throws -> NodeIdentifier {
        // emptyPropertyElt: pure literal case — no resource / nodeID and
        // no non-syntactic property attributes. The text content (which
        // may itself be empty) becomes the literal value.
        if attrIndex.resource == nil
            && attrIndex.nodeID == nil
            && attrIndex.propertyAttrs.isEmpty {
            if let datatype = attrIndex.datatype {
                let datatypeIRI = try resolveIRI(datatype)
                return .literal(value: textContent, datatype: datatypeIRI)
            }
            if let lang = currentLang {
                return .literal(value: textContent, language: lang)
            }
            return .literal(value: textContent)
        }

        // emptyPropertyElt as a resource reference. rdf:resource and
        // rdf:nodeID have been validated mutually exclusive above.
        let subject: NodeIdentifier
        if let resource = attrIndex.resource {
            subject = .iri(try resolveIRI(resource))
        } else if let nodeID = attrIndex.nodeID {
            guard RDFXMLNCName.isValid(nodeID) else {
                throw ParserError.grammar(
                    production: "rdf:nodeID",
                    at: .start,
                    detail: "not a valid NCName: \(nodeID)"
                )
            }
            subject = context.blankNode(forLabel: nodeID)
        } else {
            // Property attributes only: a fresh blank node carries them.
            subject = context.freshBlankNode()
        }
        // Emit triples for each non-syntactic property attribute against
        // this synthetic subject.
        for attr in attrIndex.propertyAttrs {
            try maybeEmitNodePropertyAttribute(
                attr: attr,
                subject: subject,
                into: &builder
            )
        }
        return subject
    }

    // MARK: - Property attributes on a node element

    private mutating func maybeEmitNodePropertyAttribute(
        attr: RDFXMLEvent.Attribute,
        subject: NodeIdentifier,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        guard isPropertyAttribute(attr) else { return }

        guard RDFXMLConstants.isValidPropertyAttribute(attr.absoluteIRI) else {
            throw ParserError.grammar(
                production: "propertyAttributeURI",
                at: .start,
                detail: "name not allowed as property attribute: \(attr.absoluteIRI)"
            )
        }

        // rdf:type is special — its value is treated as an IRI reference
        // rather than a literal lexical form.
        if attr.absoluteIRI == RDFXMLConstants.rdfType {
            let resolved = try resolveIRI(attr.value)
            try builder.insertTriple(
                subject: subject,
                predicate: RDFXMLConstants.rdfType,
                object: .iri(resolved)
            )
            return
        }

        let object: NodeIdentifier
        if let lang = currentLang {
            object = .literal(value: attr.value, language: lang)
        } else {
            object = .literal(value: attr.value)
        }
        try builder.insertTriple(
            subject: subject,
            predicate: attr.absoluteIRI,
            object: object
        )
    }

    /// True if `attr` is a property attribute (i.e. neither an RDF
    /// syntactic attribute nor an XML housekeeping attribute).
    private func isPropertyAttribute(_ attr: RDFXMLEvent.Attribute) -> Bool {
        switch attr.absoluteIRI {
        case RDFXMLConstants.rdfID,
             RDFXMLConstants.rdfAbout,
             RDFXMLConstants.rdfNodeID,
             RDFXMLConstants.rdfResource,
             RDFXMLConstants.rdfDatatype,
             RDFXMLConstants.rdfParseType:
            return false
        default:
            break
        }
        if attr.namespaceURI == RDFXMLConstants.xmlNS { return false }
        if attr.namespaceURI == RDFXMLConstants.xmlnsNS { return false }
        if attr.qualifiedName == "xmlns" { return false }
        if attr.qualifiedName.hasPrefix("xmlns:") { return false }
        // Unprefixed attribute with no namespace URI is not an RDF property.
        if attr.namespaceURI.isEmpty { return false }
        return true
    }

    // MARK: - Reification

    private mutating func maybeReify(
        rdfID: String?,
        s: NodeIdentifier,
        p: String,
        o: NodeIdentifier,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        guard let rdfID else { return }
        guard RDFXMLNCName.isValid(rdfID) else {
            throw ParserError.grammar(
                production: "rdf:ID",
                at: .start,
                detail: "not a valid NCName: \(rdfID)"
            )
        }
        let stmtIRI = try resolveIRI("#" + rdfID)
        try requireUniqueID(stmtIRI)
        let stmt = NodeIdentifier.iri(stmtIRI)
        try builder.insertTriple(
            subject: stmt,
            predicate: RDFXMLConstants.rdfType,
            object: .iri(RDFXMLConstants.rdfStatement)
        )
        try builder.insertTriple(
            subject: stmt,
            predicate: RDFXMLConstants.rdfSubject,
            object: s
        )
        try builder.insertTriple(
            subject: stmt,
            predicate: RDFXMLConstants.rdfPredicate,
            object: .iri(p)
        )
        try builder.insertTriple(
            subject: stmt,
            predicate: RDFXMLConstants.rdfObject,
            object: o
        )
    }

    // MARK: - Scope (xml:base / xml:lang)

    private mutating func pushScope(attrs: [RDFXMLEvent.Attribute]) {
        var scope = scopeStack.last ?? Scope(base: nil, lang: nil)
        for attr in attrs {
            if attr.namespaceURI == RDFXMLConstants.xmlNS && attr.localName == "base" {
                if let currentBase = scope.base {
                    scope.base = IRIResolver.resolve(
                        reference: attr.value,
                        against: currentBase
                    )
                } else {
                    scope.base = attr.value
                }
            } else if attr.namespaceURI == RDFXMLConstants.xmlNS && attr.localName == "lang" {
                scope.lang = attr.value.isEmpty ? nil : attr.value
            }
        }
        scopeStack.append(scope)
    }

    private mutating func popScope() {
        if scopeStack.count > 1 {
            scopeStack.removeLast()
        }
    }

    private var currentBase: String? {
        scopeStack.last?.base
    }
    private var currentLang: String? {
        scopeStack.last?.lang
    }

    // MARK: - IRI resolution

    private func resolveIRI(_ reference: String) throws -> String {
        let parsed = IRIComponents.parse(reference)
        if let scheme = parsed.scheme, !scheme.isEmpty {
            return IRIResolver.resolve(reference: reference, against: "")
        }
        guard let base = currentBase else {
            throw ParserError.noBaseIRI(at: .start)
        }
        return IRIResolver.resolve(reference: reference, against: base)
    }

    private mutating func requireUniqueID(_ iri: String) throws {
        if seenIDs.contains(iri) {
            throw ParserError.grammar(
                production: "rdf:ID",
                at: .start,
                detail: "duplicate ID for IRI \(iri)"
            )
        }
        seenIDs.insert(iri)
    }

    // MARK: - Event cursor helpers

    private func peek() -> RDFXMLEvent? {
        index < events.count ? events[index] : nil
    }

    @discardableResult
    private mutating func consume() -> RDFXMLEvent? {
        guard index < events.count else { return nil }
        let event = events[index]
        index += 1
        return event
    }

    private mutating func skipText() {
        while case .text(_)? = peek() {
            index += 1
        }
    }

    private func isAllWhitespace(_ string: String) -> Bool {
        for char in string.unicodeScalars {
            switch char.value {
            case 0x20, 0x09, 0x0A, 0x0D:
                continue
            default:
                return false
            }
        }
        return true
    }

    // MARK: - Attribute index helper

    /// Pre-computed view over a property element's attributes. Sorting the
    /// attributes once at the entry to `parsePropertyElement` keeps each
    /// switch arm clear of repeated linear scans.
    private struct PropertyAttributeIndex {
        var rdfID: String?
        var resource: String?
        var nodeID: String?
        var datatype: String?
        var parseType: String?
        var propertyAttrs: [RDFXMLEvent.Attribute] = []

        init(attrs: [RDFXMLEvent.Attribute]) {
            for attr in attrs {
                switch attr.absoluteIRI {
                case RDFXMLConstants.rdfID:
                    rdfID = attr.value
                case RDFXMLConstants.rdfResource:
                    resource = attr.value
                case RDFXMLConstants.rdfNodeID:
                    nodeID = attr.value
                case RDFXMLConstants.rdfDatatype:
                    datatype = attr.value
                case RDFXMLConstants.rdfParseType:
                    parseType = attr.value
                default:
                    if attr.namespaceURI == RDFXMLConstants.xmlNS { continue }
                    if attr.namespaceURI == RDFXMLConstants.xmlnsNS { continue }
                    if attr.qualifiedName == "xmlns" { continue }
                    if attr.qualifiedName.hasPrefix("xmlns:") { continue }
                    if attr.namespaceURI.isEmpty { continue }
                    propertyAttrs.append(attr)
                }
            }
        }
    }
}
