import Foundation

extension GitRepository: CherryPickWritable {
    public func cherryPick(_ commitHash: String) async throws {
        let status = try await getWorkingTreeStatus()
        let needsStash = !status.files.isEmpty

        if needsStash {
            try await stashPush(message: "Auto stash before cherry-pick")
        }

        let result = try await commandRunner.run(
            .cherryPick(commitHash: commitHash)
        )

        if result.exitCode != 0 {
            // On conflict, DON'T pop stash - leave it for after resolution
            if result.stderr.localizedCaseInsensitiveContains("conflict") {
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

        await workingTree.invalidateIndexCache()
        eventSubject.send(.cherryPickCompleted)
    }

    public func cherryPickContinue() async throws {
        let result = try await commandRunner.run(.cherryPickContinue)
        guard result.exitCode == 0 else {
            throw GitError.cherryPickContinueFailed
        }
        await invalidateAllCaches()
        eventSubject.send(.cherryPickContinued)
    }

    public func cherryPickAbort() async throws {
        let result = try await commandRunner.run(.cherryPickAbort)
        guard result.exitCode == 0 else {
            throw GitError.cherryPickAbortFailed
        }
        await invalidateAllCaches()
        eventSubject.send(.cherryPickAborted)
    }
}
