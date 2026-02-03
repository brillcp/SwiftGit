import Foundation

/// Protocol for rebasing the current branch onto another branch
public protocol RebaseWritable: Actor {
    /// Rebase the current branch onto another branch
    func rebase(onto branch: String) async throws
}
