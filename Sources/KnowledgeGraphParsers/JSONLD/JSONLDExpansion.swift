import Foundation

/// JSON-LD 1.1 Expansion algorithm (§4.2).
///
/// Turns the compact JSON-LD form into the spec's expanded form. The
/// expanded form is a plain JSON tree where every property key is either a
/// keyword or an absolute IRI, every value object exposes `@value` /
/// `@type` / `@language` / `@direction` explicitly, and every node object
/// is wrapped consistently.
struct JSONLDExpansion {

    var position: SourcePosition

    init(position: SourcePosition = .start) {
        self.position = position
    }

    /// Top-level expansion: returns an array of expanded node objects.
    mutating func expandDocument(
        _ value: JSONValue,
        context: JSONLDContext
    ) throws -> [JSONValue] {
        let expanded = try expand(
            element: value,
            context: context,
            activeProperty: nil
        )
        switch expanded {
        case .null:
            return []
        case .array(let arr):
            return arr.compactMap { $0.isNull ? nil : $0 }
        default:
            return [expanded]
        }
    }

    // MARK: - Core expansion

    mutating func expand(
        element: JSONValue,
        context: JSONLDContext,
        activeProperty: String?
    ) throws -> JSONValue {
        switch element {
        case .null:
            return .null
        case .array(let arr):
            return try expandArray(arr, context: context, activeProperty: activeProperty)
        case .object(let dict):
            return try expandObject(dict, context: context, activeProperty: activeProperty)
        default:
            if activeProperty == nil || activeProperty == JSONLDKeyword.graph {
                return .null
            }
            let term = activeProperty.flatMap { context.terms[$0] }
            return JSONLDValueExpansion.expand(
                value: element, term: term, context: context
            )
        }
    }

    private mutating func expandArray(
        _ array: [JSONValue],
        context: JSONLDContext,
        activeProperty: String?
    ) throws -> JSONValue {
        var result: [JSONValue] = []
        let term = activeProperty.flatMap { context.terms[$0] }
        let isListContainer = term?.container.contains(JSONLDKeyword.list) ?? false
        for entry in array {
            let expanded = try expand(
                element: entry, context: context, activeProperty: activeProperty
            )
            switch expanded {
            case .null:
                continue
            case .array(let nested):
                result.append(contentsOf: nested)
            default:
                result.append(expanded)
            }
        }
        if isListContainer {
            return .object([JSONLDKeyword.list: .array(result)])
        }
        return .array(result)
    }

    private mutating func expandObject(
        _ object: [String: JSONValue],
        context: JSONLDContext,
        activeProperty: String?
    ) throws -> JSONValue {
        var localContext = context

        if let ctxValue = object[JSONLDKeyword.context] {
            localContext = try JSONLDContextProcessing(position: position)
                .process(local: ctxValue, active: localContext)
        }

        var result: [String: JSONValue] = [:]
        let sortedKeys = object.keys.sorted()

        for key in sortedKeys {
            if key == JSONLDKeyword.context { continue }
            guard let value = object[key] else { continue }

            let expandedKey: String?
            if JSONLDKeyword.isKnown(key) {
                expandedKey = key
            } else {
                expandedKey = JSONLDIRIExpansion.expand(
                    key, context: localContext, documentRelative: false, vocab: true
                )
            }
            guard let expandedProperty = expandedKey else { continue }

            if !expandedProperty.contains(":") && !JSONLDKeyword.isKnown(expandedProperty) {
                continue
            }

            try handleProperty(
                expandedProperty: expandedProperty,
                originalKey: key,
                value: value,
                context: localContext,
                result: &result
            )
        }

        return try finalizeResult(result, activeProperty: activeProperty, context: localContext)
    }

