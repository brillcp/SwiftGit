import Foundation

extension GitRepository: RebaseWritable {
    public func rebase(branch: String? = nil, onto target: String) async throws {
        eventSubject.send(.startRebasing)

        let result = try await commandRunner.run(
            .rebase(branch: branch, onto: target)
        )

        guard result.exitCode == 0 else {
            if result.indicatesConflict {
                await cache.remove(.head)
                await workingTree.invalidateIndexCache()
                throw GitError.rebaseConflict(branch: branch ?? target)
            }
            throw GitError.rebaseFailed(branch: branch ?? target)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear {
            if case .commit = $0 { return true }
            return false
        }
        await workingTree.invalidateIndexCache()
        eventSubject.send(.operationCompleted(operation: .rebase, ref: branch ?? target))
    }
}
