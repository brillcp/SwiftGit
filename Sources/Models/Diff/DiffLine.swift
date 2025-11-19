import Foundation

public struct DiffLine: Hashable, Sendable {
    public enum LineType: Sendable { case added, removed, unchanged }

    public let id: Int
    public let type: LineType
    public let segments: [Segment]
}
