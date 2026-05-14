import Foundation

/// JSON-LD 1.1 Node-Map Generation (§5.9).
///
/// The expanded form is still tree-shaped: a single node may appear in
/// multiple positions, properties may need to be merged. Node-map
/// generation flattens the tree into a map keyed by `@id`, with one entry
/// per node. Named graphs become top-level entries; the default graph is
/// always present under the key `"@default"`.
///
/// We model the map as `[graphID: [subjectID: NodeMapEntry]]`. Anonymous
/// nodes are assigned blank-node identifiers from a shared counter so two
/// references to the same nested node converge on one entry.
struct JSONLDNodeMap {

    /// One entry per `@id`. Property values are kept as expanded JSON
    /// arrays so toRdf can walk them in a uniform way.
    struct Entry {
        var id: String
        var types: [String]
        var properties: [String: [JSONValue]]
        var reverseProperties: [String: [JSONValue]]
    }

    /// `graphID -> subjectID -> entry`. `graphID == "@default"` is the
    /// default graph.
    var graphs: [String: [String: Entry]]

    init() {
        self.graphs = ["@default": [:]]
    }
}

struct JSONLDNodeMapGeneration {

    var position: SourcePosition
    var nextBlank: Int = 0

    init(position: SourcePosition = .start) {
        self.position = position
    }

    mutating func generate(from expanded: [JSONValue]) throws -> JSONLDNodeMap {
        var map = JSONLDNodeMap()
        for element in expanded {
            try generate(
                element: element,
                graphName: "@default",
                activeSubject: nil,
                activeProperty: nil,
                into: &map
            )
        }
        return map
    }

    private mutating func generate(
        element: JSONValue,
        graphName: String,
        activeSubject: String?,
        activeProperty: String?,
        into map: inout JSONLDNodeMap
    ) throws {
        switch element {
        case .array(let arr):
            for entry in arr {
                try generate(
                    element: entry,
                    graphName: graphName,
                    activeSubject: activeSubject,
                    activeProperty: activeProperty,
                    into: &map
                )
            }
            return
        case .object(let dict):
            try processObject(
                dict: dict,
                graphName: graphName,
                activeSubject: activeSubject,
                activeProperty: activeProperty,
                into: &map
            )
        default:
            return
        }
    }

