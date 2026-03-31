import Foundation

/// Protocol for rebasing branches
public protocol RebaseWritable: Actor {
    /// Rebase a branch onto another branch. If `branch` is nil, rebases the current branch.
    func rebase(onto target: String, branch: String?) async throws
}
