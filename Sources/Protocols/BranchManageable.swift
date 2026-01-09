import Foundation

/// Protocol for managing branches (checkout, create, delete)
public protocol BranchManageable: Actor {
    /// Checkout an existing branch or create and checkout a new branch
    func checkout(branch: String, createNew: Bool) async throws

    /// Delete a local branch
    func deleteBranch(_ name: String, force: Bool) async throws
}
