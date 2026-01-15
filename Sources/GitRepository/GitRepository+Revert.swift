import Foundation

extension GitRepository: RevertWritable {
    public func revertCommit(_ commitHash: String) async throws {
        let result = try await commandRunner.run(
            .revert(commitHash: commitHash, noCommit: false),
            stdin: nil
        )

        if result.exitCode != 0 {
            let conflict = "conflict"
            if result.stderr.contains(conflict) || result.stderr.contains(conflict.uppercased()) {
                throw GitError.revertConflict(commit: commitHash)
            }
            throw GitError.revertFailed(commit: commitHash)
        }

        await invalidateAllCaches()
        eventSubject.send(.revertedCommit(hash: commitHash))
    }
}
