import Foundation

extension GitRepository: ConflictReadable {
    public func hasConflicts() async throws -> Bool {
        let mergeHead = gitURL.appendingPathComponent(GitPath.mergeHead.rawValue)
        let cherryPickHead = gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue)
        let revertHead = gitURL.appendingPathComponent(GitPath.revertHead.rawValue)

        return fileManager.fileExists(atPath: mergeHead.path) ||
               fileManager.fileExists(atPath: cherryPickHead.path) ||
               fileManager.fileExists(atPath: revertHead.path)
    }

    public func getConflictedFiles() async throws -> Set<String> {
        try await getRepoSnapshot().conflictedPaths
    }

    public func conflictOperation() async -> ConflictOperation? {
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.mergeHead.rawValue).path) {
            return .merge
        }
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue).path) {
            return .cherryPick
        }
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.revertHead.rawValue).path) {
            return .revert
        }
        return nil
    }
}

// MARK: - ConflictWritable
extension GitRepository: ConflictWritable {
    public func abortOperation() async throws {
        var abortedOperation: GitEvent?

        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.mergeHead.rawValue).path) {
            try await commandRunner.run(.mergeAbort)
            abortedOperation = .mergeAborted
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue).path) {
            try await commandRunner.run(.cherryPickAbort)
            abortedOperation = .cherryPickAborted
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.revertHead.rawValue).path) {
            try await commandRunner.run(.revertAbort)
            abortedOperation = .revertAborted
        }

        await invalidateAllCaches()

        if let abortedOperation {
            eventSubject.send(abortedOperation)
        }
    }

    public func continueOperation() async throws {
        var continuedOperation: GitEvent?

        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.mergeHead.rawValue).path) {
            let result = try await commandRunner.run(.mergeContinue)
            guard result.exitCode == 0 else {
                throw GitError.mergeContinueFailed
            }
            continuedOperation = .mergeContinued
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue).path) {
            let result = try await commandRunner.run(.cherryPickContinue)
            guard result.exitCode == 0 else {
                throw GitError.cherryPickContinueFailed
            }
            continuedOperation = .cherryPickContinued
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.revertHead.rawValue).path) {
            let result = try await commandRunner.run(.revertContinue)
            guard result.exitCode == 0 else {
                throw GitError.revertContinueFailed
            }
            continuedOperation = .revertContinued
        }

        await invalidateAllCaches()

        if let event = continuedOperation {
            eventSubject.send(event)
        }
    }
}
