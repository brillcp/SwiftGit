import Foundation

extension GitRepository: ResetWritable {
    public func reset(to commit: String, mode: ResetMode) async throws {
        eventSubject.send(.startResetting(mode: mode))

        let result = try await commandRunner.run(
            .resetToCommit(mode: mode, target: commit)
        )

        guard result.exitCode == 0 else {
            throw GitError.resetFailed(commit: commit)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear {
            if case .commit = $0 { return true }
            return false
        }
        await workingTree.invalidateIndexCache()
        eventSubject.send(.resetCompleted(mode: mode))
    }
}
