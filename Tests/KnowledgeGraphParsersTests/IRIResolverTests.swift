import Testing
@testable import KnowledgeGraphParsers

/// Exhaustive coverage of RFC 3986 §5.4 reference-resolution examples.
///
/// The RFC publishes two example tables — §5.4.1 "Normal Examples" and
/// §5.4.2 "Abnormal Examples". Both are reproduced here verbatim. A
/// resolver that passes both tables is, for practical purposes, RFC 3986
/// compliant on this code path.
@Suite("IRIResolver — RFC 3986 §5.4")
struct IRIResolverTests {

    static let base = "http://a/b/c/d;p?q"

    // MARK: - §5.4.1 Normal examples

    @Test("§5.4.1 normal examples", arguments: normalExamples)
    func normalResolution(reference: String, expected: String) {
        let actual = IRIResolver.resolve(reference: reference, against: Self.base)
        #expect(actual == expected, "normal example: \"\(reference)\" → \"\(actual)\" (expected \"\(expected)\")")
    }

    static let normalExamples: [(reference: String, expected: String)] = [
        ("g:h",       "g:h"),
        ("g",         "http://a/b/c/g"),
        ("./g",       "http://a/b/c/g"),
        ("g/",        "http://a/b/c/g/"),
        ("/g",        "http://a/g"),
        ("//g",       "http://g"),
        ("?y",        "http://a/b/c/d;p?y"),
        ("g?y",       "http://a/b/c/g?y"),
        ("#s",        "http://a/b/c/d;p?q#s"),
        ("g#s",       "http://a/b/c/g#s"),
        ("g?y#s",     "http://a/b/c/g?y#s"),
        (";x",        "http://a/b/c/;x"),
        ("g;x",       "http://a/b/c/g;x"),
        ("g;x?y#s",   "http://a/b/c/g;x?y#s"),
        ("",          "http://a/b/c/d;p?q"),
        (".",         "http://a/b/c/"),
        ("./",        "http://a/b/c/"),
        ("..",        "http://a/b/"),
        ("../",       "http://a/b/"),
        ("../g",      "http://a/b/g"),
        ("../..",     "http://a/"),
        ("../../",    "http://a/"),
        ("../../g",   "http://a/g"),
    ]

    // MARK: - §5.4.2 Abnormal examples

    @Test("§5.4.2 abnormal examples", arguments: abnormalExamples)
    func abnormalResolution(reference: String, expected: String) {
        let actual = IRIResolver.resolve(reference: reference, against: Self.base)
        #expect(actual == expected, "abnormal example: \"\(reference)\" → \"\(actual)\" (expected \"\(expected)\")")
    }

    static let abnormalExamples: [(reference: String, expected: String)] = [
        // Extra parent navigations beyond the root.
        ("../../../g",      "http://a/g"),
        ("../../../../g",   "http://a/g"),

        // Useless dot-segments removed even when the syntax is unusual.
        ("/./g",            "http://a/g"),
        ("/../g",           "http://a/g"),
        ("g.",              "http://a/b/c/g."),
        (".g",              "http://a/b/c/.g"),
        ("g..",             "http://a/b/c/g.."),
        ("..g",             "http://a/b/c/..g"),

        // Combinations.
        ("./../g",          "http://a/b/g"),
        ("./g/.",           "http://a/b/c/g/"),
        ("g/./h",           "http://a/b/c/g/h"),
        ("g/../h",          "http://a/b/c/h"),
        ("g;x=1/./y",       "http://a/b/c/g;x=1/y"),
        ("g;x=1/../y",      "http://a/b/c/y"),

        // Dot segments only have meaning in the path component.
        ("g?y/./x",         "http://a/b/c/g?y/./x"),
        ("g?y/../x",        "http://a/b/c/g?y/../x"),
        ("g#s/./x",         "http://a/b/c/g#s/./x"),
        ("g#s/../x",        "http://a/b/c/g#s/../x"),

        // Strict mode: "http:g" is an absolute reference, returned unchanged.
        ("http:g",          "http:g"),
    ]

    // MARK: - Component-level sanity checks

    @Test("removeDotSegments handles the RFC §5.2.4 demo trace")
    func removeDotSegmentsDemo() {
        // The RFC walks through "/a/b/c/./../../g" step by step in §5.2.4.
        // Final result should be "/a/g".
        #expect(IRIResolver.removeDotSegments("/a/b/c/./../../g") == "/a/g")
        // And "mid/content=5/../6" → "mid/6".
        #expect(IRIResolver.removeDotSegments("mid/content=5/../6") == "mid/6")
    }

    @Test("Absolute references ignore base")
    func absoluteReferenceIgnoresBase() {
        let resolved = IRIResolver.resolve(
            reference: "https://example.com/foo",
            against: "http://a/b/c/d"
        )
        #expect(resolved == "https://example.com/foo")
    }
}
