import Foundation

public protocol RevertWritable: Actor {
    /// Create a new commit that undoes changes from a specific commit
    func revertCommit(_ commitHash: String) async throws

    /// Reverse-apply a single hunk from a committed diff onto the working tree.
    /// The index is left untouched, so the reverted change shows up as an unstaged modification.
    func revertHunk(_ hunk: DiffHunk, at path: String) async throws
}
