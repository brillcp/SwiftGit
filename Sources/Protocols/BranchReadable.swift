import Foundation

/// Protocol for reading branch information
public protocol BranchReadable: Actor {
    /// Get all branches (local and remote)
    func getBranches() async throws -> Branches
}