    private mutating func processObject(
        dict: [String: JSONValue],
        graphName: String,
        activeSubject: String?,
        activeProperty: String?,
        into map: inout JSONLDNodeMap
    ) throws {
        // Value object: append into parent property bucket.
        if dict[JSONLDKeyword.value] != nil {
            try appendToParent(.object(dict), graphName: graphName,
                               activeSubject: activeSubject,
                               activeProperty: activeProperty,
                               into: &map)
            return
        }

        // List object: flatten nested node references but keep the @list
        // intact as a single property value. The toRdf step expands it into
        // an rdf:first/rdf:rest chain.
        if let listValue = dict[JSONLDKeyword.list] {
            if case .array(let items) = listValue {
                for item in items {
                    // Process nested node objects so they appear in the map,
                    // but pass `activeSubject:nil` so the recursion does not
                    // attach them back to the parent property.
                    if case .object(let nested) = item, nested[JSONLDKeyword.value] == nil,
                       nested[JSONLDKeyword.list] == nil {
                        try generate(
                            element: item,
                            graphName: graphName,
                            activeSubject: nil,
                            activeProperty: nil,
                            into: &map
                        )
                    }
                }
            }
            try appendToParent(
                .object(dict),
                graphName: graphName,
                activeSubject: activeSubject,
                activeProperty: activeProperty,
                into: &map
            )
            return
        }

        // Node object: assign or read its identifier.
        let id: String
        if case .string(let explicit) = dict[JSONLDKeyword.id] ?? .null {
            id = explicit
        } else {
            id = freshBlank()
        }

        // Ensure entry exists in this graph.
        if map.graphs[graphName] == nil { map.graphs[graphName] = [:] }
        if map.graphs[graphName]![id] == nil {
            map.graphs[graphName]![id] = JSONLDNodeMap.Entry(
                id: id, types: [], properties: [:], reverseProperties: [:]
            )
        }

        // If we have an active property in a parent context, link parent → this node.
        if let activeSubject, let activeProperty {
            let reference: JSONValue = .object([JSONLDKeyword.id: .string(id)])
            try appendProperty(
                on: activeSubject, graph: graphName,
                property: activeProperty, value: reference,
                into: &map
            )
        }

        // Process @type.
        if let typeValue = dict[JSONLDKeyword.type] {
            let types: [JSONValue]
            switch typeValue {
            case .array(let a): types = a
            default: types = [typeValue]
            }
            var existing = map.graphs[graphName]![id]!.types
            for t in types {
                if case .string(let s) = t, !existing.contains(s) {
                    existing.append(s)
                }
            }
            map.graphs[graphName]![id]!.types = existing
        }

        // Process @graph: recurse into named graph.
        if let graphValue = dict[JSONLDKeyword.graph] {
            let nestedGraph = id
            if map.graphs[nestedGraph] == nil { map.graphs[nestedGraph] = [:] }
            try generate(
                element: graphValue,
                graphName: nestedGraph,
                activeSubject: nil,
                activeProperty: nil,
                into: &map
            )
        }

        // Process @reverse.
        if let reverseValue = dict[JSONLDKeyword.reverse],
           case .object(let revDict) = reverseValue {
            for (rprop, rval) in revDict {
                let values: [JSONValue]
                switch rval {
                case .array(let a): values = a
                default: values = [rval]
                }
                for v in values {
                    let subjectID: String
                    if case .object(let nested) = v {
                        if case .string(let explicit) = nested[JSONLDKeyword.id] ?? .null {
                            subjectID = explicit
                        } else {
                            subjectID = freshBlank()
                        }
                        if map.graphs[graphName]![subjectID] == nil {
                            map.graphs[graphName]![subjectID] = JSONLDNodeMap.Entry(
                                id: subjectID, types: [], properties: [:], reverseProperties: [:]
                            )
                        }
                        try generate(
                            element: .object(nested),
                            graphName: graphName,
                            activeSubject: nil,
                            activeProperty: nil,
                            into: &map
                        )
                    } else {
                        continue
                    }
                    try appendProperty(
                        on: subjectID, graph: graphName,
                        property: rprop,
                        value: .object([JSONLDKeyword.id: .string(id)]),
                        into: &map
                    )
                }
            }
        }

        // Process regular properties.
        let reservedKeys: Set<String> = [
            JSONLDKeyword.id, JSONLDKeyword.type,
            JSONLDKeyword.graph, JSONLDKeyword.reverse,
            JSONLDKeyword.index
        ]
        for key in dict.keys.sorted() where !reservedKeys.contains(key) {
            guard let val = dict[key] else { continue }
            try generate(
                element: val,
                graphName: graphName,
                activeSubject: id,
                activeProperty: key,
                into: &map
            )
        }
    }

    // MARK: - Helpers

    private mutating func appendToParent(
        _ value: JSONValue,
        graphName: String,
        activeSubject: String?,
        activeProperty: String?,
        into map: inout JSONLDNodeMap
    ) throws {
        guard let activeSubject, let activeProperty else { return }
        try appendProperty(
            on: activeSubject, graph: graphName,
            property: activeProperty, value: value,
            into: &map
        )
    }

    private func appendProperty(
        on subject: String,
        graph: String,
        property: String,
        value: JSONValue,
        into map: inout JSONLDNodeMap
    ) throws {
        guard map.graphs[graph]?[subject] != nil else { return }
        var entry = map.graphs[graph]![subject]!
        var bucket: [JSONValue] = []
        if let existing = entry.properties[property] {
            bucket = existing
        }
        // §5.9.4 only de-duplicates node references (`{"@id": "..."}`):
        // value objects and list objects must be appended verbatim, because
        // two literals with identical lexical form and datatype are still
        // two separate triples to emit. Restricting the contains-check to
        // @id-only objects keeps multi-valued literal properties intact.
        let isNodeReference: Bool = {
            guard case .object(let obj) = value else { return false }
            return obj.count == 1 && obj[JSONLDKeyword.id] != nil
        }()
        if isNodeReference {
            if !bucket.contains(value) {
                bucket.append(value)
            }
        } else {
            bucket.append(value)
        }
        entry.properties[property] = bucket
        map.graphs[graph]![subject] = entry
    }

    private mutating func freshBlank() -> String {
        nextBlank += 1
        return "_:b\(nextBlank)"
    }
}
