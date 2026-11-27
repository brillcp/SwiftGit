import Foundation

/// Protocol for reading branch information
public protocol BranchReadable: Actor {
    /// Get all branches (local and remote)
    func getBranches() async throws -> Branches

    /// Resolves the tracked upstream of `branch` (or HEAD when nil).
    /// Returns nil when no upstream is configured — that is an expected
    /// state for fresh local branches and is not surfaced as an error.
    func getUpstream(for branch: String?) async throws -> Upstream?

    /// Counts commits the local branch has that the upstream doesn't, and
    /// vice versa. Use this — not the loaded commit window — to determine
    /// ahead/behind, since the window may not contain either ref.
    func getAheadBehind(local: String, upstream: String) async throws -> AheadBehind


    /// Upstream and ahead/behind counts for every local branch that tracks a
    /// remote branch, keyed by local branch name, from one git process.
    /// Branches without an upstream, or whose upstream is gone, are absent.
    func getBranchSyncState() async throws -> [String: BranchSyncState]
}