    private mutating func handleProperty(
        expandedProperty: String,
        originalKey: String,
        value: JSONValue,
        context: JSONLDContext,
        result: inout [String: JSONValue]
    ) throws {
        switch expandedProperty {
        case JSONLDKeyword.id:
            guard case .string(let s) = value else {
                throw ParserError.grammar(
                    production: "@id",
                    at: position,
                    detail: "must be a string"
                )
            }
            guard let expanded = JSONLDIRIExpansion.expand(
                s, context: context, documentRelative: true, vocab: false
            ) else {
                throw ParserError.grammar(
                    production: "@id",
                    at: position,
                    detail: "could not expand \(s)"
                )
            }
            result[JSONLDKeyword.id] = .string(expanded)

        case JSONLDKeyword.type:
            let types = try expandTypeValue(value, context: context)
            result[JSONLDKeyword.type] = .array(types.map { .string($0) })

        case JSONLDKeyword.value:
            result[JSONLDKeyword.value] = value

        case JSONLDKeyword.language:
            result[JSONLDKeyword.language] = value

        case JSONLDKeyword.direction:
            result[JSONLDKeyword.direction] = value

        case JSONLDKeyword.index:
            result[JSONLDKeyword.index] = value

        case JSONLDKeyword.list:
            let expanded = try expand(element: value, context: context, activeProperty: originalKey)
            let listItems: [JSONValue]
            switch expanded {
            case .array(let a): listItems = a
            case .null: listItems = []
            default: listItems = [expanded]
            }
            result[JSONLDKeyword.list] = .array(listItems)

        case JSONLDKeyword.set:
            let expanded = try expand(element: value, context: context, activeProperty: originalKey)
            switch expanded {
            case .array:
                result[JSONLDKeyword.set] = expanded
            default:
                result[JSONLDKeyword.set] = .array([expanded])
            }

        case JSONLDKeyword.graph:
            let expanded = try expand(element: value, context: context, activeProperty: JSONLDKeyword.graph)
            switch expanded {
            case .array:
                result[JSONLDKeyword.graph] = expanded
            case .null:
                result[JSONLDKeyword.graph] = .array([])
            default:
                result[JSONLDKeyword.graph] = .array([expanded])
            }

        case JSONLDKeyword.included:
            let expanded = try expand(element: value, context: context, activeProperty: nil)
            switch expanded {
            case .array: result[JSONLDKeyword.included] = expanded
            case .null: result[JSONLDKeyword.included] = .array([])
            default: result[JSONLDKeyword.included] = .array([expanded])
            }

        case JSONLDKeyword.reverse:
            try handleReverse(value: value, context: context, result: &result)

        default:
            try handleRegularProperty(
                expandedProperty: expandedProperty,
                originalKey: originalKey,
                value: value,
                context: context,
                result: &result
            )
        }
    }

    private mutating func handleRegularProperty(
        expandedProperty: String,
        originalKey: String,
        value: JSONValue,
        context: JSONLDContext,
        result: inout [String: JSONValue]
    ) throws {
        let term = context.terms[originalKey]
        let expanded = try expand(
            element: value, context: context, activeProperty: originalKey
        )
        let normalised: JSONValue
        if let term, term.container.contains(JSONLDKeyword.list),
           !isListObject(expanded) {
            let items: [JSONValue]
            switch expanded {
            case .array(let a): items = a
            case .null: items = []
            default: items = [expanded]
            }
            normalised = .object([JSONLDKeyword.list: .array(items)])
        } else {
            normalised = expanded
        }

        if normalised.isNull { return }

        if let term, term.reverse {
            var reverseMap: [String: JSONValue] = [:]
            if let existing = result[JSONLDKeyword.reverse]?.asObject {
                reverseMap = existing
            }
            var bucket: [JSONValue] = []
            if let existing = reverseMap[expandedProperty]?.asArray {
                bucket = existing
            }
            switch normalised {
            case .array(let a): bucket.append(contentsOf: a)
            default: bucket.append(normalised)
            }
            reverseMap[expandedProperty] = .array(bucket)
            result[JSONLDKeyword.reverse] = .object(reverseMap)
            return
        }

        var bucket: [JSONValue] = []
        if let existing = result[expandedProperty]?.asArray {
            bucket = existing
        }
        switch normalised {
        case .array(let a): bucket.append(contentsOf: a)
        default: bucket.append(normalised)
        }
        result[expandedProperty] = .array(bucket)
    }

