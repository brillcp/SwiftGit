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

        if let id = try await getStashes().first?.id {
            eventSubject.send(.stashed(id: id))
        }
    }

    public func stashPop(index: Int) async throws {
        let stashId = try await getStashes()[index].id

        let result = try await commandRunner.run(
            .stashPop(index: index),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.stashPopFailed
        }

        await workingTree.invalidateIndexCache()
        await cache.remove(.refs)
        eventSubject.send(.stashPopped(id: stashId))
    }

    public func stashApply(index: Int) async throws {
        let result = try await commandRunner.run(
            .stashApply(index: index),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.stashApplyFailed
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.stashApplied)
    }

    public func stashDrop(index: Int) async throws {
        let stashId = try await getStashes()[index].id

        let result = try await commandRunner.run(
            .stashDrop(index: index),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.stashDropFailed
        }

        await cache.remove(.refs)
        eventSubject.send(.stashDropped(id: stashId))
    }
}
