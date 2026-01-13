import Foundation

extension GitRepository: StashReadable {
    public func getStashes() async throws -> [Stash] {
        try await refReader.getStashes()
    }
}

// MARK: - StashManageable
extension GitRepository: StashManageable {
    /// Save current changes to stash
    public func stashPush(message: String? = nil) async throws {
        let result = try await commandRunner.run(
            .stashPush(message: message),
            stdin: nil
        )

        let output = result.stderr + result.stdout
        if output.contains("No local changes") {
            throw GitError.nothingToStash
        }

        guard result.exitCode == 0 else {
            throw GitError.stashFailed
        }

        await workingTree.invalidateIndexCache()
        await cache.remove(.refs)
        eventSubject.send(.stashed)
    }

    /// Apply and remove most recent stash
    public func stashPop(index: Int) async throws {
        let result = try await commandRunner.run(
            .stashPop(index: index),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.stashPopFailed
        }

        // Invalidate caches
        await workingTree.invalidateIndexCache()
        await cache.remove(.refs)
        eventSubject.send(.stashPopped)
    }

    /// Apply stash without removing it
    public func stashApply(index: Int) async throws {
        let result = try await commandRunner.run(
            .stashApply(index: index),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.stashApplyFailed
        }

        // Invalidate caches
        await workingTree.invalidateIndexCache()
        eventSubject.send(.stashApplied)
    }

    /// Delete a stash
    public func stashDrop(index: Int) async throws {
        let result = try await commandRunner.run(
            .stashDrop(index: index),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.stashDropFailed
        }

        // Invalidate refs cache (stash list changed)
        await cache.remove(.refs)
        eventSubject.send(.stashDropped)
    }
}
