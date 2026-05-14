import Foundation
import KnowledgeGraph

/// Reusable Turtle / TriG grammar layer.
///
/// `TurtleGrammar` owns the token buffer, the `ParsingContext`, and an
/// optional named graph that triples are emitted into. Both `TurtleParser`
/// and `TriGParser` embed an instance and pump tokens from a shared
/// `TurtleTokenizer` into it.
///
/// Splitting the grammar from the driver lets TriG reuse Turtle's productions
/// (subjects, predicate-object lists, blank node property lists, collections,
/// literals) without duplicating ~300 lines, while letting each driver own
/// its own top-level statement dispatch.
struct TurtleGrammar {

    // MARK: - State

    var tokens: [Token]
    var head: Int
    var context: ParsingContext
    /// The named graph that newly inserted triples belong to. `nil` for the
    /// default graph (the only option in Turtle; TriG flips this between
    /// blocks).
    var currentGraph: String?

    /// Sentinel: a production needs more input than is currently buffered.
    /// The driver catches this and restores its checkpoint so the partial
    /// production is retried once more bytes arrive.
    struct NeedMoreInput: Error {}

    init(context: ParsingContext, currentGraph: String? = nil) {
        self.tokens = []
        self.head = 0
        self.context = context
        self.currentGraph = currentGraph
    }

    // MARK: - Token helpers

    mutating func expectToken() throws -> Token {
        guard head < tokens.count else {
            throw NeedMoreInput()
        }
        let token = tokens[head]
        head += 1
        return token
    }

    func peekToken() throws -> Token {
        guard head < tokens.count else {
            throw NeedMoreInput()
        }
        return tokens[head]
    }

    mutating func expectDot(production: String) throws {
        let tok = try expectToken()
        if case .dot = tok.kind { return }
        throw ParserError.grammar(
            production: production,
            at: tok.position,
            detail: "expected '.'"
        )
    }

    mutating func expectCloseBracket() throws {
        let tok = try expectToken()
        if case .closeBracket = tok.kind { return }
        throw ParserError.grammar(
            production: "blankNodePropertyList",
            at: tok.position,
            detail: "expected ']'"
        )
    }

    func isPredicateStartToken(_ token: Token) -> Bool {
        switch token.kind {
        case .iriRef, .prefixedName, .aKeyword:
            return true
        default:
            return false
        }
    }

    // MARK: - Triple insertion (graph-aware)

    @discardableResult
    private mutating func insertTriple(
        subject: NodeIdentifier,
        predicate: String,
        object: NodeIdentifier,
        into builder: inout KnowledgeGraphBuilder
    ) throws -> EdgeIdentifier {
        try builder.insertTriple(
            subject: subject,
            predicate: predicate,
            object: object,
            namedGraph: currentGraph
        )
    }

    // MARK: - Top level (Turtle statement)

    mutating func parseStatement(into builder: inout KnowledgeGraphBuilder) throws {
        let token = try peekToken()
        switch token.kind {
        case .prefixDirective:
            head += 1
            try parsePrefixDirective(opener: token, requiresDot: true)
        case .baseDirective:
            head += 1
            try parseBaseDirective(opener: token, requiresDot: true)
        case .sparqlPrefix:
            head += 1
            try parsePrefixDirective(opener: token, requiresDot: false)
        case .sparqlBase:
            head += 1
            try parseBaseDirective(opener: token, requiresDot: false)
        default:
            try parseTriples(into: &builder)
        }
    }

    // MARK: - Directives

    mutating func parsePrefixDirective(opener: Token, requiresDot: Bool) throws {
        let pname = try expectToken()
        guard case .prefixedName(let prefix, let local) = pname.kind, local.isEmpty else {
            throw ParserError.grammar(
                production: "prefixID",
                at: pname.position,
                detail: "expected PNAME_NS"
            )
        }
        let iri = try expectToken()
        guard case .iriRef(let iriValue) = iri.kind else {
            throw ParserError.grammar(
                production: "prefixID",
                at: iri.position,
                detail: "expected IRIREF"
            )
        }
        let resolved = try context.resolveIRIReference(iriValue, at: iri.position)
        context.declarePrefix(prefix, iri: resolved)
        _ = opener
        if requiresDot {
            try expectDot(production: "prefixID")
        }
    }

