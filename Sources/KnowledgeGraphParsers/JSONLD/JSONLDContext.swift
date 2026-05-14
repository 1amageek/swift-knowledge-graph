import Foundation

/// In-memory representation of a processed JSON-LD context.
///
/// JSON-LD §3.1 calls this an "active context". The expansion algorithm
/// threads one of these through every recursive call, consulting `terms`
/// for IRI / type / language information and falling back to `vocab` /
/// `defaultLanguage` / `defaultDirection` for terms that do not have an
/// explicit definition.
struct JSONLDContext: Sendable, Hashable {

    /// Effective `@base` IRI. Starts as the document's base IRI and may be
    /// overridden by `@base` entries inside the document's `@context`.
    var baseIRI: String?

    /// `@vocab` setting — prepended to a term that is otherwise undefined.
    var vocab: String?

    /// Default language for plain-string values, if any.
    var defaultLanguage: String?

    /// Default direction for plain-string values, if any.
    var defaultDirection: String?

    /// Term map.
    var terms: [String: JSONLDTermDefinition]

    /// 1.0 or 1.1. Many algorithm steps gate on this.
    var version: Double

    /// When `false`, this context does not propagate into nested node
    /// objects (set by `@propagate: false`). Defaults to `true`.
    var propagate: Bool

    /// When the previous context should be restored after the current one
    /// expires (used by `@propagate` semantics).
    var previousContext: PreviousContextBox?

    init(
        baseIRI: String? = nil,
        vocab: String? = nil,
        defaultLanguage: String? = nil,
        defaultDirection: String? = nil,
        terms: [String: JSONLDTermDefinition] = [:],
        version: Double = 1.1,
        propagate: Bool = true,
        previousContext: PreviousContextBox? = nil
    ) {
        self.baseIRI = baseIRI
        self.vocab = vocab
        self.defaultLanguage = defaultLanguage
        self.defaultDirection = defaultDirection
        self.terms = terms
        self.version = version
        self.propagate = propagate
        self.previousContext = previousContext
    }

    /// Boxed `JSONLDContext` to break the recursive struct definition.
    final class PreviousContextBox: @unchecked Sendable, Hashable {
        let context: JSONLDContext
        init(_ context: JSONLDContext) { self.context = context }
        static func == (lhs: PreviousContextBox, rhs: PreviousContextBox) -> Bool {
            lhs.context == rhs.context
        }
        func hash(into hasher: inout Hasher) { hasher.combine(context) }
    }
}
