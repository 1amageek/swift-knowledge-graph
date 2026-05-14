import Foundation

/// JSON-LD 1.1 Context Processing algorithm (§4.1).
///
/// Processes a single local-context value or an array of them, returning a
/// new active context. Remote contexts (string-form `@context` values) are
/// rejected — the spec allows them, but our `No network` invariant forbids
/// any default HTTP fetch. A future revision can add an injected
/// `JSONLDContextResolver` to handle that.
struct JSONLDContextProcessing {

    let position: SourcePosition

    init(position: SourcePosition = .start) {
        self.position = position
    }

    /// §4.1 step 1-13. `local` is the raw `@context` value; `active` is the
    /// context to extend; `remoteContexts` is the cycle-detection list (used
    /// when a remote resolver is wired up — currently unused).
    func process(
        local: JSONValue,
        active: JSONLDContext
    ) throws -> JSONLDContext {
        var result = active
        let locals: [JSONValue]
        switch local {
        case .array(let arr):
            locals = arr
        case .null:
            locals = [.null]
        default:
            locals = [local]
        }
        for ctx in locals {
            switch ctx {
            case .null:
                // §4.1.5.1: resetting to a new initial context.
                result = JSONLDContext(baseIRI: active.baseIRI)
            case .string:
                throw ParserError.unsupportedFeature(
                    name: "remote @context",
                    at: position
                )
            case .object(let dict):
                result = try processObjectContext(dict, into: result)
            default:
                throw ParserError.jsonSyntax(
                    detail: "@context entry must be null, an object, or an array",
                    at: position
                )
            }
        }
        return result
    }

    // MARK: - Object context

    private func processObjectContext(
        _ dict: [String: JSONValue],
        into base: JSONLDContext
    ) throws -> JSONLDContext {
        var result = base

        if let v = dict[JSONLDKeyword.version] {
            switch v {
            case .double(let d):
                result.version = d
            case .int(let i):
                result.version = Double(i)
            default:
                throw ParserError.invalidLiteral(
                    value: "@version",
                    at: position,
                    reason: "must be a number"
                )
            }
        }

        if let v = dict[JSONLDKeyword.base] {
            switch v {
            case .null:
                result.baseIRI = nil
            case .string(let s):
                if s.isEmpty {
                    // §4.1.5: empty string means inherit current base.
                    break
                }
                if let existing = result.baseIRI {
                    result.baseIRI = IRIResolver.resolve(reference: s, against: existing)
                } else {
                    result.baseIRI = s
                }
            default:
                throw ParserError.invalidLiteral(
                    value: "@base",
                    at: position,
                    reason: "must be null or an IRI string"
                )
            }
        }

        if let v = dict[JSONLDKeyword.vocab] {
            switch v {
            case .null:
                result.vocab = nil
            case .string(let s):
                // §4.1.5.2: the vocab value is itself an IRI / blank-node
                // identifier / vocab-relative term. Expand against the
                // current context (after @base / previous @vocab have been
                // applied to `result`) before storing — otherwise terms
                // resolved against this @vocab pick up the raw string and
                // produce malformed IRIs.
                if s.isEmpty {
                    result.vocab = ""
                } else if s.hasPrefix("_:") {
                    result.vocab = s
                } else if let expanded = JSONLDIRIExpansion.expand(
                    s, context: result, documentRelative: true, vocab: true
                ) {
                    result.vocab = expanded
                } else {
                    throw ParserError.invalidLiteral(
                        value: "@vocab",
                        at: position,
                        reason: "could not expand \(s) to an absolute IRI"
                    )
                }
            default:
                throw ParserError.invalidLiteral(
                    value: "@vocab",
                    at: position,
                    reason: "must be null or a string"
                )
            }
        }

        if let v = dict[JSONLDKeyword.language] {
            switch v {
            case .null:
                result.defaultLanguage = nil
            case .string(let s):
                result.defaultLanguage = s
            default:
                throw ParserError.invalidLiteral(
                    value: "@language",
                    at: position,
                    reason: "must be null or a string"
                )
            }
        }

        if let v = dict[JSONLDKeyword.direction] {
            switch v {
            case .null:
                result.defaultDirection = nil
            case .string(let s):
                guard s == "ltr" || s == "rtl" else {
                    throw ParserError.invalidLiteral(
                        value: s,
                        at: position,
                        reason: "@direction must be 'ltr' or 'rtl'"
                    )
                }
                result.defaultDirection = s
            default:
                throw ParserError.invalidLiteral(
                    value: "@direction",
                    at: position,
                    reason: "must be null or 'ltr'/'rtl'"
                )
            }
        }

        if let v = dict[JSONLDKeyword.propagate] {
            switch v {
            case .bool(let b):
                result.propagate = b
            default:
                throw ParserError.invalidLiteral(
                    value: "@propagate",
                    at: position,
                    reason: "must be a boolean"
                )
            }
        }

        // Process term definitions for every non-keyword key. Use the
        // `defined` map to detect cycles per §4.2.
        var defined: [String: Bool] = [:]
        let reservedKeys: Set<String> = [
            JSONLDKeyword.version, JSONLDKeyword.base, JSONLDKeyword.vocab,
            JSONLDKeyword.language, JSONLDKeyword.direction,
            JSONLDKeyword.propagate, JSONLDKeyword.protected,
            JSONLDKeyword.import
        ]
        for (term, _) in dict where !reservedKeys.contains(term) {
            try createTermDefinition(
                term: term,
                local: dict,
                active: &result,
                defined: &defined
            )
        }
        return result
    }