    mutating func parseBaseDirective(opener: Token, requiresDot: Bool) throws {
        let iri = try expectToken()
        guard case .iriRef(let iriValue) = iri.kind else {
            throw ParserError.grammar(
                production: "base",
                at: iri.position,
                detail: "expected IRIREF"
            )
        }
        let resolved = try context.resolveIRIReference(iriValue, at: iri.position)
        context.setBaseIRI(resolved)
        _ = opener
        if requiresDot {
            try expectDot(production: "base")
        }
    }

    // MARK: - Triples

    /// Parse one `triples '.'` production. Drivers that consume the trailing
    /// dot themselves (TriG inside `{ ... }`) should call `parseTriplesBody`
    /// instead.
    mutating func parseTriples(into builder: inout KnowledgeGraphBuilder) throws {
        try parseTriplesBody(into: &builder)
        try expectDot(production: "triples")
    }

    /// Parse the body of one `triples` production without consuming the
    /// trailing dot.
    mutating func parseTriplesBody(into builder: inout KnowledgeGraphBuilder) throws {
        let first = try peekToken()
        if case .openBracket = first.kind {
            head += 1
            let subject = context.freshBlankNode()
            let inner = try peekToken()
            if case .closeBracket = inner.kind {
                head += 1
            } else {
                try parsePredicateObjectListContent(subject: subject, into: &builder)
                try expectCloseBracket()
            }
            let afterBracket = try peekToken()
            if case .dot = afterBracket.kind {
                return
            }
            if case .closeBrace = afterBracket.kind {
                return
            }
            try parsePredicateObjectListContent(subject: subject, into: &builder)
            return
        }
        if case .openParen = first.kind {
            head += 1
            let subject = try parseCollection(into: &builder)
            try parsePredicateObjectListContent(subject: subject, into: &builder)
            return
        }
        let subject = try parseSubjectAtom()
        try parsePredicateObjectListContent(subject: subject, into: &builder)
    }

    mutating func parseSubjectAtom() throws -> NodeIdentifier {
        let tok = try expectToken()
        switch tok.kind {
        case .iriRef(let value):
            let resolved = try context.resolveIRIReference(value, at: tok.position)
            return NodeIdentifier.iri(resolved.value)
        case .prefixedName(let prefix, let local):
            let resolved = try context.resolveCURIE(prefix: prefix, suffix: local, at: tok.position)
            return NodeIdentifier.iri(resolved.value)
        case .blankNodeLabel(let label):
            return context.blankNode(forLabel: label)
        case .anon:
            return context.freshBlankNode()
        default:
            throw ParserError.grammar(
                production: "subject",
                at: tok.position,
                detail: "expected IRI / blank node / collection"
            )
        }
    }

    mutating func parsePredicateObjectListContent(
        subject: NodeIdentifier,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        try parsePredicateThenObjects(subject: subject, into: &builder)
        while true {
            let next = try peekToken()
            if case .semicolon = next.kind {
                head += 1
                while case .semicolon = (try peekToken()).kind {
                    head += 1
                }
                let after = try peekToken()
                if isPredicateStartToken(after) {
                    try parsePredicateThenObjects(subject: subject, into: &builder)
                }
                continue
            }
            break
        }
    }

    private mutating func parsePredicateThenObjects(
        subject: NodeIdentifier,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        let predicate = try parsePredicate()
        try parseObjectList(subject: subject, predicate: predicate, into: &builder)
    }

    mutating func parsePredicate() throws -> String {
        let tok = try expectToken()
        switch tok.kind {
        case .aKeyword:
            return "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        case .iriRef(let value):
            return (try context.resolveIRIReference(value, at: tok.position)).value
        case .prefixedName(let prefix, let local):
            return (try context.resolveCURIE(prefix: prefix, suffix: local, at: tok.position)).value
        default:
            throw ParserError.grammar(
                production: "predicate",
                at: tok.position,
                detail: "expected IRI / 'a' / prefixed name"
            )
        }
    }

