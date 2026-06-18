import Foundation

extension GitRepository: MergeWritable {
    public func merge(branch: String, noFastForward: Bool) async throws {
        eventSubject.send(.startMerging(branch: branch))

        let result = try await commandRunner.run(
            .merge(branch: branch, noFastForward: noFastForward)
        )

        guard result.exitCode == 0 else {
            if result.indicatesConflict {
                await workingTree.invalidateIndexCache()
                throw GitError.conflictDetected
            }
            throw GitError.mergeFailed(branch: branch)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.mergeCompleted(branch: branch))
    }
}
