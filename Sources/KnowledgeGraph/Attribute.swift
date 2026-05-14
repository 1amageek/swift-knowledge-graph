import Foundation

/// Free-form key/value pair attached to a `Node` or `Edge`.
///
/// Attributes carry rendering or layout hints that fall outside the RDF data
/// model itself — for example a colour, a weight, or a tooltip. The IR layer
/// does not interpret these values; downstream renderers and layout engines do.
public struct Attribute: Hashable, Sendable, Codable {
    public let key: String
    public let value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