    mutating func parseObjectList(
        subject: NodeIdentifier,
        predicate: String,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        let first = try parseObject(into: &builder)
        try insertTriple(subject: subject, predicate: predicate, object: first, into: &builder)
        while true {
            let next = try peekToken()
            if case .comma = next.kind {
                head += 1
                let object = try parseObject(into: &builder)
                try insertTriple(subject: subject, predicate: predicate, object: object, into: &builder)
                continue
            }
            break
        }
    }

    mutating func parseObject(into builder: inout KnowledgeGraphBuilder) throws -> NodeIdentifier {
        let tok = try expectToken()
        switch tok.kind {
        case .iriRef(let value):
            let resolved = try context.resolveIRIReference(value, at: tok.position)
            return NodeIdentifier.iri(resolved.value)
        case .prefixedName(let prefix, let local):
            let resolved = try context.resolveCURIE(prefix: prefix, suffix: local, at: tok.position)
            return NodeIdentifier.iri(resolved.value)
        case .blankNodeLabel(let label):
            return context.blankNode(forLabel: label)
        case .anon:
            return context.freshBlankNode()
        case .openBracket:
            let subject = context.freshBlankNode()
            let inner = try peekToken()
            if case .closeBracket = inner.kind {
                head += 1
                return subject
            }
            try parsePredicateObjectListContent(subject: subject, into: &builder)
            try expectCloseBracket()
            return subject
        case .openParen:
            return try parseCollection(into: &builder)
        case .stringLiteral(let value):
            return try completeLiteral(value: value)
        case .integer(let lexeme):
            return TurtleLiterals.integer(lexeme)
        case .decimal(let lexeme):
            return TurtleLiterals.decimal(lexeme)
        case .double(let lexeme):
            return TurtleLiterals.double(lexeme)
        case .boolean(let value):
            return TurtleLiterals.boolean(value)
        default:
            throw ParserError.grammar(
                production: "object",
                at: tok.position,
                detail: "expected IRI / blank / literal / collection"
            )
        }
    }

    mutating func completeLiteral(value: String) throws -> NodeIdentifier {
        let next = try peekToken()
        if case .langTag(let lang) = next.kind {
            head += 1
            return TurtleLiterals.langTagged(value, language: lang)
        }
        if case .doubleCaret = next.kind {
            head += 1
            let datatypeToken = try expectToken()
            switch datatypeToken.kind {
            case .iriRef(let dval):
                let resolved = try context.resolveIRIReference(dval, at: datatypeToken.position)
                return TurtleLiterals.typed(value, datatype: resolved.value)
            case .prefixedName(let prefix, let local):
                let resolved = try context.resolveCURIE(prefix: prefix, suffix: local, at: datatypeToken.position)
                return TurtleLiterals.typed(value, datatype: resolved.value)
            default:
                throw ParserError.grammar(
                    production: "datatype",
                    at: datatypeToken.position,
                    detail: "expected IRI / prefixed name"
                )
            }
        }
        return TurtleLiterals.plainString(value)
    }

    mutating func parseCollection(into builder: inout KnowledgeGraphBuilder) throws -> NodeIdentifier {
        let rdfFirst = "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
        let rdfRest = "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
        let rdfNil = NodeIdentifier.iri("http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")

        var items: [NodeIdentifier] = []
        while true {
            let next = try peekToken()
            if case .closeParen = next.kind {
                head += 1
                break
            }
            let item = try parseObject(into: &builder)
            items.append(item)
        }
        if items.isEmpty {
            return rdfNil
        }
        var listNodes: [NodeIdentifier] = []
        for _ in items {
            listNodes.append(context.freshBlankNode())
        }
        for (index, item) in items.enumerated() {
            let listHead = listNodes[index]
            let rest: NodeIdentifier = (index + 1 < items.count) ? listNodes[index + 1] : rdfNil
            try insertTriple(subject: listHead, predicate: rdfFirst, object: item, into: &builder)
            try insertTriple(subject: listHead, predicate: rdfRest, object: rest, into: &builder)
        }
        return listNodes[0]
    }
}
