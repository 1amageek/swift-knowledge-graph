import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("Streaming partial-parse equivalence (condition 7)")
struct StreamingPartialParseTests {

    // MARK: - Helpers

    private func parseTurtleOneShot(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = TurtleParser(context: context)
        return try parser.parse(text)
    }

    private func parseTurtleByteByByte(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = TurtleParser(context: context)
        var builder = KnowledgeGraphBuilder()
        let bytes = Array(text.utf8)
        for byte in bytes {
            try parser.parseChunk(ArraySlice([byte]), into: &builder)
        }
        try parser.finish(into: &builder)
        return builder.build()
    }

    private func parseTriGByteByByte(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = TriGParser(context: context)
        var builder = KnowledgeGraphBuilder()
        for byte in Array(text.utf8) {
            try parser.parseChunk(ArraySlice([byte]), into: &builder)
        }
        try parser.finish(into: &builder)
        return builder.build()
    }

    private func parseTriGOneShot(_ text: String, scope: String) throws -> KnowledgeGraph {
        let context = ParsingContext(blankScopeID: scope)
        var parser = TriGParser(context: context)
        return try parser.parse(text)
    }

    private func edgeKeys(_ g: KnowledgeGraph) -> Set<String> {
        Set(g.edges.map { "\($0.id.source.key)|\($0.id.predicate)|\($0.id.target.key)|\($0.id.namedGraph ?? "")" })
    }

    // MARK: - Turtle

    @Test("Turtle: 1-byte chunks match one-shot parse for simple triples")
    func turtleSimpleTriple() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p "value" .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_a")
        let b = try parseTurtleByteByByte(text, scope: "stream_a")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks match for blank nodes")
    func turtleBlankNodes() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        _:a ex:knows _:b .
        _:b ex:name "Bob" .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_blank")
        let b = try parseTurtleByteByByte(text, scope: "stream_blank")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks match for typed literals")
    func turtleTypedLiteral() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
        ex:s ex:age "42"^^xsd:integer .
        ex:s ex:name "Alice"@en .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_typed")
        let b = try parseTurtleByteByByte(text, scope: "stream_typed")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks match for collections")
    func turtleCollection() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:items ( "a" "b" "c" ) .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_coll")
        let b = try parseTurtleByteByByte(text, scope: "stream_coll")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks match for multi-line triples with comments")
    func turtleComments() throws {
        let text = """
        # leading comment
        @prefix ex: <http://example.org/> .
        # mid comment
        ex:s
            ex:p1 "one" ;  # inline comment
            ex:p2 "two" .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_comments")
        let b = try parseTurtleByteByByte(text, scope: "stream_comments")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    // MARK: - TriG

    @Test("TriG: 1-byte chunks match for named graphs")
    func trigNamedGraph() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        ex:g1 {
            ex:s ex:p "v" .
        }
        ex:g2 {
            ex:x ex:y "z" .
        }
        """
        let a = try parseTriGOneShot(text, scope: "stream_trig")
        let b = try parseTriGByteByByte(text, scope: "stream_trig")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    // MARK: - Fragile-path coverage
    //
    // The tokenizer holds the most subtle streaming state: features that
    // need 2- or 3-byte lookahead (`"""` triple-quote, `A` Unicode
    // escapes, `123.45e10` numeric exponents, BCP 47 langtag hyphens, the
    // `[ ... ]` anonymous blank-node form) can silently emit a wrong token
    // when the chunk boundary falls between the lookahead bytes. Each
    // fixture below targets exactly one of those paths.

    @Test("Turtle: 1-byte chunks preserve \\u Unicode escapes inside strings")
    func turtleUnicodeEscapeInString() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:label "caf\\u00e9" .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_uesc_str")
        let b = try parseTurtleByteByByte(text, scope: "stream_uesc_str")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks preserve \\U Unicode escapes inside IRIs")
    func turtleUnicodeEscapeInIRI() throws {
        // \U escape inside an IRI exercises a different code path from the
        // string-literal one — it must read 8 hex digits across whatever
        // chunk boundary lands inside the escape.
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p <http://example.org/caf\\u00e9> .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_uesc_iri")
        let b = try parseTurtleByteByByte(text, scope: "stream_uesc_iri")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks preserve triple-quoted strings")
    func turtleTripleQuoted() throws {
        // Triple-quoted strings need the tokenizer to peek 2 bytes past the
        // opening `"` to decide between empty-string `""` and triple-quote
        // `"""`. A buffer split at offset+1 or offset+2 must defer the
        // decision rather than emit a spurious empty string.
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p \"\"\"line1
        line2
        line3\"\"\" .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_tq")
        let b = try parseTurtleByteByByte(text, scope: "stream_tq")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks preserve anonymous blank-node `[ ... ]`")
    func turtleAnonymousBlank() throws {
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:has [ ex:p "v" ; ex:q "w" ] .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_anon")
        let b = try parseTurtleByteByByte(text, scope: "stream_anon")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks preserve numeric literals with exponents")
    func turtleNumericExponent() throws {
        // `1.0e10` and `.5e-3` stress the numeric tokenizer's exponent
        // branch — the `e` / `E` lookahead and optional sign must survive
        // splits between the mantissa, the exponent marker, the sign, and
        // the exponent digits.
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:f 1.0e10 .
        ex:s ex:g .5e-3 .
        ex:s ex:h -2.5E+7 .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_exp")
        let b = try parseTurtleByteByByte(text, scope: "stream_exp")
        #expect(edgeKeys(a) == edgeKeys(b))
    }

    @Test("Turtle: 1-byte chunks preserve multi-subtag language tags")
    func turtleLangtagHyphen() throws {
        // `@en-GB-oxendict` — the langtag scanner walks across hyphens to
        // pick up extension subtags. A chunk split exactly on a hyphen
        // must not terminate the tag early.
        let text = """
        @prefix ex: <http://example.org/> .
        ex:s ex:name "elevator"@en-GB-oxendict .
        ex:s ex:name "ascensore"@it-IT .
        """
        let a = try parseTurtleOneShot(text, scope: "stream_langtag")
        let b = try parseTurtleByteByByte(text, scope: "stream_langtag")
        #expect(edgeKeys(a) == edgeKeys(b))
    }
}
