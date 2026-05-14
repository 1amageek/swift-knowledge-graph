import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("TurtleParser")
struct TurtleParserTests {

    // MARK: - Helpers

    private func parse(_ source: String, base: String? = nil) throws -> KnowledgeGraph {
        var context = ParsingContext(blankScopeID: "test")
        if let base {
            context.setBaseIRI(IRI(base))
        }
        var parser = TurtleParser(context: context)
        return try parser.parse(source)
    }

    private func triples(in graph: KnowledgeGraph) -> [(String, String, String)] {
        graph.edges.map { edge in
            (edge.id.source.key, edge.id.predicate, edge.id.target.key)
        }
    }

    // MARK: - Smallest possible documents

    @Test("Empty document parses to empty graph")
    func emptyDocument() throws {
        let graph = try parse("")
        #expect(graph.edges.isEmpty)
        #expect(graph.nodes.isEmpty)
    }

    @Test("Whitespace-only document parses to empty graph")
    func whitespaceDocument() throws {
        let graph = try parse("   \n\t\r\n  ")
        #expect(graph.edges.isEmpty)
    }

    @Test("Comment-only document parses to empty graph")
    func commentDocument() throws {
        let graph = try parse("# this is a comment\n# and another\n")
        #expect(graph.edges.isEmpty)
    }

    // MARK: - Simple triple

