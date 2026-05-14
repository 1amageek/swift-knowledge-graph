import Foundation

/// JSON-LD 1.1 Value Expansion (§4.5).
///
/// Turns a scalar JSON value into the expanded value-object form (a JSON
/// object with `@value`, optionally `@type`, `@language`, `@direction`).
/// The active term definition supplies type / language / direction hints.
enum JSONLDValueExpansion {

    static let xsdInteger = "http://www.w3.org/2001/XMLSchema#integer"
    static let xsdDouble  = "http://www.w3.org/2001/XMLSchema#double"
    static let xsdBoolean = "http://www.w3.org/2001/XMLSchema#boolean"
    static let xsdString  = "http://www.w3.org/2001/XMLSchema#string"

    static func expand(
        value: JSONValue,
        term: JSONLDTermDefinition?,
        context: JSONLDContext
    ) -> JSONValue {
        if let term, term.typeMapping == "@id", case .string(let s) = value {
            if let expanded = JSONLDIRIExpansion.expand(
                s, context: context, documentRelative: true, vocab: false
            ) {
                return .object([JSONLDKeyword.id: .string(expanded)])
            }
            return .object([JSONLDKeyword.id: .string(s)])
        }
        if let term, term.typeMapping == "@vocab", case .string(let s) = value {
            if let expanded = JSONLDIRIExpansion.expand(
                s, context: context, documentRelative: true, vocab: true
            ) {
                return .object([JSONLDKeyword.id: .string(expanded)])
            }
            return .object([JSONLDKeyword.id: .string(s)])
        }
        if let term, term.typeMapping == "@json" {
            return .object([
                JSONLDKeyword.value: value,
                JSONLDKeyword.type: .string("@json")
            ])
        }

        var result: [String: JSONValue] = [JSONLDKeyword.value: value]

        if let term, let typeMapping = term.typeMapping,
           typeMapping != "@id", typeMapping != "@vocab",
           typeMapping != "@json", typeMapping != "@none" {
            result[JSONLDKeyword.type] = .string(typeMapping)
            return .object(result)
        }

        switch value {
        case .string(let s):
            if let term, let lang = term.languageMapping {
                if !lang.isEmpty {
                    result[JSONLDKeyword.language] = .string(lang)
                }
            } else if let lang = context.defaultLanguage {
                result[JSONLDKeyword.language] = .string(lang)
            }
            if let term, let dir = term.directionMapping {
                if !dir.isEmpty {
                    result[JSONLDKeyword.direction] = .string(dir)
                }
            } else if let dir = context.defaultDirection {
                result[JSONLDKeyword.direction] = .string(dir)
            }
            _ = s
        case .bool:
            result[JSONLDKeyword.type] = .string(xsdBoolean)
        case .int:
            result[JSONLDKeyword.type] = .string(xsdInteger)
        case .double:
            result[JSONLDKeyword.type] = .string(xsdDouble)
        default:
            break
        }
        return .object(result)
    }
}
