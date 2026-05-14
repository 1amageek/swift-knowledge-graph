import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

@Suite("Typed errors carry line:column:byteOffset (condition 9)")
struct ErrorReportingTests {

    // MARK: - Helpers

    private func turtleError(_ text: String) -> ParserError? {
        var parser = TurtleParser()
        do {
            _ = try parser.parse(text)
            return nil
        } catch let error as ParserError {
            return error
        } catch {
            return nil
        }
    }

    private func trigError(_ text: String) -> ParserError? {
        var parser = TriGParser()
        do {
            _ = try parser.parse(text)
            return nil
        } catch let error as ParserError {
            return error
        } catch {
            return nil
        }
    }

    private func rdfxmlError(_ text: String) -> ParserError? {
        var parser = RDFXMLParser()
        var builder = KnowledgeGraphBuilder()
        do {
            try parser.parseAll(text, into: &builder)
            return nil
        } catch let error as ParserError {
            return error
        } catch {
            return nil
        }
    }

    private func jsonldError(_ text: String) -> ParserError? {
        var parser = JSONLDParser()
        var builder = KnowledgeGraphBuilder()
        do {
            try parser.parseAll(text, into: &builder)
            return nil
        } catch let error as ParserError {
            return error
        } catch {
            return nil
        }
    }

    // MARK: - Turtle

    @Test("Turtle: unterminated IRI carries source position")
    func turtleUnterminatedIRI() {
        let err = turtleError("@prefix ex: <http://example.org/")
        #expect(err != nil)
        if let err {
            #expect(err.position.line >= 1)
            #expect(err.position.column >= 1)
            #expect(err.position.byteOffset >= 0)
        }
    }

    @Test("Turtle: missing dot terminator carries position")
    func turtleMissingDot() {
        let text = "@prefix ex: <http://example.org/> .\nex:s ex:p \"v\""
        let err = turtleError(text)
        #expect(err != nil)
        if let err {
            #expect(err.position.line >= 2)
        }
    }

    @Test("Turtle: undefined prefix carries position")
    func turtleUndefinedPrefix() {
        let text = "ex:s ex:p \"v\" ."
        let err = turtleError(text)
        #expect(err != nil)
        if case .undefinedPrefix(let prefix, let pos)? = err {
            #expect(prefix == "ex")
            #expect(pos.line >= 1)
        } else {
            Issue.record("expected .undefinedPrefix, got \(String(describing: err))")
        }
    }

    // MARK: - TriG

    @Test("TriG: unclosed graph block carries position")
    func trigUnclosedGraph() {
        let text = "@prefix ex: <http://example.org/> .\nex:g1 { ex:s ex:p \"v\" ."
        let err = trigError(text)
        #expect(err != nil)
        if let err {
            #expect(err.position.line >= 1)
            #expect(err.position.byteOffset >= 0)
        }
    }

    // MARK: - RDF/XML

    @Test("RDF/XML: malformed XML throws .xmlSyntax with position")
    func rdfxmlMalformed() {
        let err = rdfxmlError("<rdf:RDF xmlns:rdf='x'")
        #expect(err != nil)
        if case .xmlSyntax(_, let pos)? = err {
            #expect(pos.line >= 1)
            #expect(pos.column >= 1)
        } else {
            Issue.record("expected .xmlSyntax, got \(String(describing: err))")
        }
    }

    @Test("RDF/XML: empty input throws .unexpectedEndOfInput with .start position")
    func rdfxmlEmpty() {
        let err = rdfxmlError("")
        if case .unexpectedEndOfInput(let pos, _)? = err {
            #expect(pos == .start)
        } else {
            Issue.record("expected .unexpectedEndOfInput, got \(String(describing: err))")
        }
    }

    // MARK: - JSON-LD

    @Test("JSON-LD: malformed JSON throws .jsonSyntax with position")
    func jsonldMalformed() {
        let err = jsonldError(#"{"@id":}"#)
        if case .jsonSyntax(_, let pos)? = err {
            #expect(pos.line >= 1)
            #expect(pos.column >= 1)
            #expect(pos.byteOffset >= 0)
        } else {
            Issue.record("expected .jsonSyntax, got \(String(describing: err))")
        }
    }

    @Test("JSON-LD: unterminated string throws .unexpectedEndOfInput with position")
    func jsonldUnterminated() {
        let err = jsonldError(#"{"@id": "incomplete"#)
        if case .unexpectedEndOfInput(let pos, _)? = err {
            #expect(pos.byteOffset > 0)
        } else {
            Issue.record("expected .unexpectedEndOfInput, got \(String(describing: err))")
        }
    }

    @Test("JSON-LD: remote @context throws .unsupportedFeature")
    func jsonldRemoteContext() {
        let err = jsonldError(#"{"@context":"http://example.org/ctx","@id":"http://x/"}"#)
        if case .unsupportedFeature(let name, _)? = err {
            #expect(name == "remote @context")
        } else {
            Issue.record("expected .unsupportedFeature, got \(String(describing: err))")
        }
    }

    // MARK: - Position consistency

    @Test("ParserError.position is reachable for every variant")
    func positionForEveryVariant() {
        let cases: [ParserError] = [
            .unexpectedEndOfInput(at: SourcePosition(line: 1, column: 1, byteOffset: 0), expected: "x"),
            .unexpectedCharacter("?", at: SourcePosition(line: 1, column: 1, byteOffset: 0), expected: "x"),
            .invalidEscape(sequence: "\\?", at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .unterminatedLiteral(at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .invalidLiteral(value: "x", at: SourcePosition(line: 1, column: 1, byteOffset: 0), reason: "r"),
            .invalidIRI(value: "x", at: SourcePosition(line: 1, column: 1, byteOffset: 0), reason: "r"),
            .noBaseIRI(at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .undefinedPrefix(prefix: "p", at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .grammar(production: "x", at: SourcePosition(line: 1, column: 1, byteOffset: 0), detail: "d"),
            .xmlSyntax(detail: "d", at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .jsonSyntax(detail: "d", at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .unsupportedFeature(name: "x", at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
            .blankScopeLeak(label: "x", at: SourcePosition(line: 1, column: 1, byteOffset: 0)),
        ]
        for err in cases {
            let p = err.position
            #expect(p.line == 1 && p.column == 1 && p.byteOffset == 0)
        }
    }
}
