import Foundation
import Testing
import KnowledgeGraph
@testable import KnowledgeGraphParsers

/// Performance baseline (condition 12).
///
/// Target: 100k triples must parse in <1s under release-mode (M-series). In
/// debug builds the absolute number is higher; we record the duration so a
/// regression in either build mode shows up. The threshold check applies
/// only under release optimisation — see `releaseThreshold`.
@Suite("Performance benchmarks (condition 12)")
struct PerformanceBenchmarks {

    /// `swift test -c release` defines NDEBUG-equivalent: we detect via
    /// `_isDebugAssertConfiguration()` so the assertion only fires when the
    /// build actually has optimisations enabled.
    private var isReleaseBuild: Bool {
        !_isDebugAssertConfiguration()
    }

    private static func makeTurtle(triples: Int) -> String {
        var lines: [String] = ["@prefix ex: <http://example.org/> ."]
        lines.reserveCapacity(triples + 1)
        for i in 0..<triples {
            lines.append("ex:s\(i) ex:p\(i % 100) \"v\(i)\" .")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @Test("Turtle: 100k triples parse in <1s (release build only)")
    func turtle100k() throws {
        let triples = 100_000
        let text = Self.makeTurtle(triples: triples)
        let context = ParsingContext(blankScopeID: "perf")
        var parser = TurtleParser(context: context)
        let start = Date()
        let graph = try parser.parse(text)
        let elapsed = Date().timeIntervalSince(start)
        // Sanity: count must match.
        #expect(graph.edges.count == triples)
        // Record duration regardless of build mode.
        let mode = isReleaseBuild ? "RELEASE" : "DEBUG"
        print("[perf] Turtle 100k triples [\(mode)] elapsed = \(String(format: "%.3f", elapsed)) s")
        if isReleaseBuild {
            #expect(elapsed < 1.0, "Turtle 100k > 1s in release: \(elapsed)s")
        }
    }

    @Test("Turtle: 100k triples streaming via 4 KiB chunks completes in <2s (release)")
    func turtle100kStreaming() throws {
        let triples = 100_000
        let text = Self.makeTurtle(triples: triples)
        let bytes = Array(text.utf8)
        let context = ParsingContext(blankScopeID: "perf-stream")
        var parser = TurtleParser(context: context)
        var builder = KnowledgeGraphBuilder()
        let chunkSize = 4096
        let start = Date()
        var i = 0
        while i < bytes.count {
            let end = min(i + chunkSize, bytes.count)
            try parser.parseChunk(ArraySlice(bytes[i..<end]), into: &builder)
            i = end
        }
        try parser.finish(into: &builder)
        let elapsed = Date().timeIntervalSince(start)
        let graph = builder.build()
        #expect(graph.edges.count == triples)
        let mode = isReleaseBuild ? "RELEASE" : "DEBUG"
        print("[perf] Turtle 100k triples (4KiB chunks) [\(mode)] elapsed = \(String(format: "%.3f", elapsed)) s")
        if isReleaseBuild {
            #expect(elapsed < 2.0, "Turtle 100k streaming > 2s in release: \(elapsed)s")
        }
    }
}