    private mutating func handleReverse(
        value: JSONValue,
        context: JSONLDContext,
        result: inout [String: JSONValue]
    ) throws {
        guard case .object(let dict) = value else {
            throw ParserError.grammar(
                production: "@reverse",
                at: position,
                detail: "must be an object"
            )
        }
        var reverseMap: [String: JSONValue] = [:]
        if let existing = result[JSONLDKeyword.reverse]?.asObject {
            reverseMap = existing
        }
        for (key, val) in dict {
            guard let expandedKey = JSONLDIRIExpansion.expand(
                key, context: context, documentRelative: false, vocab: true
            ), expandedKey.contains(":") else { continue }
            let expanded = try expand(element: val, context: context, activeProperty: key)
            let bucket: [JSONValue]
            switch expanded {
            case .array(let a): bucket = a
            case .null: bucket = []
            default: bucket = [expanded]
            }
            var current: [JSONValue] = []
            if let existing = reverseMap[expandedKey]?.asArray {
                current = existing
            }
            current.append(contentsOf: bucket)
            reverseMap[expandedKey] = .array(current)
        }
        result[JSONLDKeyword.reverse] = .object(reverseMap)
    }

    private mutating func expandTypeValue(
        _ value: JSONValue,
        context: JSONLDContext
    ) throws -> [String] {
        let entries: [JSONValue]
        switch value {
        case .array(let a): entries = a
        default: entries = [value]
        }
        var result: [String] = []
        for entry in entries {
            guard case .string(let s) = entry else {
                throw ParserError.grammar(
                    production: "@type",
                    at: position,
                    detail: "values must be strings"
                )
            }
            guard let expanded = JSONLDIRIExpansion.expand(
                s, context: context, documentRelative: true, vocab: true
            ) else {
                // §4.2: a @type value that does not expand to a keyword,
                // absolute IRI, or blank node identifier is dropped, not
                // promoted to an error — the surrounding node still parses.
                continue
            }
            if !JSONLDKeyword.isKnown(expanded)
                && !expanded.contains(":") {
                continue
            }
            result.append(expanded)
        }
        return result
    }

    private mutating func finalizeResult(
        _ raw: [String: JSONValue],
        activeProperty: String?,
        context: JSONLDContext
    ) throws -> JSONValue {
        var result = raw

        if result[JSONLDKeyword.value] != nil {
            let allowed: Set<String> = [
                JSONLDKeyword.value, JSONLDKeyword.type,
                JSONLDKeyword.language, JSONLDKeyword.direction,
                JSONLDKeyword.index
            ]
            for key in result.keys where !allowed.contains(key) {
                throw ParserError.grammar(
                    production: "value object",
                    at: position,
                    detail: "unexpected key \(key) alongside @value"
                )
            }
            if case .null = result[JSONLDKeyword.value]! {
                return .null
            }
            if let typeValue = result[JSONLDKeyword.type],
               case .array(let arr) = typeValue, arr.count == 1 {
                result[JSONLDKeyword.type] = arr[0]
            }
            if result[JSONLDKeyword.language] != nil {
                guard case .string = result[JSONLDKeyword.value]! else {
                    throw ParserError.grammar(
                        production: "value object",
                        at: position,
                        detail: "@language requires a string @value"
                    )
                }
            }
            return .object(result)
        }

        if let typeValue = result[JSONLDKeyword.type] {
            if case .array(let arr) = typeValue, arr.count == 1 {
                result[JSONLDKeyword.type] = arr[0]
            }
        }

        if let setValue = result[JSONLDKeyword.set] {
            return setValue
        }

        // §4.2.17: free-floating @graph at root / under @graph context is
        // promoted — drop the wrapper object and return its @graph array.
        // The spec restricts this to objects whose only entry is @graph: if
        // @index (or any other keyword) is also present, the wrapper must
        // be preserved so the index/id survives into node-map generation.
        if let graphValue = result[JSONLDKeyword.graph],
           (activeProperty == nil || activeProperty == JSONLDKeyword.graph) {
            if result.keys.allSatisfy({ $0 == JSONLDKeyword.graph }) {
                return graphValue
            }
        }

        if result.isEmpty {
            return .null
        }

        return .object(result)
    }

    private func isListObject(_ value: JSONValue) -> Bool {
        if case .object(let dict) = value, dict[JSONLDKeyword.list] != nil {
            return true
        }
        return false
    }
}
