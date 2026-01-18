import Foundation

extension GitRepository: RevertWritable {
    public func revertCommit(_ commitHash: String) async throws {
        let result = try await commandRunner.run(
            .revert(commitHash: commitHash, noCommit: false)
        )

        if result.exitCode != 0 {
            if result.stderr.localizedCaseInsensitiveContains("conflict") {
                throw GitError.revertConflict(commit: commitHash)
            }
            throw GitError.revertFailed(commit: commitHash)
        }

        await invalidateAllCaches()
        eventSubject.send(.revertedCommit(hash: commitHash))
    }

    public func revertContinue() async throws {
        let result = try await commandRunner.run(.revertContinue)
        guard result.exitCode == 0 else {
            throw GitError.revertContinueFailed
        }
        await invalidateAllCaches()
        eventSubject.send(.revertContinued)
    }

    public func revertAbort() async throws {
        let result = try await commandRunner.run(.revertAbort)
        guard result.exitCode == 0 else {
            throw GitError.revertAbortFailed
        }
        await invalidateAllCaches()
        eventSubject.send(.revertAborted)
    }
}
