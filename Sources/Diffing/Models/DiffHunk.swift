import Foundation

public struct DiffHunk: Hashable, Sendable {
    /// Which side of the diff the "\ No newline at end of file" marker applies to.
    public enum NoNewlineSide: Hashable, Sendable {
        case old   // marker follows a removed (-) line
        case new   // marker follows an added (+) line
        case both  // marker present on both sides (neither side has trailing newline)
    }

    public let id: Int
    public let header: String
    public let lines: [DiffLine]
    public let hasNoNewlineAtEnd: Bool
    /// Populated when hasNoNewlineAtEnd is true; indicates which side lacks the trailing newline.
    public let noNewlineSide: NoNewlineSide?

    public init(id: Int, header: String, lines: [DiffLine], hasNoNewlineAtEnd: Bool = false, noNewlineSide: NoNewlineSide? = nil) {
        self.id = id
        self.header = header
        self.lines = lines
        self.hasNoNewlineAtEnd = hasNoNewlineAtEnd
        self.noNewlineSide = noNewlineSide
    }
}
