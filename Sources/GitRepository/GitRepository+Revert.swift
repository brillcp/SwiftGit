import Foundation

extension GitRepository: RevertWritable {
    public func revertCommit(_ commitHash: String) async throws {
        let result = try await commandRunner.run(
            .revert(commitHash: commitHash, noCommit: false)
        )

        if result.exitCode != 0 {
            if result.stderr.localizedCaseInsensitiveContains("conflict") {
                throw GitError.revertConflict(commit: commitHash)
            }
            throw GitError.revertFailed(commit: commitHash)
        }

        await invalidateAllCaches()
        eventSubject.send(.revertedCommit(hash: commitHash))
    }
}