    // MARK: - Term definition (§4.2)

    private func createTermDefinition(
        term: String,
        local: [String: JSONValue],
        active: inout JSONLDContext,
        defined: inout [String: Bool]
    ) throws {
        if let state = defined[term] {
            if state { return }
            throw ParserError.grammar(
                production: "term definition",
                at: position,
                detail: "cyclic IRI mapping for \(term)"
            )
        }
        defined[term] = false
        if term.isEmpty {
            throw ParserError.grammar(
                production: "term definition",
                at: position,
                detail: "empty term name"
            )
        }
        guard let value = local[term] else {
            defined[term] = true
            return
        }

        // null value: remove any existing definition.
        if value.isNull {
            active.terms[term] = nil
            defined[term] = true
            return
        }

        // String shorthand: { "term": "iri-or-term" }
        if case .string(let s) = value {
            guard let expanded = JSONLDIRIExpansion.expand(
                s, context: active, documentRelative: false, vocab: true
            ) else {
                throw ParserError.grammar(
                    production: "term definition",
                    at: position,
                    detail: "could not expand IRI mapping for \(term)"
                )
            }
            active.terms[term] = JSONLDTermDefinition(
                iri: expanded,
                prefix: isPrefixIRI(expanded)
            )
            defined[term] = true
            return
        }

        guard case .object(let body) = value else {
            throw ParserError.grammar(
                production: "term definition",
                at: position,
                detail: "term value must be null, a string, or an object"
            )
        }

        var def = JSONLDTermDefinition()

        if let typeVal = body[JSONLDKeyword.type] {
            guard case .string(let typeStr) = typeVal else {
                throw ParserError.grammar(
                    production: "term @type",
                    at: position,
                    detail: "must be a string"
                )
            }
            if typeStr == "@id" || typeStr == "@vocab" || typeStr == "@json" || typeStr == "@none" {
                def.typeMapping = typeStr
            } else if let expanded = JSONLDIRIExpansion.expand(
                typeStr, context: active, documentRelative: false, vocab: true
            ) {
                def.typeMapping = expanded
            } else {
                throw ParserError.grammar(
                    production: "term @type",
                    at: position,
                    detail: "invalid type mapping \(typeStr)"
                )
            }
        }

        if let lang = body[JSONLDKeyword.language] {
            switch lang {
            case .null:
                def.languageMapping = ""
            case .string(let s):
                def.languageMapping = s
            default:
                throw ParserError.grammar(
                    production: "term @language",
                    at: position,
                    detail: "must be null or a string"
                )
            }
        }

        if let dir = body[JSONLDKeyword.direction] {
            switch dir {
            case .null:
                def.directionMapping = ""
            case .string(let s):
                guard s == "ltr" || s == "rtl" else {
                    throw ParserError.invalidLiteral(
                        value: s,
                        at: position,
                        reason: "@direction must be 'ltr' or 'rtl'"
                    )
                }
                def.directionMapping = s
            default:
                throw ParserError.grammar(
                    production: "term @direction",
                    at: position,
                    detail: "must be null or 'ltr'/'rtl'"
                )
            }
        }

        if let cont = body[JSONLDKeyword.container] {
            let containers = try parseContainer(cont)
            def.container = containers
        }

        if let pref = body[JSONLDKeyword.prefix] {
            guard case .bool(let b) = pref else {
                throw ParserError.grammar(
                    production: "term @prefix",
                    at: position,
                    detail: "must be a boolean"
                )
            }
            def.prefix = b
        }

        if let prot = body[JSONLDKeyword.protected] {
            guard case .bool(let b) = prot else {
                throw ParserError.grammar(
                    production: "term @protected",
                    at: position,
                    detail: "must be a boolean"
                )
            }
            def.protected = b
        }

        if let rev = body[JSONLDKeyword.reverse] {
            guard case .string(let s) = rev else {
                throw ParserError.grammar(
                    production: "term @reverse",
                    at: position,
                    detail: "must be a string"
                )
            }
            guard let expanded = JSONLDIRIExpansion.expand(
                s, context: active, documentRelative: false, vocab: true
            ) else {
                throw ParserError.grammar(
                    production: "term @reverse",
                    at: position,
                    detail: "could not expand reverse mapping \(s)"
                )
            }
            def.iri = expanded
            def.reverse = true
        }

        if let id = body[JSONLDKeyword.id], !def.reverse {
            switch id {
            case .null:
                break
            case .string(let s):
                if s == term {
                    // Self-reference; skip expansion.
                } else if JSONLDKeyword.isKnown(s) {
                    def.iri = s
                } else {
                    guard let expanded = JSONLDIRIExpansion.expand(
                        s, context: active, documentRelative: false, vocab: true
                    ) else {
                        throw ParserError.grammar(
                            production: "term @id",
                            at: position,
                            detail: "could not expand id mapping for \(term)"
                        )
                    }
                    def.iri = expanded
                }
            default:
                throw ParserError.grammar(
                    production: "term @id",
                    at: position,
                    detail: "must be null or a string"
                )
            }
        }

        if def.iri == nil && !def.reverse {
            // Fall back to vocab + term, or treat the term name itself as a
            // compact IRI / absolute IRI.
            if let expanded = JSONLDIRIExpansion.expand(
                term, context: active, documentRelative: false, vocab: true
            ) {
                def.iri = expanded
            }
        }

        // §4.2 Step 22: in json-ld-1.1 mode the prefix flag is only set when
        // @prefix is explicit in the object form. Auto-detection from a
        // gen-delim-terminated IRI is reserved for the simple-string
        // shorthand (handled at the early-return above). Object-form
        // definitions without @prefix keep the default `prefix = false`.

        active.terms[term] = def
        defined[term] = true
    }

    /// §4.2.6 — an IRI mapping that ends with a gen-delim character marks
    /// the term as a candidate compact-IRI prefix.
    private func isPrefixIRI(_ iri: String) -> Bool {
        guard let last = iri.last else { return false }
        switch last {
        case "/", "#", ":", "?", "[", "]", "@":
            return true
        default:
            return false
        }
    }

    private func parseContainer(_ value: JSONValue) throws -> Set<String> {
        switch value {
        case .string(let s):
            return [s]
        case .array(let arr):
            var set: Set<String> = []
            for entry in arr {
                guard case .string(let s) = entry else {
                    throw ParserError.grammar(
                        production: "term @container",
                        at: position,
                        detail: "container array entries must be strings"
                    )
                }
                set.insert(s)
            }
            return set
        case .null:
            return []
        default:
            throw ParserError.grammar(
                production: "term @container",
                at: position,
                detail: "must be a string or array of strings"
            )
        }
    }

}
