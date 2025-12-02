import Foundation

enum GitError: Error {
    case gitNotFound
    case commandFailed(command: GitCommand, result: CommandResult)
    case notARepository
    case conflictDetected
    case cannotStageHunkFromUntrackedFile
    case fileNotInIndex(path: String)

    var userMessage: String {
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
        }
    }
}
