import Foundation

extension GitRepository: RevertManageable {
    /// Create a new commit that undoes changes from a specific commit
    public func revertCommit(_ commitHash: String) async throws {
        let result = try await commandRunner.run(
            .revert(commitHash: commitHash, noCommit: false),
            stdin: nil
        )

        // Check for conflicts
        if result.exitCode != 0 {
            if result.stderr.contains("conflict") || result.stderr.contains("CONFLICT") {
                throw GitError.revertConflict(commit: commitHash)
            }
            throw GitError.revertFailed(commit: commitHash)
        }

        // Invalidate caches after successful revert
        await invalidateAllCaches()
    }
}