# swift-knowledge-graph

A pure-Swift, W3C-conformant Knowledge Graph library with streaming parsers for
the major RDF serialization formats.

- Strict Swift 6.3 concurrency (`Sendable` throughout)
- Streaming, allocation-conscious parsers (`parseChunk` / `finish`)
- No third-party dependencies

## Modules

| Module | Purpose |
|---|---|
| `KnowledgeGraph` | Core graph model: `Node`, `Edge`, `Attribute`, `NamedGraph`, `KnowledgeGraphBuilder` |
| `KnowledgeGraphParsers` | Streaming parsers for Turtle, TriG, N-Quads, RDF/XML, JSON-LD 1.1 |

Presentation metadata such as grouping, ordering, shape, style, and layout
intent is kept out of the RDF semantic graph. The planned `GraphPresentation` IR is documented in
[`Specs/GraphPresentation.md`](Specs/GraphPresentation.md).

## Supported formats

| Format | Media type | Spec |
|---|---|---|
| Turtle | `text/turtle` | [W3C RDF 1.1 Turtle](https://www.w3.org/TR/turtle/) |
| TriG | `application/trig` | [W3C RDF 1.1 TriG](https://www.w3.org/TR/trig/) |
| N-Quads | `application/n-quads` | [W3C RDF 1.1 N-Quads](https://www.w3.org/TR/n-quads/) |
| RDF/XML | `application/rdf+xml` | [W3C RDF 1.1 XML Syntax](https://www.w3.org/TR/rdf-syntax-grammar/) |
| JSON-LD 1.1 | `application/ld+json` | [W3C JSON-LD 1.1 to RDF](https://www.w3.org/TR/json-ld11-api/#deserialize-json-ld-to-rdf-algorithm) |

The JSON-LD 1.1 parser implements the toRdf algorithm and is exercised against
the W3C `toRdf` test suite. Features outside the supported subset (scoped
contexts, `@nest`, `@included`, `@direction`, term-driven container maps, etc.)
are rejected with `ParserError.unsupportedFeature` rather than emitting a
partial graph that disagrees with the spec.

## Installation

Add to `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-knowledge-graph.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "KnowledgeGraph", package: "swift-knowledge-graph"),
            .product(name: "KnowledgeGraphParsers", package: "swift-knowledge-graph"),
        ]
    ),
]
```

## Usage

### One-shot parse

```swift
import KnowledgeGraph
import KnowledgeGraphParsers

let text = """
@prefix ex: <http://example.org/> .
ex:alice ex:knows ex:bob .
ex:bob ex:name "Bob"@en .
"""

var parser = TurtleParser(context: ParsingContext(blankScopeID: "scope_1"))
let graph: KnowledgeGraph = try parser.parse(text)

for edge in graph.edges {
    print(edge.id.source.key, edge.id.predicate, edge.id.target.key)
}
```

### Streaming parse

All parsers conform to `KnowledgeGraphParser` and accept input incrementally:

```swift
var parser = TurtleParser(context: ParsingContext(blankScopeID: "scope_1"))
var builder = KnowledgeGraphBuilder()

for chunk in inputChunks {
    try parser.parseChunk(ArraySlice(chunk), into: &builder)
}
try parser.finish(into: &builder)

let graph = builder.build()
```

The parser holds enough lookahead state that byte-by-byte streaming produces
byte-for-byte identical results to one-shot parsing — see
`StreamingPartialParseTests` for the equivalence proofs.

### JSON-LD

```swift
var ctx = ParsingContext(blankScopeID: "scope_1")
ctx.setBaseIRI(IRI("http://example.org/"))
var parser = JSONLDParser(context: ctx)
var builder = KnowledgeGraphBuilder()
try parser.parseChunk(ArraySlice(Array(data)), into: &builder)
try parser.finish(into: &builder)
let graph = builder.build()
```

## Testing

```bash
xcodebuild test -scheme swift-knowledge-graph -destination 'platform=macOS'
```

The W3C JSON-LD 1.1 `toRdf` suite is bundled as a test resource and run as a
parameterised suite. Positive entries are validated by graph isomorphism;
negative entries must throw `ParserError`.

## License

MIT.
