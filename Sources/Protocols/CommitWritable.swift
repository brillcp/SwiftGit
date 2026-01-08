import Foundation

/// Protocol for creating commits
public protocol CommitWritable: Actor {
    /// Create a new commit with the given message
    func commit(message: String) async throws
}