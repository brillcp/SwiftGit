import Foundation

public protocol ConflictReadable: Actor {
    /// Get list of conflicted file paths
    func getConflictedFiles() async throws -> Set<String>

    /// Get the type of operation in progress (merge, cherry-pick, revert, rebase), or nil if none
    func conflictOperation() -> ConflictOperation?

    /// Get the commit hash of "theirs" side in a conflict (from MERGE_HEAD, CHERRY_PICK_HEAD, etc.)
    func theirsCommitHash() -> String?
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
