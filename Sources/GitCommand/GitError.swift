import Foundation

public enum GitError: LocalizedError {
    case gitNotFound
    case notARepository
    case conflictDetected
    case cannotStageHunkFromUntrackedFile
    case fileNotInIndex(path: String)
    case emptyCommitMessage
    case commitFailed(stderr: String)
    case nothingToCommit
    case uncommittedChanges
    case discardFileFailed(stderr: String)
    case discardHunkFailed(stderr: String)
    case discardAllFailed(stderr: String)
    case stageFailed(stderr: String)
    case stageAllFailed(stderr: String)
    case unstageFailed(stderr: String)
    case unstageAllFailed(stderr: String)
    case stageHunkFailed(stderr: String)
    case unstageHunkFailed(stderr: String)
    case checkoutFailed(branch: String, action: String, stderr: String)
    case cannotDeleteCurrentBranch
    case cannotDeleteProtectedBranch(String)
    case deleteBranchFailed(branch: String, stderr: String)
    case nothingToStash
    case stashFailed(stderr: String)
    case stashPopFailed(stderr: String)
    case stashApplyFailed(stderr: String)
    case stashDropFailed(stderr: String)
    case cherryPickFailed(commit: String, stderr: String)
    case cherryPickConflict(commit: String)
    case revertFailed(commit: String, stderr: String)
    case revertConflict(commit: String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git binary not found. Please install Git."
        case .notARepository:
            return "Not a Git repository"
        case .conflictDetected:
            return "conflict"
        case .cannotStageHunkFromUntrackedFile:
            return "Cannot stage individual hunks from untracked files. Please stage the entire file first."
        case .fileNotInIndex:
            return "Cannot stage hunk. File is not in the index. Stage the entire file first."
        case .emptyCommitMessage:
            return "Commit message cannot be empty."
        case .commitFailed(let stderr):
            return "Failed to create commit: \(stderr)"
        case .nothingToCommit:
            return "Nothing to commit."
        case .uncommittedChanges:
            return "The repository contains uncommitted changes."
        case .discardFileFailed(let stderr):
            return "Failed to discard changes: \(stderr)"
        case .discardHunkFailed(let stderr):
            return "Failed to discard hunk: \(stderr)"
        case .discardAllFailed(let stderr):
            return "Failed to discard all changes: \(stderr)"
        case .stageFailed(let stderr):
            return "Failed to stage: \(stderr)"
        case .stageAllFailed(let stderr):
            return "Failed to stage all files: \(stderr)"
        case .unstageFailed(let stderr):
            return "Failed to unstage: \(stderr)"
        case .unstageAllFailed(let stderr):
            return "Failed to unstage all files: \(stderr)"
        case .stageHunkFailed(let stderr):
            return "Failed to stage hunk: \(stderr)"
        case .unstageHunkFailed(let stderr):
            return "Failed to unstage hunk: \(stderr)"
        case .checkoutFailed(let branch, let action, let stderr):
            return "Failed to \(action) '\(branch)': \(stderr)"
        case .cannotDeleteCurrentBranch:
            return "Cannot delete the current branch. Checkout a different branch first."
        case .cannotDeleteProtectedBranch(let name):
            return "Cannot delete protected branch '\(name)'. This is a critical branch."
        case .deleteBranchFailed(let branch, _):
            return "Failed to delete branch '\(branch)."
        case .nothingToStash:
            return "No changes to stash."
        case .stashFailed:
            return "Failed to stash changes."
        case .stashPopFailed:
            return "Failed to pop stash."
        case .stashApplyFailed:
            return "Failed to apply stash."
        case .stashDropFailed:
            return "Failed to drop stash."
        case .cherryPickFailed(let commit, _):
            return "Failed to cherry-pick commit \(commit.prefix(7))."
        case .cherryPickConflict(let commit):
            return "Cherry-pick of \(commit.prefix(7)) resulted in conflicts. Resolve conflicts and commit."
        case .revertFailed(let commit, _):
            return "Failed to revert commit \(commit.prefix(7))."
        case .revertConflict(let commit):
            return "Revert of \(commit.prefix(7)) resulted in conflicts. Resolve conflicts and commit."
        }
    }
}
