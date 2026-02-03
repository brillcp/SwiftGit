import Foundation

extension GitRepository: RebaseWritable {
    public func rebase(onto branch: String) async throws {
        let result = try await commandRunner.run(
            .rebase(onto: branch)
        )

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout

            if output.localizedCaseInsensitiveContains("conflict") {
                throw GitError.rebaseConflict(branch: branch)
            }
            throw GitError.rebaseFailed(branch: branch)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear(where: { key in
            if case .commit = key { return true }
            return false
        })
        await workingTree.invalidateIndexCache()
        eventSubject.send(.rebaseCompleted)
    }
}
