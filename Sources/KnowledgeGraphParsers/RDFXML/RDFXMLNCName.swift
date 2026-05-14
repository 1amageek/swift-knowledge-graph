import Foundation

/// XML 1.0 NCName validation per W3C Namespaces in XML 1.0 §4.
///
/// NCName is a non-colonised name: a `Name` (XML 1.0 §2.3) that contains
/// no `:`. RDF/XML uses NCNames for `rdf:ID` values, `rdf:nodeID` values,
/// and prefix names. The W3C RDF/XML negative-syntax tests check this:
/// invalid IDs must produce a parse error.
///
/// We implement the rule literally rather than approximating with a
/// regex, so that surrogate-pair code points (`>= 0x10000`) are accepted
/// per the spec and bare digits are rejected.
enum RDFXMLNCName {

    static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        var iterator = value.unicodeScalars.makeIterator()
        guard let first = iterator.next() else { return false }
        if !isNameStart(first) { return false }
        while let scalar = iterator.next() {
            if !isNameChar(scalar) { return false }
        }
        return true
    }

    private static func isNameStart(_ s: Unicode.Scalar) -> Bool {
        let v = s.value
        if v == 0x5F { return true }                          // _
        if (0x41...0x5A).contains(v) { return true }          // A-Z
        if (0x61...0x7A).contains(v) { return true }          // a-z
        if (0xC0...0xD6).contains(v) { return true }
        if (0xD8...0xF6).contains(v) { return true }
        if (0xF8...0x2FF).contains(v) { return true }
        if (0x370...0x37D).contains(v) { return true }
        if (0x37F...0x1FFF).contains(v) { return true }
        if (0x200C...0x200D).contains(v) { return true }
        if (0x2070...0x218F).contains(v) { return true }
        if (0x2C00...0x2FEF).contains(v) { return true }
        if (0x3001...0xD7FF).contains(v) { return true }
        if (0xF900...0xFDCF).contains(v) { return true }
        if (0xFDF0...0xFFFD).contains(v) { return true }
        if (0x10000...0xEFFFF).contains(v) { return true }
        return false
    }

    private static func isNameChar(_ s: Unicode.Scalar) -> Bool {
        if isNameStart(s) { return true }
        let v = s.value
        if v == 0x2D { return true }                          // -
        if v == 0x2E { return true }                          // .
        if (0x30...0x39).contains(v) { return true }          // 0-9
        if v == 0xB7 { return true }
        if (0x0300...0x036F).contains(v) { return true }
        if (0x203F...0x2040).contains(v) { return true }
        return false
    }
}
