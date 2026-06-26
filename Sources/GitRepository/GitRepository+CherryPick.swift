import Foundation

extension GitRepository: CherryPickWritable {
    public func cherryPick(_ commitHash: String) async throws {
        eventSubject.send(.startCherryPicking)

        let status = try await getWorkingTreeStatus()
        let needsStash = !status.files.isEmpty

        if needsStash {
            try await stashPush(message: "Auto stash before cherry-pick")
        }

        let result = try await commandRunner.run(
            .cherryPick(commitHash: commitHash)
        )

        if result.exitCode != 0 {
            if result.indicatesEmptyCherryPick {
                let skipResult = try await commandRunner.run(.cherryPickSkip)
                guard skipResult.exitCode == 0 else {
                    throw GitError.cherryPickSkipFailed
                }

                if needsStash {
                    try await stashPop(index: 0)
                }

                await cache.remove(.head)
                await cache.remove(.refs)
                await workingTree.invalidateIndexCache()
                eventSubject.send(.operationSkipped(operation: .cherryPick, isComplete: true))
                return
            }

            // On conflict, DON'T pop stash - leave it for after resolution
            if result.indicatesConflict {
                await workingTree.invalidateIndexCache()
                throw GitError.cherryPickConflict(commit: commitHash)
            }

            // On other errors, try to restore stash
            if needsStash {
                try? await stashPop(index: 0)
            }
            throw GitError.cherryPickFailed(commit: commitHash)
        }

        // Success - pop stash
        if needsStash {
            try await stashPop(index: 0)
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await workingTree.invalidateIndexCache()
        eventSubject.send(.operationCompleted(operation: .cherryPick, ref: commitHash))
    }
}
