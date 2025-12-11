import Foundation

public enum GitError: LocalizedError {
    case gitNotFound
    case commandFailed(command: GitCommand, result: CommandResult)
    case notARepository
    case conflictDetected
    case cannotStageHunkFromUntrackedFile
    case fileNotInIndex(path: String)
    case emptyCommitMessage
    case nothingToCommit
    case uncommittedChanges
    case checkoutFailed(branch: String, action: String, stderr: String)
    case cannotDeleteCurrentBranch(String)
    case deleteBranchFailed(branch: String, stderr: String)

    public var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "Git binary not found. Please install Git."
        case .commandFailed(let command, let result):
            return """
            Git command failed: \(command.arguments.joined(separator: " "))
            Exit code: \(result.exitCode)
            Error: \(result.stderr)
            """
        case .notARepository:
            return "Not a Git repository"
        case .conflictDetected:
            return "conflict"
        case .cannotStageHunkFromUntrackedFile:
            return "Cannot stage individual hunks from untracked files. Please stage the entire file first."
        case .fileNotInIndex(let path):
            return "Cannot stage hunk: '\(path)' is not in the index. Stage the entire file first."
        case .emptyCommitMessage:
            return "Commit message cannot be empty."
        case .nothingToCommit:
            return "Nothing to commit."
        case .uncommittedChanges:
            return "The repository contains uncommitted changes."
        case .checkoutFailed(let branch, let action, let stderr):
            return "Failed to \(action) '\(branch)': \(stderr)"
        case .cannotDeleteCurrentBranch(let name):
            return "Cannot delete the current branch: \(name). Checkout a different branch first."
        case .deleteBranchFailed(let branch, let stderr):
            return "Failed to delete branch '\(branch)': \(stderr)"
        }
    }
}