    @Test("Single triple with three IRIs")
    func singleIRITriple() throws {
        let source = "<http://a.example/s> <http://a.example/p> <http://a.example/o> ."
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].0 == "http://a.example/s")
        #expect(edges[0].1 == "http://a.example/p")
        #expect(edges[0].2 == "http://a.example/o")
    }

    @Test("Three independent triples")
    func multipleTriples() throws {
        let source = """
        <http://a.example/s1> <http://a.example/p> <http://a.example/o1> .
        <http://a.example/s2> <http://a.example/p> <http://a.example/o2> .
        <http://a.example/s3> <http://a.example/p> <http://a.example/o3> .
        """
        let graph = try parse(source)
        #expect(graph.edges.count == 3)
    }

    // MARK: - Prefix / base

    @Test("@prefix + prefixed name")
    func prefixDirectiveAndUse() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].0 == "http://example.org/s")
        #expect(edges[0].1 == "http://example.org/p")
        #expect(edges[0].2 == "http://example.org/o")
    }

    @Test("@base resolves relative IRIs")
    func baseDirectiveAndRelativeIRI() throws {
        let source = """
        @base <http://example.org/> .
        <s> <p> <o> .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].0 == "http://example.org/s")
        #expect(edges[0].1 == "http://example.org/p")
        #expect(edges[0].2 == "http://example.org/o")
    }

    @Test("SPARQL-style PREFIX (no dot)")
    func sparqlPrefix() throws {
        let source = """
        PREFIX ex: <http://example.org/>
        ex:s ex:p ex:o .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].0 == "http://example.org/s")
    }

    @Test("SPARQL-style BASE (no dot)")
    func sparqlBase() throws {
        let source = """
        BASE <http://example.org/>
        <s> <p> <o> .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges[0].0 == "http://example.org/s")
    }

    @Test("Default empty prefix")
    func defaultEmptyPrefix() throws {
        let source = """
        @prefix : <http://example.org/> .
        :s :p :o .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges[0].0 == "http://example.org/s")
    }

    // MARK: - `a` shortcut

    @Test("`a` predicate is rdf:type")
    func aShortcut() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:Alice a ex:Person .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges[0].1 == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type")
        #expect(edges[0].2 == "http://example.org/Person")
    }

    // MARK: - Predicate-object lists

    @Test("Object list (comma)")
    func objectList() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o1 , ex:o2 , ex:o3 .
        """
        let graph = try parse(source)
        let edges = triples(in: graph).sorted { $0.2 < $1.2 }
        #expect(edges.count == 3)
        #expect(edges.map { $0.2 } == [
            "http://example.org/o1",
            "http://example.org/o2",
            "http://example.org/o3",
        ])
    }

    @Test("Predicate-object list (semicolon)")
    func predicateObjectList() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p1 ex:o1 ; ex:p2 ex:o2 .
        """
        let graph = try parse(source)
        let edges = triples(in: graph).sorted { $0.1 < $1.1 }
        #expect(edges.count == 2)
        #expect(edges[0].1 == "http://example.org/p1")
        #expect(edges[1].1 == "http://example.org/p2")
    }

    @Test("Trailing semicolon is allowed")
    func trailingSemicolon() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o ; .
        """
        let graph = try parse(source)
        #expect(graph.edges.count == 1)
    }

    @Test("Repeated semicolons are allowed")
    func repeatedSemicolons() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o ;; ex:q ex:r .
        """
        let graph = try parse(source)
        let edges = triples(in: graph).sorted { $0.1 < $1.1 }
        #expect(edges.count == 2)
        #expect(edges[0].1 == "http://example.org/p")
        #expect(edges[1].1 == "http://example.org/q")
    }

    // MARK: - Blank nodes

    @Test("Blank node label is shared by repeat use")
    func blankNodeLabel() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        _:b ex:p ex:o1 .
        _:b ex:p ex:o2 .
        """
        let graph = try parse(source)
        let blanks = Set(graph.edges.map { $0.id.source.key })
        #expect(blanks.count == 1)
    }

    @Test("Anonymous blank node [] yields a fresh blank")
    func anonymousBlankNode() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        [] ex:p ex:o .
        """
        let graph = try parse(source)
        let edges = graph.edges
        #expect(edges.count == 1)
        #expect(edges[0].id.source.kind == .blank)
    }

    @Test("Blank node property list as subject")
    func blankNodePropertyListSubject() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        [ ex:p ex:o ] ex:q ex:r .
        """
        let graph = try parse(source)
        // 1 triple from [ex:p ex:o] subject and 1 outer triple = 2
        #expect(graph.edges.count == 2)
        let blanks = Set(graph.edges.map { $0.id.source.key })
        #expect(blanks.count == 1) // both triples share the same blank subject
    }

    @Test("Blank node property list as object")
    func blankNodePropertyListObject() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p [ ex:q ex:r ] .
        """
        let graph = try parse(source)
        #expect(graph.edges.count == 2)
        // Outer edge target == inner edge source
        let outerEdge = graph.edges.first { $0.id.source.kind == .iri }!
        let innerEdge = graph.edges.first { $0.id.source.kind == .blank }!
        #expect(outerEdge.id.target == innerEdge.id.source)
    }

    // MARK: - Collections

    @Test("Empty collection is rdf:nil")
    func emptyCollection() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p () .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        #expect(edges.count == 1)
        #expect(edges[0].2 == "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
    }

    @Test("Three-element collection expands into rdf:first/rdf:rest chain")
    func threeElementCollection() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p (ex:a ex:b ex:c) .
        """
        let graph = try parse(source)
        let edges = triples(in: graph)
        // 1 outer triple + 3 rdf:first + 3 rdf:rest = 7
        #expect(edges.count == 7)
        let firsts = edges.filter { $0.1 == "http://www.w3.org/1999/02/22-rdf-syntax-ns#first" }
        let rests = edges.filter { $0.1 == "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest" }
        #expect(firsts.count == 3)
        #expect(rests.count == 3)
        #expect(firsts.map { $0.2 }.sorted() == [
            "http://example.org/a",
            "http://example.org/b",
            "http://example.org/c",
        ])
    }

    // MARK: - Literals

    @Test("Integer literal")
    func integerLiteral() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p 42 .
        """
        let graph = try parse(source)
        let edge = graph.edges[0]
        #expect(edge.id.target.kind == .literal)
        #expect(edge.id.target.key == "\"42\"^^http://www.w3.org/2001/XMLSchema#integer")
    }

    @Test("Decimal literal")
    func decimalLiteral() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p 3.14 .
        """
        let graph = try parse(source)
        let edge = graph.edges[0]
        #expect(edge.id.target.key == "\"3.14\"^^http://www.w3.org/2001/XMLSchema#decimal")
    }

    @Test("Double literal")
    func doubleLiteral() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p 6.022e23 .
        """
        let graph = try parse(source)
        let edge = graph.edges[0]
        #expect(edge.id.target.key == "\"6.022e23\"^^http://www.w3.org/2001/XMLSchema#double")
    }

    @Test("Boolean literal true / false")
    func booleanLiteral() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p true, false .
        """
        let graph = try parse(source)
        let keys = graph.edges.map { $0.id.target.key }.sorted()
        #expect(keys == [
            "\"false\"^^http://www.w3.org/2001/XMLSchema#boolean",
            "\"true\"^^http://www.w3.org/2001/XMLSchema#boolean",
        ])
    }

    @Test("Double-quoted string literal")
    func doubleQuotedString() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p "hello world" .
        """
        let graph = try parse(source)
        let edge = graph.edges[0]
        #expect(edge.id.target.key == "\"hello world\"")
    }

    @Test("Single-quoted string literal")
    func singleQuotedString() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p 'hello' .
        """
        let graph = try parse(source)
        #expect(graph.edges[0].id.target.key == "\"hello\"")
    }

    @Test("Language-tagged literal")
    func languageTaggedLiteral() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p "bonjour"@fr .
        """
        let graph = try parse(source)
        #expect(graph.edges[0].id.target.key == "\"bonjour\"@fr")
    }

    @Test("Typed literal")
    func typedLiteral() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
        ex:s ex:p "42"^^xsd:integer .
        """
        let graph = try parse(source)
        #expect(graph.edges[0].id.target.key == "\"42\"^^http://www.w3.org/2001/XMLSchema#integer")
    }

    @Test("Explicit ^^xsd:string is canonicalised to plain literal")
    func explicitStringDatatypeIsCanonical() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        @prefix xsd: <http://www.w3.org/2001/XMLSchema#> .
        ex:s ex:p "hello"^^xsd:string , "hello" .
        """
        let graph = try parse(source)
        let keys = Set(graph.edges.map { $0.id.target.key })
        // Both literals collapse onto the same canonical key.
        #expect(keys == ["\"hello\""])
    }

    @Test("Triple-quoted multi-line string")
    func tripleQuotedString() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p \"\"\"line 1
        line 2\"\"\" .
        """
        let graph = try parse(source)
        let key = graph.edges[0].id.target.key
        #expect(key.contains("line 1\nline 2"))
    }

    @Test("String escape sequences")
    func stringEscapes() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p "tab:\\there\\nnewline\\u00E9" .
        """
        let graph = try parse(source)
        let key = graph.edges[0].id.target.key
        #expect(key == "\"tab:\there\nnewlineé\"")
    }

    // MARK: - Streaming

    @Test("Chunked parse matches one-shot parse")
    func chunkedParseMatches() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o , ex:o2 ;
                 ex:q "literal"@en , 42, 3.14, true ;
                 ex:list (ex:a ex:b ex:c) ;
                 ex:bnp [ ex:inner ex:value ] .
        ex:s2 a ex:Person .
        """
        let oneShot = try parse(source)

        var chunkedParser = TurtleParser(context: ParsingContext(blankScopeID: "test"))
        var chunkedBuilder = KnowledgeGraphBuilder()
        let bytes = Array(source.utf8)
        var index = 0
        while index < bytes.count {
            let end = min(index + 7, bytes.count)
            try chunkedParser.parseChunk(bytes[index..<end], into: &chunkedBuilder)
            index = end
        }
        try chunkedParser.finish(into: &chunkedBuilder)
        let chunked = chunkedBuilder.build()

        let oneShotKeys = oneShot.edges.map { "\($0.id.source.key)|\($0.id.predicate)|\($0.id.target.key)" }.sorted()
        let chunkedKeys = chunked.edges.map { "\($0.id.source.key)|\($0.id.predicate)|\($0.id.target.key)" }.sorted()
        #expect(chunkedKeys == oneShotKeys)
    }

    @Test("Single-byte chunked parse")
    func singleByteChunked() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o .
        """
        var parser = TurtleParser(context: ParsingContext(blankScopeID: "test"))
        var builder = KnowledgeGraphBuilder()
        for byte in source.utf8 {
            try parser.parseChunk(ArraySlice([byte]), into: &builder)
        }
        try parser.finish(into: &builder)
        let graph = builder.build()
        #expect(graph.edges.count == 1)
    }

    // MARK: - Error cases

    @Test("Unterminated literal raises ParserError.unterminatedLiteral")
    func unterminatedLiteralThrows() {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p "open
        """
        #expect(throws: ParserError.self) {
            _ = try parse(source)
        }
    }

    @Test("Undefined prefix throws .undefinedPrefix")
    func undefinedPrefixThrows() {
        let source = "ex:s ex:p ex:o ."
        #expect(throws: ParserError.self) {
            _ = try parse(source)
        }
    }

    @Test("Missing trailing dot is reported")
    func missingDotThrows() {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:o
        """
        #expect(throws: ParserError.self) {
            _ = try parse(source)
        }
    }

    @Test("Relative IRI without base raises noBaseIRI")
    func relativeIRIWithoutBaseThrows() {
        let source = "<s> <p> <o> ."
        #expect(throws: ParserError.self) {
            _ = try parse(source)
        }
    }

    // MARK: - PN_LOCAL features

    @Test("PN_LOCAL allows ':', digit, and percent encoding")
    func pnLocalSpecialCharacters() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:0a:b%20c .
        """
        let graph = try parse(source)
        // The local part is "0a:b%20c" — appended directly to the namespace.
        #expect(graph.edges[0].id.target.key == "http://example.org/0a:b%20c")
    }

    @Test("PN_LOCAL_ESC decodes punctuation escapes")
    func pnLocalEscape() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        ex:s ex:p ex:foo\\.bar .
        """
        let graph = try parse(source)
        #expect(graph.edges[0].id.target.key == "http://example.org/foo.bar")
    }

    // MARK: - Warm-restart

    @Test("Same blankScopeID produces identical blank-node identifiers")
    func warmRestartIdenticalBlanks() throws {
        let source = """
        @prefix ex: <http://example.org/> .
        _:b ex:p ex:o .
        """
        var first = TurtleParser(context: ParsingContext(blankScopeID: "warm"))
        var second = TurtleParser(context: ParsingContext(blankScopeID: "warm"))
        let g1 = try first.parse(source)
        let g2 = try second.parse(source)
        #expect(g1.edges.map { $0.id.source.key } == g2.edges.map { $0.id.source.key })
    }
}
