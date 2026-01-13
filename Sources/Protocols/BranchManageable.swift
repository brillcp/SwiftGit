import Foundation

/// Protocol for managing branches (checkout, create, delete)
public protocol BranchManageable: Actor {
    /// Push commits to remote
    func push(
        remote: String?,
        branch: String?,
        setUpstream: Bool,
        force: Bool
    ) async throws

    /// Checkout an existing branch or create and checkout a new branch
    func checkoutBranch(_ name: String, createNew: Bool) async throws

    /// Delete a local branch
    func deleteBranch(_ name: String, force: Bool) async throws
}
