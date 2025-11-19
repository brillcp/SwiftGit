import Foundation

public struct Segment: Hashable, Sendable {
    public let id: Int
    public let text: String
    public let isHighlighted: Bool
}
