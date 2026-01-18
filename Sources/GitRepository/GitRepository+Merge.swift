import Foundation

extension GitRepository: MergeWritable {
    public func mergeContinue() async throws {
        let result = try await commandRunner.run(.mergeContinue)
        guard result.exitCode == 0 else {
            throw GitError.mergeContinueFailed
        }
        await invalidateAllCaches()
        eventSubject.send(.mergeContinued)
    }

    public func mergeAbort() async throws {
        let result = try await commandRunner.run(.mergeAbort)
        guard result.exitCode == 0 else {
            throw GitError.mergeAbortFailed
        }
        await invalidateAllCaches()
        eventSubject.send(.mergeAborted)
    }
}
