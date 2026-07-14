import Foundation

extension GitRepository: RevertWritable {
    public func revertCommit(_ commitHash: String) async throws {
        eventSubject.send(.startReverting(hash: commitHash))

        let result = try await commandRunner.run(
            .revert(commitHash: commitHash, noCommit: false)
        )

        if result.exitCode != 0 {
            if result.indicatesConflict {
                await workingTree.invalidateIndexCache()
                throw GitError.revertConflict(commit: commitHash)
            }
            throw GitError.revertFailed(commit: commitHash)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.operationCompleted(operation: .revert, ref: commitHash))
    }
}
