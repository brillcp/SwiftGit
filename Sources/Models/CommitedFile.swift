import Foundation

public enum GitChangeType: Hashable, Sendable {
    case added
    case modified
    case deleted
    case renamed(from: String)
    case untracked
}

// MARK: - File (for commits/diffs)
public struct CommitedFile: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let blob: Blob
    public var changeType: GitChangeType = .modified
}

// MARK: - Equatable
extension CommitedFile: Equatable {
    public static func == (lhs: CommitedFile, rhs: CommitedFile) -> Bool {
        lhs.id == rhs.id
    }
}
