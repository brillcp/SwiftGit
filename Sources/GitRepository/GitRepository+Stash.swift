import Foundation

extension GitRepository: StashReadable {
    public func getStashes() async throws -> [Stash] {
        try await refReader.getStashes()
    }
}

// MARK: - StashManageable
extension GitRepository: StashWritable {
    @discardableResult
    public func stashPush(message: String? = nil) async throws -> Stash.ID? {
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
        return try await publishNewestStash()
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
        eventPublisher.send(.stashPopped(id: stashId))
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
        eventPublisher.send(.stashApplied)
    }

    public func stashDrop(index: Int) async throws {
        let stashId = try await getStashes()[index].id

        let result = try await commandRunner.run(
            .stashDrop(index: index))

        guard result.exitCode == 0 else {
            throw GitError.stashDropFailed
        }

        await cache.remove(.stashes)
        eventPublisher.send(.stashDropped(id: stashId))
    }

    @discardableResult
    public func stashFiles(paths: [String], message: String? = nil) async throws -> Stash.ID? {
        guard !paths.isEmpty else { return nil }

        let result = try await commandRunner.run(
            .stashPushFiles(paths: paths, message: message))

        let output = result.stderr + result.stdout
        if output.contains("No local changes") {
            throw GitError.nothingToStash
        }

        guard result.exitCode == 0 else {
            throw GitError.stashFailed
        }

        await workingTree.invalidateIndexCache()
        await cache.remove(.stashes)
        return try await publishNewestStash()
    }

    @discardableResult
    public func stashFile(path: String, message: String? = nil) async throws -> Stash.ID? {
        let result = try await commandRunner.run(
            .stashPushFile(path: path, message: message))

        let output = result.stderr + result.stdout
        if output.contains("No local changes") {
            throw GitError.nothingToStash
        }

        guard result.exitCode == 0 else {
            throw GitError.stashFailed
        }

        await workingTree.invalidateIndexCache()
        await cache.remove(.stashes)
        return try await publishNewestStash()
    }

    public func stashRestoreFile(index: Int, path: String) async throws {
        let result = try await commandRunner.run(
            .stashRestoreFile(index: index, path: path))

        guard result.exitCode == 0 else {
            throw GitError.restoreFailed
        }

        await workingTree.invalidateIndexCache()
        eventPublisher.send(.stashApplied)
    }

    public func stashRestoreFiles(index: Int, paths: [String]) async throws {
        guard !paths.isEmpty else { return }

        let result = try await commandRunner.run(
            .stashRestoreFiles(index: index, paths: paths))

        guard result.exitCode == 0 else {
            throw GitError.restoreFailed
        }

        await workingTree.invalidateIndexCache()
        eventPublisher.send(.stashApplied)
    }
}

private extension GitRepository {
    /// The stash just pushed is always `stash@{0}`; announce it and hand its
    /// id back so callers don't need a second `getStashes()`.
    func publishNewestStash() async throws -> Stash.ID? {
        guard let id = try await getStashes().first?.id else { return nil }
        eventPublisher.send(.stashed(id: id))
        return id
    }
}
