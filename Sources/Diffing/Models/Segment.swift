import Foundation

public struct Segment: Hashable, Sendable {
    public let id: Int
    public let text: String
    public let isHighlighted: Bool

    public init(id: Int, text: String, isHighlighted: Bool) {
        self.id = id
        self.text = text
        self.isHighlighted = isHighlighted
    }
}