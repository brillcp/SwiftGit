import Foundation
import Collections

/// Protocol for reading commit information from a Git repository
public protocol CommitReadable: Actor {
    /// Get a specific commit by its SHA
    func getCommit(_ hash: String) async throws -> Commit?

    /// Get all commits up to a specified limit, optionally including additional refs (e.g. stash hashes)
    func getAllCommits(limit: Int, additionalRefs: [String]) async throws -> Deque<Commit>

    /// Get the current HEAD commit SHA
    func getHEAD() async throws -> String?

    /// Get the name of the current checked-out branch
    func getHEADBranch() async throws -> String?

    /// Get changed files for a commit
    func getCommittedFiles(_ commitId: String) async throws -> OrderedDictionary<String, CommittedFile>

    /// Get changed files for a stash commit
    func getStashedFiles(_ stashId: String) async throws -> OrderedDictionary<String, CommittedFile>
}
