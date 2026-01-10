import Foundation

public enum GitError: LocalizedError {
    // MARK: - Setup & Environment
    case gitNotFound
    case notARepository

    // MARK: - Commit Operations
    case emptyCommitMessage
    case nothingToCommit
    case commitFailed

    // MARK: - Branch Operations
    case uncommittedChanges
    case checkoutFailed(branch: String)
    case cannotDeleteCurrentBranch
    case cannotDeleteProtectedBranch(String)
    case deleteBranchFailed(branch: String)

    // MARK: - Staging Operations
    case cannotStageHunkFromUntrackedFile
    case fileNotInIndex(path: String)
    case stageFailed(path: String)
    case stageAllFailed
    case unstageFailed(path: String)
    case unstageAllFailed
    case stageHunkFailed(path: String)
    case unstageHunkFailed(path: String)

    // MARK: - Discard Operations
    case discardFileFailed(path: String)
    case discardHunkFailed(path: String)
    case discardAllFailed
    case restoreFailed
    case cleanFailed

    // MARK: - Stash Operations
    case nothingToStash
    case stashFailed
    case stashPopFailed
    case stashPopConflict
    case stashApplyFailed
    case stashDropFailed

    // MARK: - Advanced Operations
    case cherryPickFailed(commit: String)
    case cherryPickConflict(commit: String)
    case revertFailed(commit: String)
    case revertConflict(commit: String)

    // MARK: - Conflict Detection
    case conflictDetected
    case diffFailed

    public var errorDescription: String? {
        switch self {
        // MARK: - Setup & Environment
        case .gitNotFound:
            return "Git is not installed. Please install Git to continue."
        case .notARepository:
            return "This folder is not a Git repository."

        // MARK: - Commit Operations
        case .emptyCommitMessage:
            return "Commit message cannot be empty."
        case .nothingToCommit:
            return "No changes to commit. Stage files first."
        case .commitFailed:
            return "Failed to create commit. Please try again."

        // MARK: - Branch Operations
        case .uncommittedChanges:
            return "You have uncommitted changes. Commit or stash them before switching branches."
        case .checkoutFailed(let branch):
            return "Failed to checkout '\(branch)'. The branch may not exist."
        case .cannotDeleteCurrentBranch:
            return "Cannot delete the current branch. Switch to another branch first."
        case .cannotDeleteProtectedBranch(let name):
            return "Cannot delete '\(name)'. This is a protected branch (main, master, develop, etc.)."
        case .deleteBranchFailed(let branch):
            return "Failed to delete '\(branch)'. The branch may have unmerged changes."

        // MARK: - Staging Operations
        case .cannotStageHunkFromUntrackedFile:
            return "Cannot stage individual changes from a new file. Stage the entire file first."
        case .fileNotInIndex(let path):
            return "'\(path)' is not tracked. Stage the entire file before staging individual changes."
        case .stageFailed(let path):
            return "Failed to stage '\(path)'."
        case .stageAllFailed:
            return "Failed to stage files."
        case .unstageFailed(let path):
            return "Failed to unstage '\(path)'."
        case .unstageAllFailed:
            return "Failed to unstage files."
        case .stageHunkFailed(let path):
            return "Failed to stage changes in '\(path)'."
        case .unstageHunkFailed(let path):
            return "Failed to unstage changes in '\(path)'."

        // MARK: - Discard Operations
        case .discardFileFailed(let path):
            return "Failed to discard changes in '\(path)'."
        case .discardHunkFailed(let path):
            return "Failed to discard selected changes in '\(path)'."
        case .discardAllFailed:
            return "Failed to discard changes."
        case .revertFailed:
            return "Failed to revert changes."
        case .cleanFailed:
            return "Failed to clean the repository."
        case .restoreFailed:
            return "Failed to restore the working directory."

        // MARK: - Stash Operations
        case .nothingToStash:
            return "No changes to stash."
        case .stashFailed:
            return "Failed to stash changes."
        case .stashPopFailed:
            return "Failed to apply stash."
        case .stashPopConflict:
            return "Cannot apply stash: your current changes would be overwritten. Commit or stash your changes first."
        case .stashApplyFailed:
            return "Failed to apply stash."
        case .stashDropFailed:
            return "Failed to delete stash."

        // MARK: - Advanced Operations
        case .cherryPickFailed(let commit):
            return "Failed to cherry-pick commit \(commit.prefix(7))."
        case .cherryPickConflict(let commit):
            return "Cherry-picking \(commit.prefix(7)) caused conflicts. Resolve them and commit."
        case .revertFailed(let commit):
            return "Failed to revert commit \(commit.prefix(7))."
        case .revertConflict(let commit):
            return "Reverting \(commit.prefix(7)) caused conflicts. Resolve them and commit."

        // MARK: - Conflict Detection
        case .conflictDetected:
            return "Merge conflicts detected. Resolve them before continuing."
        case .diffFailed:
            return "Failed to get file diff. Please try again."
        }
    }
}
