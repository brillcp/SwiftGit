import Foundation

public protocol ConflictManageable: Actor {
    /// Check if repository is in a conflicted state
    func hasConflicts() async throws -> Bool

    /// Get list of conflicted file paths
    func getConflictedFiles() async throws -> Set<String>

    /// Get the type of operation causing conflicts (merge, cherry-pick, revert)
    func conflictOperation() async -> ConflictOperation?

    /// Abort current merge/cherry-pick/revert operation
    func abortOperation() async throws
}

/// Type of Git operation that can result in conflicts
public enum ConflictOperation: Sendable {
    case merge
    case cherryPick
    case revert
}
