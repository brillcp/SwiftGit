import Foundation

public struct DiffHunk: Hashable, Sendable {
    public let id: Int
    public let header: String
    public let lines: [DiffLine]
}
