import Foundation

public enum GitError: LocalizedError {
    // MARK: - Setup & Environment
    case gitNotFound
    case notARepository

    // MARK: - Push
    case pushRejected(reason: String)
    case noUpstream
    case authenticationFailed
    case pushFailed
    case mergeFailed(branch: String)

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

    // MARK: - Working Tree Operations
    case workingTreeStatusFailed

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

    // MARK: - Reset Operations
    case resetFailed(commit: String)

    // MARK: - Rebase Operations
    case rebaseFailed(branch: String)
    case rebaseConflict(branch: String)

    // MARK: - Remote Operations
    case fetchFailed
    case pullFailed
    case pullConflict

    // MARK: - Advanced Operations
    case cherryPickFailed(commit: String)
    case cherryPickSkipFailed
    case cherryPickConflict(commit: String)
    case revertFailed(commit: String)
    case revertConflict(commit: String)

    // MARK: - Conflict Detection
    case conflictDetected
    case diffFailed
    case getCommittedFilesFailed
    case logFailed(reason: String)
    case commitNotFound
    case fileNotFound(path: String, ref: String)
    case getFileContentFailed(path: String, ref: String)

    // MARK: - Continue operations
    case cherryPickContinueFailed
    case mergeContinueFailed
    case revertContinueFailed
    case rebaseContinueFailed

    // MARK: - Abort operations
    case cherryPickAbortFailed
    case mergeAbortFailed
    case revertAbortFailed
    case rebaseAbortFailed

    // MARK: - Tag Operations
    case tagCreationFailed(name: String)

    case workflowFailed(name: String)
    case refsFailed

    public var errorDescription: String? {
        switch self {
        // MARK: - Setup & Environment
        case .gitNotFound:
            return "Git is not installed. Please install Git to continue."
        case .notARepository:
            return "This folder is not a Git repository."

        // MARK: - Push
        case .pushRejected(let reason):
            return "Push rejected: \(reason)"
        case .noUpstream:
            return "No upstream branch configured"
        case .authenticationFailed:
            return "Authentication failed"
        case .pushFailed:
            return "Push failed"
        case .mergeFailed(let branch):
            return "Failed to merge branch '\(branch)'. Please try again."

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
            
        // MARK: - Working Tree Operations
        case .workingTreeStatusFailed:
            return "Failed to get working tree status."

        // MARK: - Discard Operations
        case .discardFileFailed(let path):
            return "Failed to discard changes in '\(path)'."
        case .discardHunkFailed(let path):
            return "Failed to discard selected changes in '\(path)'."
        case .discardAllFailed:
            return "Failed to discard changes."
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

        // MARK: - Reset Operations
        case .resetFailed(let commit):
            return "Failed to reset to \(commit.shortHash)."

        // MARK: - Rebase Operations
        case .rebaseFailed(let branch):
            return "Failed to rebase onto '\(branch)'."
        case .rebaseConflict(let branch):
            return "Rebasing onto '\(branch)' caused conflicts. Resolve them and continue."

        // MARK: - Remote Operations
        case .fetchFailed:
            return "Failed to fetch from remote."
        case .pullFailed:
            return "Failed to pull from remote."
        case .pullConflict:
            return "Pulling caused conflicts. Resolve them and commit."

        // MARK: - Advanced Operations
        case .cherryPickFailed(let commit):
            return "Failed to cherry-pick commit \(commit.shortHash)."
        case .cherryPickSkipFailed:
            return "Cherrypick skip failed."
        case .cherryPickConflict(let commit):
            return "Cherry-picking \(commit.shortHash) caused conflicts. Resolve them and commit."
        case .revertFailed(let commit):
            return "Failed to revert commit \(commit.shortHash)."
        case .revertConflict(let commit):
            return "Reverting \(commit.shortHash) caused conflicts. Resolve them and commit."

        // MARK: - Conflict Detection
        case .conflictDetected:
            return "Merge conflicts detected. Resolve them before continuing."
        case .diffFailed:
            return "Failed to get file diff. Please try again."
        case .logFailed(let reason):
            return "Failed to get commit history. Reason: \(reason)."
        case .commitNotFound:
            return "Commit not found."
        case .getCommittedFilesFailed:
            return "Failed to get committed files."
        case .fileNotFound(let path, let ref):
            return "File '\(path)' not found at \(ref)"
        case .getFileContentFailed(let path, let ref):
            return "Failed to get '\(path)' at \(ref)"

        // MARK: - Continue operations
        case .cherryPickContinueFailed:
            return "Failed to continue cherry-pick"
        case .mergeContinueFailed:
            return "Failed to continue merge"
        case .revertContinueFailed:
            return "Failed to continue revert"
        case .rebaseContinueFailed:
            return "Failed to continue rebase"

        // MARK: - Abort operations
        case .cherryPickAbortFailed:
            return "Failed to abort cherry-pick"
        case .mergeAbortFailed:
            return "Failed to abort merge"
        case .revertAbortFailed:
            return "Failed to abort revert"
        case .rebaseAbortFailed:
            return "Failed to abort rebase"

        // MARK: - Tag Operations
        case .tagCreationFailed(let name):
            return "Failed to create tag '\(name)'."

        case .workflowFailed(let name):
            return "Failed to run workflow '\(name)'."

        case .refsFailed:
            return "Failed to read refs."
        }
    }
}
