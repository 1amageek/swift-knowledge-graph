import Foundation

/// Reference resolution per RFC 3986 §5.
///
/// Given a base IRI and a (possibly relative) reference, produce the target
/// IRI. The implementation follows the abstract algorithm in §5.2.2 line by
/// line; the helper functions `mergePaths` and `removeDotSegments` follow
/// §5.2.3 and §5.2.4 respectively.
public enum IRIResolver {

    /// Resolve `reference` against `base`. The reference may be absolute, in
    /// which case it is returned unchanged after a single round-trip through
    /// `removeDotSegments` (per the spec, step 3 of §5.2.2). The base must
    /// itself be absolute — relative bases are rejected at the call site.
    public static func resolve(reference: String, against base: String) -> String {
        let r = IRIComponents.parse(reference)
        let b = IRIComponents.parse(base)
        var t = IRIComponents(scheme: nil, authority: nil, path: "", query: nil, fragment: nil)

        if r.scheme != nil {
            t.scheme = r.scheme
            t.authority = r.authority
            t.path = removeDotSegments(r.path)
            t.query = r.query
        } else {
            if r.authority != nil {
                t.authority = r.authority
                t.path = removeDotSegments(r.path)
                t.query = r.query
            } else {
                if r.path.isEmpty {
                    t.path = b.path
                    if r.query != nil {
                        t.query = r.query
                    } else {
                        t.query = b.query
                    }
                } else {
                    if r.path.hasPrefix("/") {
                        t.path = removeDotSegments(r.path)
                    } else {
                        t.path = removeDotSegments(mergePaths(base: b, referencePath: r.path))
                    }
                    t.query = r.query
                }
                t.authority = b.authority
            }
            t.scheme = b.scheme
        }
        t.fragment = r.fragment
        return t.recomposed()
    }

    /// `merge` per RFC 3986 §5.2.3.
    static func mergePaths(base: IRIComponents, referencePath: String) -> String {
        if base.authority != nil && base.path.isEmpty {
            return "/" + referencePath
        }
        if let lastSlash = base.path.lastIndex(of: "/") {
            let upToSlash = base.path[...lastSlash]
            return String(upToSlash) + referencePath
        }
        return referencePath
    }

    /// `remove_dot_segments` per RFC 3986 §5.2.4.
    ///
    /// The algorithm is described as character-level manipulation on two
    /// strings (input buffer, output buffer). We implement it literally —
    /// no shortcuts, no segment-level shortcuts — so behaviour matches the
    /// spec byte for byte even for pathological inputs like `"./../g"` or
    /// `"g;x=1/../y"`.
    static func removeDotSegments(_ path: String) -> String {
        var input = path
        var output = ""

        while !input.isEmpty {
            if input.hasPrefix("../") {
                input.removeFirst(3)
            } else if input.hasPrefix("./") {
                input.removeFirst(2)
            } else if input.hasPrefix("/./") {
                input = "/" + input.dropFirst(3)
            } else if input == "/." {
                input = "/"
            } else if input.hasPrefix("/../") {
                input = "/" + input.dropFirst(4)
                removeLastSegment(&output)
            } else if input == "/.." {
                input = "/"
                removeLastSegment(&output)
            } else if input == "." || input == ".." {
                input = ""
            } else {
                // Move the first path segment from input to the end of output.
                // A segment is "/" followed by any characters up to but not
                // including the next "/", OR (for the very first iteration on
                // a relative path) the characters up to the first "/".
                let segmentEnd = nextSegmentEnd(in: input)
                output.append(contentsOf: input[..<segmentEnd])
                input.removeSubrange(input.startIndex..<segmentEnd)
            }
        }
        return output
    }

    /// Remove the last `/`-prefixed segment from `output` (including the
    /// leading slash). If there is no slash, clear `output`.
    private static func removeLastSegment(_ output: inout String) {
        if let lastSlash = output.lastIndex(of: "/") {
            output.removeSubrange(lastSlash..<output.endIndex)
        } else {
            output.removeAll(keepingCapacity: true)
        }
    }

    /// Find the index past the end of the first path segment in `input`.
    /// If `input` starts with `/`, the segment runs from index 0 through the
    /// character before the *next* slash. Otherwise it runs to the first
    /// slash (or to end-of-input).
    private static func nextSegmentEnd(in input: String) -> String.Index {
        if input.hasPrefix("/") {
            let afterFirst = input.index(after: input.startIndex)
            if let nextSlash = input[afterFirst...].firstIndex(of: "/") {
                return nextSlash
            }
            return input.endIndex
        }
        if let nextSlash = input.firstIndex(of: "/") {
            return nextSlash
        }
        return input.endIndex
    }
}
