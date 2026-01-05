import Foundation

extension GitRepository: CherryPickManageable {
    /// Apply changes from a commit to the current branch
    public func cherryPick(_ commitHash: String) async throws {
        let result = try await commandRunner.run(
            .cherryPick(commitHash: commitHash),
            stdin: nil,
            in: url
        )
        
        // Check for conflicts
        if result.exitCode != 0 {
            if result.stderr.contains("conflict") || result.stderr.contains("CONFLICT") {
                throw GitError.cherryPickConflict(commit: commitHash)
            }
            throw GitError.cherryPickFailed(commit: commitHash)
        }
        
        // Invalidate caches after successful cherry-pick
        await invalidateAllCaches()
    }
}
