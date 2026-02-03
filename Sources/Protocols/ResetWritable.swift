import Foundation

/// Protocol for resetting the current branch to a specific commit
public protocol ResetWritable: Actor {
    /// Reset the current branch HEAD to a specific commit
    func reset(to commit: String, mode: ResetMode) async throws
}
