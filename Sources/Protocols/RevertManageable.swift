import Foundation

public protocol RevertManageable: Actor {
    /// Create a new commit that undoes changes from a specific commit
    func revertCommit(_ commitHash: String) async throws
}