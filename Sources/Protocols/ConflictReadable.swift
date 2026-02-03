import Foundation

public protocol ConflictReadable: Actor {
    /// Check if repository is in a conflicted state
    func hasConflicts() async throws -> Bool

    /// Get list of conflicted file paths
    func getConflictedFiles() async throws -> Set<String>

    /// Get the type of operation causing conflicts (merge, cherry-pick, revert, rebase)
    func conflictOperation() async -> ConflictOperation?
}

/// Type of Git operation that can result in conflicts
public enum ConflictOperation: Sendable {
    case merge
    case cherryPick
    case revert
    case rebase

    /// The Git ref file that contains the commit hash for "theirs" side
    public var refFile: String {
        switch self {
        case .merge:
            "\(GitPath.git.rawValue)/\(GitPath.mergeHead.rawValue)"
        case .cherryPick:
            "\(GitPath.git.rawValue)/\(GitPath.cherryPickHead.rawValue)"
        case .revert:
            "\(GitPath.git.rawValue)/\(GitPath.revertHead.rawValue)"
        case .rebase:
            "\(GitPath.git.rawValue)/\(GitPath.rebaseHead.rawValue)"
        }
    }
}
