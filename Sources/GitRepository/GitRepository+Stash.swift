import Foundation

extension GitRepository: StashReadable {
    public func getStashes() async throws -> [Stash] {
        try await refReader.getStashes()
    }
}

// MARK: - StashManageable
extension GitRepository: StashWritable {
    public func stashPush(message: String? = nil) async throws {
        let result = try await commandRunner.run(
            .stashPush(message: message))

        let output = result.stderr + result.stdout
        if output.contains("No local changes") {
            throw GitError.nothingToStash
        }

        guard result.exitCode == 0 else {
            throw GitError.stashFailed
        }

        await workingTree.invalidateIndexCache()
        await cache.remove(.stashes)

        if let id = try await getStashes().first?.id {
            eventSubject.send(.stashed(id: id))
        }
    }

    public func stashPop(index: Int) async throws {
        let stashId = try await getStashes()[index].id

        let result = try await commandRunner.run(
            .stashPop(index: index))

        guard result.exitCode == 0 else {
            throw GitError.stashPopFailed
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.remove(.stashes)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.stashPopped(id: stashId))
    }

    public func stashApply(index: Int) async throws {
        let result = try await commandRunner.run(
            .stashApply(index: index))

        guard result.exitCode == 0 else {
            throw GitError.stashApplyFailed
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.remove(.stashes)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.stashApplied)
    }

    public func stashDrop(index: Int) async throws {
        let stashId = try await getStashes()[index].id

        let result = try await commandRunner.run(
            .stashDrop(index: index))

        guard result.exitCode == 0 else {
            throw GitError.stashDropFailed
        }

        await cache.remove(.stashes)
        eventSubject.send(.stashDropped(id: stashId))
    }
}
