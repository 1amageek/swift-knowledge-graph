import Foundation
import KnowledgeGraph
@testable import KnowledgeGraphParsers

/// Entry extracted from the W3C JSON-LD 1.1 `toRdf-manifest.jsonld`.
struct W3CJSONLDTestEntry: Sendable, CustomStringConvertible, Hashable {
    enum Kind: Sendable, Hashable {
        case positiveEval
        case negativeEval
    }

    let name: String
    let id: String
    let kind: Kind
    let inputURL: URL
    /// Only populated for `.positiveEval` — expected N-Quads file.
    let expectedURL: URL?
    let baseIRI: String
    let specVersion: String?
    /// Free-form per-entry options (e.g. `produceGeneralizedRdf`, `processingMode`).
    /// Used by the runner to decide whether a test is in our supported subset.
    let options: [String: JSONValue]
    /// Comma-separated `requires` tag from the manifest, when present.
    let requires: String?
    /// Manifest-declared error code for `.negativeEval` entries (e.g.
    /// `"invalid vocab mapping"`). Used by the test runner to record what
    /// the spec expected so the failure message is diagnostic rather than
    /// "some error was thrown".
    let expectErrorCode: String?

    var description: String { "\(id) \(name)" }
}

/// Static index over the bundled W3C JSON-LD 1.1 toRdf manifest.
///
/// The manifest is itself a JSON-LD document, but every relevant field is a
/// plain JSON property and the file does not require remote `@context`
/// resolution — so the lightweight `JSONValueDecoder` is enough to load it
/// without bootstrapping the full expansion algorithm.
enum W3CJSONLDSuite {

    static let baseTestIRI = "https://w3c.github.io/json-ld-api/tests/"

    static let manifestURL: URL = {
        guard let url = Bundle.module.url(
            forResource: "toRdf-manifest",
            withExtension: "jsonld",
            subdirectory: "jsonld-tests"
        ) else {
            fatalError("W3C JSON-LD toRdf-manifest.jsonld is not packaged as a test resource")
        }
        return url
    }()

    static let testsDirectory: URL = manifestURL.deletingLastPathComponent()

    static let allEntries: [W3CJSONLDTestEntry] = {
        do {
            return try loadEntries()
        } catch {
            fatalError("Failed to load W3C JSON-LD manifest: \(error)")
        }
    }()

    static var positiveEntries: [W3CJSONLDTestEntry] {
        allEntries.filter { $0.kind == .positiveEval }
    }

    static var negativeEntries: [W3CJSONLDTestEntry] {
        allEntries.filter { $0.kind == .negativeEval }
    }

    // MARK: - Loading

    private static func loadEntries() throws -> [W3CJSONLDTestEntry] {
        let data = try Data(contentsOf: manifestURL)
        let bytes = Array(data)
        let root = try JSONValueDecoder.decode(bytes)
        guard let object = root.asObject,
              let sequence = object["sequence"]?.asArray else {
            return []
        }
        var entries: [W3CJSONLDTestEntry] = []
        for value in sequence {
            guard let entry = value.asObject else { continue }
            guard let id = entry["@id"]?.asString,
                  let name = entry["name"]?.asString,
                  let input = entry["input"]?.asString,
                  let typeValue = entry["@type"] else { continue }
            let types: [String] = typeValue.asArray?.compactMap { $0.asString } ?? [typeValue.asString].compactMap { $0 }

            let kind: W3CJSONLDTestEntry.Kind
            if types.contains("jld:PositiveEvaluationTest") {
                kind = .positiveEval
            } else if types.contains("jld:NegativeEvaluationTest") {
                kind = .negativeEval
            } else {
                continue
            }
            guard types.contains("jld:ToRDFTest") else { continue }

            let inputURL = testsDirectory.appendingPathComponent(input)
            var expectedURL: URL?
            if let expect = entry["expect"]?.asString {
                expectedURL = testsDirectory.appendingPathComponent(expect)
            }

            var options: [String: JSONValue] = [:]
            var specVersion: String?
            if let optionObject = entry["option"]?.asObject {
                options = optionObject
                specVersion = optionObject["specVersion"]?.asString
            }
            let requires = entry["requires"]?.asString
            let expectErrorCode = entry["expectErrorCode"]?.asString

            let trimmedID = id.hasPrefix("#") ? String(id.dropFirst()) : id
            entries.append(W3CJSONLDTestEntry(
                name: name,
                id: trimmedID,
                kind: kind,
                inputURL: inputURL,
                expectedURL: expectedURL,
                baseIRI: baseTestIRI + input,
                specVersion: specVersion,
                options: options,
                requires: requires,
                expectErrorCode: expectErrorCode
            ))
        }
        return entries.sorted { $0.id < $1.id }
    }
}
