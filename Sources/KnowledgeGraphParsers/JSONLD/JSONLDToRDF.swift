import Foundation
import KnowledgeGraph

/// JSON-LD 1.1 Deserialize-to-RDF algorithm (§5).
///
/// Walks a `JSONLDNodeMap` and emits triples into a
/// `KnowledgeGraphBuilder`. The default graph is emitted without a named
/// graph; every other graph keyed by an absolute IRI is emitted under that
/// IRI as a named graph.
struct JSONLDToRDF {

    static let rdfType  = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    static let rdfFirst = "http://www.w3.org/1999/02/22-rdf-syntax-ns#first"
    static let rdfRest  = "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest"
    static let rdfNil   = "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil"
    static let rdfJSON  = "http://www.w3.org/1999/02/22-rdf-syntax-ns#JSON"
    static let xsdString  = "http://www.w3.org/2001/XMLSchema#string"
    static let xsdBoolean = "http://www.w3.org/2001/XMLSchema#boolean"
    static let xsdInteger = "http://www.w3.org/2001/XMLSchema#integer"
    static let xsdDouble  = "http://www.w3.org/2001/XMLSchema#double"

    var context: ParsingContext
    var nextBlank: Int = 0
    /// Map of JSON-LD blank label (`_:b1`) to scoped NodeIdentifier so two
    /// occurrences of the same label resolve to the same node.
    var blankMap: [String: NodeIdentifier] = [:]

    init(context: ParsingContext) {
        self.context = context
    }

    mutating func emit(_ map: JSONLDNodeMap, into builder: inout KnowledgeGraphBuilder) throws {
        for graphName in map.graphs.keys.sorted() {
            guard let entries = map.graphs[graphName] else { continue }
            let graphID: String?
            if graphName == "@default" {
                graphID = nil
            } else if graphName.hasPrefix("_:") {
                // Blank-named graph: scope the label through ParsingContext
                // so the graph id matches the blank node's stable key, the
                // same convention NQuadsParser uses for blank graph terms.
                let node = resolveSubjectOrObject(id: graphName)
                graphID = node.key
                try builder.insertNamedGraph(NamedGraph(id: node.key))
            } else {
                graphID = graphName
                try builder.insertNamedGraph(NamedGraph(id: graphID!))
            }
            for subjectID in entries.keys.sorted() {
                let entry = entries[subjectID]!
                let subjectNode = resolveSubjectOrObject(id: subjectID)
                for type in entry.types {
                    let object = resolveSubjectOrObject(id: type)
                    try builder.insertTriple(
                        subject: subjectNode,
                        predicate: Self.rdfType,
                        object: object,
                        namedGraph: graphID
                    )
                }
                for property in entry.properties.keys.sorted() {
                    guard let values = entry.properties[property] else { continue }
                    for value in values {
                        try emitTriple(
                            subject: subjectNode,
                            predicate: property,
                            value: value,
                            graphID: graphID,
                            into: &builder
                        )
                    }
                }
            }
        }
    }

    private mutating func emitTriple(
        subject: NodeIdentifier,
        predicate: String,
        value: JSONValue,
        graphID: String?,
        into builder: inout KnowledgeGraphBuilder
    ) throws {
        guard case .object(let dict) = value else { return }

        if let listVal = dict[JSONLDKeyword.list] {
            let items: [JSONValue]
            switch listVal {
            case .array(let a): items = a
            default: items = []
            }
            let headObject = try emitList(items: items, graphID: graphID, into: &builder)
            try builder.insertTriple(
                subject: subject,
                predicate: predicate,
                object: headObject,
                namedGraph: graphID
            )
            return
        }

        if let valueVal = dict[JSONLDKeyword.value] {
            let literal = makeLiteral(value: valueVal, dict: dict)
            try builder.insertTriple(
                subject: subject,
                predicate: predicate,
                object: literal,
                namedGraph: graphID
            )
            return
        }

        if case .string(let id) = dict[JSONLDKeyword.id] ?? .null {
            let object = resolveSubjectOrObject(id: id)
            try builder.insertTriple(
                subject: subject,
                predicate: predicate,
                object: object,
                namedGraph: graphID
            )
        }
    }

    private mutating func emitList(
        items: [JSONValue],
        graphID: String?,
        into builder: inout KnowledgeGraphBuilder
    ) throws -> NodeIdentifier {
        if items.isEmpty {
            return .iri(Self.rdfNil)
        }
        var blankNodes: [NodeIdentifier] = []
        for _ in items { blankNodes.append(freshBlankNode()) }
        for (i, item) in items.enumerated() {
            let node = blankNodes[i]
            try emitTriple(
                subject: node,
                predicate: Self.rdfFirst,
                value: item,
                graphID: graphID,
                into: &builder
            )
            let next: NodeIdentifier = (i + 1 < items.count) ? blankNodes[i + 1] : .iri(Self.rdfNil)
            try builder.insertTriple(
                subject: node,
                predicate: Self.rdfRest,
                object: next,
                namedGraph: graphID
            )
        }
        return blankNodes[0]
    }

    private func makeLiteral(value: JSONValue, dict: [String: JSONValue]) -> NodeIdentifier {
        var datatype: String? = nil
        if case .string(let t) = dict[JSONLDKeyword.type] ?? .null {
            datatype = (t == "@json") ? Self.rdfJSON : t
        }
        var language: String? = nil
        if case .string(let l) = dict[JSONLDKeyword.language] ?? .null {
            language = l
        }

        let lexical: String
        switch value {
        case .string(let s):
            lexical = s
        case .bool(let b):
            lexical = b ? "true" : "false"
            if datatype == nil { datatype = Self.xsdBoolean }
        case .int(let i):
            lexical = String(i)
            if datatype == nil { datatype = Self.xsdInteger }
        case .double(let d):
            lexical = formatDouble(d)
            if datatype == nil { datatype = Self.xsdDouble }
        default:
            lexical = ""
        }

        if let language {
            return NodeIdentifier.literal(value: lexical, language: language)
        }
        if let datatype, datatype != Self.xsdString {
            return NodeIdentifier.literal(value: lexical, datatype: datatype)
        }
        return NodeIdentifier.literal(value: lexical)
    }

    private func formatDouble(_ d: Double) -> String {
        // Canonical xsd:double form: mantissa with a decimal point + E + integer.
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "INF" : "-INF" }
        if d == 0 { return "0.0E0" }
        let absVal = abs(d)
        let exponent = Int(floor(log10(absVal)))
        let mantissa = d / pow(10.0, Double(exponent))
        let mantissaStr = String(format: "%.15g", mantissa)
        let dotted = mantissaStr.contains(".") ? mantissaStr : mantissaStr + ".0"
        return "\(dotted)E\(exponent)"
    }

    private mutating func resolveSubjectOrObject(id: String) -> NodeIdentifier {
        if id.hasPrefix("_:") {
            let label = String(id.dropFirst(2))
            if let existing = blankMap[id] { return existing }
            let node = context.blankNode(forLabel: label)
            blankMap[id] = node
            return node
        }
        return .iri(id)
    }

    private mutating func freshBlankNode() -> NodeIdentifier {
        nextBlank += 1
        let label = "jsonld_list_\(nextBlank)"
        let node = context.blankNode(forLabel: label)
        return node
    }
}
