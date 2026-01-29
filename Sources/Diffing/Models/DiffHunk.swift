import Foundation

public struct DiffHunk: Hashable, Sendable {
    public let id: Int
    public let header: String
    public let lines: [DiffLine]
    public let hasNoNewlineAtEnd: Bool

    public init(id: Int, header: String, lines: [DiffLine], hasNoNewlineAtEnd: Bool = false) {
        self.id = id
        self.header = header
        self.lines = lines
        self.hasNoNewlineAtEnd = hasNoNewlineAtEnd
    }
}
