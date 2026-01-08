import Foundation

/// Protocol for reading commit information from a Git repository
public protocol CommitReadable: Actor {
    /// Get a specific commit by its SHA
    func getCommit(_ hash: String) async throws -> Commit?

    /// Get all commits up to a specified limit
    func getAllCommits(limit: Int) async throws -> [Commit]

    /// Get the current HEAD commit SHA
    func getHEAD() async throws -> String?

    /// Get the name of the current checked-out branch
    func getHEADBranch() async throws -> String?

    /// Get changed files for a commit
    func getChangedFiles(_ commitId: String) async throws -> [String: CommitedFile]
}