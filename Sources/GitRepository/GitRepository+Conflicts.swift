import Foundation

extension GitRepository: ConflictReadable {
    public func getConflictedFiles() async throws -> Set<String> {
        let status = try await workingTree.workingTreeStatus()
        return status.conflictedFiles
    }

    public func conflictOperation() -> ConflictOperation? {
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.mergeHead.rawValue).path) {
            return .merge
        }
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue).path) {
            return .cherryPick
        }
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.revertHead.rawValue).path) {
            return .revert
        }
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.rebaseMerge.rawValue).path) ||
           fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.rebaseApply.rawValue).path) {
            return .rebase
        }
        return nil
    }

    public func theirsCommitHash() -> String? {
        guard let operation = conflictOperation() else { return nil }

        let refPath: GitPath
        switch operation {
        case .merge: refPath = .mergeHead
        case .cherryPick: refPath = .cherryPickHead
        case .revert: refPath = .revertHead
        case .rebase: refPath = .rebaseHead
        }

        let refURL = gitURL.appendingPathComponent(refPath.rawValue)
        return try? String(contentsOf: refURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ConflictWritable
extension GitRepository: ConflictWritable {
    public func abortOperation() async throws {
        guard let op = conflictOperation() else { return }

        var abortedOperation: GitEvent?

        switch op {
        case .merge:
            try await commandRunner.run(.mergeAbort)
            abortedOperation = .mergeAborted
        case .cherryPick:
            try await commandRunner.run(.cherryPickAbort)
            abortedOperation = .cherryPickAborted
        case .revert:
            try await commandRunner.run(.revertAbort)
            abortedOperation = .revertAborted
        case .rebase:
            let result = try await commandRunner.run(.rebaseAbort)
            guard result.exitCode == 0 else {
                throw GitError.rebaseAbortFailed
            }
            abortedOperation = .rebaseAborted
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear(where: { key in
            if case .commit = key { return true }
            return false
        })
        await workingTree.invalidateIndexCache()

        if let abortedOperation {
            eventSubject.send(abortedOperation)
        }
    }

    public func skipOperation() async throws {
        guard let op = conflictOperation() else { return }
        guard op == .rebase else {
            // Skip is only defined for rebase. Other operations have no equivalent
            // "skip this commit and keep going" semantic.
            throw GitError.rebaseSkipFailed
        }

        let result = try await commandRunner.run(.rebaseSkip)
        guard result.exitCode == 0 else {
            throw GitError.rebaseSkipFailed
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear(where: { key in
            if case .commit = key { return true }
            return false
        })
        await workingTree.invalidateIndexCache()
        eventSubject.send(.rebaseSkipped)
    }

    public func continueOperation() async throws {
        guard let op = conflictOperation() else { return }

        var continuedOperation: GitEvent?
        switch op {
        case .merge:
            let result = try await commandRunner.run(.mergeContinue)
            guard result.exitCode == 0 else {
                throw GitError.mergeContinueFailed
            }
            continuedOperation = .mergeContinued
        case .cherryPick:
            let result = try await commandRunner.run(.cherryPickContinue)
            // Check for empty cherry-pick
            if result.exitCode != 0 && result.stderr.contains("now empty") {
                // Auto-skip empty cherry-picks
                let skipResult = try await commandRunner.run(.cherryPickSkip)
                guard skipResult.exitCode == 0 else {
                    throw GitError.cherryPickSkipFailed
                }
                continuedOperation = .cherryPickContinued
            } else if result.exitCode != 0 {
                throw GitError.cherryPickContinueFailed
            } else {
                continuedOperation = .cherryPickContinued
            }
        case .revert:
            let result = try await commandRunner.run(.revertContinue)
            guard result.exitCode == 0 else {
                throw GitError.revertContinueFailed
            }
            continuedOperation = .revertContinued
        case .rebase:
            let result = try await commandRunner.run(.rebaseContinue)
            guard result.exitCode == 0 else {
                throw GitError.rebaseContinueFailed
            }
            continuedOperation = .rebaseContinued
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear(where: { key in
            if case .commit = key { return true }
            return false
        })
        await workingTree.invalidateIndexCache()

        if let event = continuedOperation {
            eventSubject.send(event)
        }
    }
}
