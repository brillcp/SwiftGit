import Foundation

public protocol ConflictReadable: Actor {
    /// Get list of conflicted file paths
    func getConflictedFiles() async throws -> Set<String>

    /// Get the type of operation in progress (merge, cherry-pick, revert, rebase), or nil if none
    func conflictOperation() -> ConflictOperation?

    /// Get the commit hash of "theirs" side in a conflict (from MERGE_HEAD, CHERRY_PICK_HEAD, etc.)
    func theirsCommitHash() -> String?

    /// Short name of the branch on the "theirs" side of the active operation.
    /// - For `.merge`, parsed from `.git/MERGE_MSG` (handles both
    ///   `Merge branch 'feature'` and `Merge remote-tracking branch 'origin/feature'`,
    ///   stripping any `remote/` prefix).
    /// - For `.rebase`, returns the trimmed last path component of
    ///   `.git/rebase-merge/head-name`.
    /// - For `.cherryPick`, `.revert`, or no operation, returns `nil` — those
    ///   reference commits, not branches.
    func theirsBranchName() -> String?

    /// During a rebase: the short branch name being rebased (last component of
    /// `.git/rebase-merge/head-name`). `nil` when not rebasing.
    func rebaseHeadName() -> String?

    /// During a rebase: the trimmed contents of `.git/rebase-merge/onto`
    /// (commit hash or ref). `nil` when not rebasing.
    func rebaseOnto() -> String?
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
