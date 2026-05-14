import Foundation

/// 1-based line / column pair plus 0-based byte offset within the original
/// payload. Every `ParserError` carries one of these so downstream tooling
/// can surface precise diagnostics without re-tokenising the input.
public struct SourcePosition: Hashable, Sendable, Codable, CustomStringConvertible {
    public let line: Int
    public let column: Int
    public let byteOffset: Int

    public init(line: Int, column: Int, byteOffset: Int) {
        self.line = line
        self.column = column
        self.byteOffset = byteOffset
    }

    /// Sentinel position used when an error is detected before any input has
    /// been consumed (for example, before the first chunk has arrived).
    public static let start = SourcePosition(line: 1, column: 1, byteOffset: 0)

    public var description: String {
        "line \(line), column \(column) (byte offset \(byteOffset))"
    }
}
