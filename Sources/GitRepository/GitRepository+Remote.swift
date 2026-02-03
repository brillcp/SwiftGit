import Foundation

extension GitRepository: RemoteWritable {
    public func fetch(remote: String? = nil, prune: Bool = true) async throws {
        let result = try await commandRunner.run(
            .fetch(remote: remote, prune: prune)
        )

        guard result.exitCode == 0 else {
            throw GitError.fetchFailed
        }

        await cache.remove(.refs)
        eventSubject.send(.fetched(remote: remote ?? "origin"))
    }

    public func pull(remote: String? = nil, branch: String? = nil) async throws {
        let result = try await commandRunner.run(
            .pull(remote: remote, branch: branch)
        )

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout

            if output.localizedCaseInsensitiveContains("conflict") {
                throw GitError.pullConflict
            }
            throw GitError.pullFailed
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear(where: { key in
            if case .commit = key { return true }
            return false
        })
        await workingTree.invalidateIndexCache()
        eventSubject.send(.pulled(remote: remote ?? "origin"))
    }
}
