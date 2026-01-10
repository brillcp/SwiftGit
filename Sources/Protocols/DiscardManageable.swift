import Foundation

/// Protocol for discarding changes
public protocol DiscardManageable: Actor {
    /// Discard changes in a single file
    func discardFile(at path: String) async throws

    /// Discard all changes
    func discardAllFiles() async throws

    /// Discard a specific hunk
    func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws

    /// Discard all unstaged changes and remove all untracked files/directories, preserving staged changes
    func discardUnstagedChanges() async throws
}
