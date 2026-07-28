import Foundation

extension GitRepository: ConflictReadable {
    public func getConflictedFiles() async throws -> Set<String> {
        let status = try await workingTree.workingTreeStatus()
        var files = status.conflictedFiles

        if conflictOperation() != nil {
            for file in status.files.values where file.staged != nil && !files.contains(file.path) {
                let fileURL = url.appendingPathComponent(file.path)
                if (try? String(contentsOf: fileURL, encoding: .utf8))?.contains("<<<<<<< ") == true {
                    files.insert(file.path)
                }
            }
        }

        return files
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

    public func theirsBranchName() -> String? {
        guard let operation = conflictOperation() else { return nil }
        switch operation {
        case .merge:
            return parseMergeMessageBranch()
        case .rebase:
            return rebaseHeadName()
        case .cherryPick, .revert:
            return nil
        }
    }

    public func rebaseHeadName() -> String? {
        readRebaseMergeFile(named: "head-name")
            .flatMap { $0.components(separatedBy: "/").last }
    }

    public func rebaseOnto() -> String? {
        readRebaseMergeFile(named: "onto")
    }
}

// MARK: - ConflictWritable
extension GitRepository: ConflictWritable {
    public func abortOperation() async throws {
        guard let op = conflictOperation() else { return }

        eventSubject.send(.startAbortingOperation)

        let command = switch op {
        case .merge: GitCommand.mergeAbort
        case .cherryPick: GitCommand.cherryPickAbort
        case .revert: GitCommand.revertAbort
        case .rebase: GitCommand.rebaseAbort
        }
        let result = try await commandRunner.run(command)
        guard result.exitCode == 0 else {
            throw GitError.operationAbortFailed(
                operation: op,
                reason: result.failureDescription
            )
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear {
            if case .commit = $0 { return true }
            return false
        }
        await workingTree.invalidateIndexCache()

        eventSubject.send(.operationAborted(operation: op))
    }

    public func skipOperation() async throws {
        guard let op = conflictOperation() else { return }
        guard op == .rebase else {
            // Skip is only defined for rebase. Other operations have no equivalent
            // "skip this commit and keep going" semantic.
            throw GitError.rebaseSkipFailed
        }

        eventSubject.send(.startSkippingOperation)

        let result = try await commandRunner.run(.rebaseSkip)
        guard result.exitCode == 0 else {
            throw GitError.rebaseSkipFailed
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear {
            if case .commit = $0 { return true }
            return false
        }
        await workingTree.invalidateIndexCache()
        eventSubject.send(.operationSkipped(operation: .rebase, isComplete: conflictOperation() == nil))
    }

    public func continueOperation() async throws {
        guard let op = conflictOperation() else { return }

        eventSubject.send(.startContinuingOperation)

        switch op {
        case .merge:
            let result = try await commandRunner.run(.mergeContinue)
            guard result.exitCode == 0 else {
                throw GitError.mergeContinueFailed
            }
        case .cherryPick:
            let result = try await commandRunner.run(.cherryPickContinue)
            // Check for empty cherry-pick
            if result.exitCode != 0 && result.stderr.contains("now empty") {
                // Auto-skip empty cherry-picks
                let skipResult = try await commandRunner.run(.cherryPickSkip)
                guard skipResult.exitCode == 0 else {
                    throw GitError.cherryPickSkipFailed
                }
            } else if result.exitCode != 0 {
                throw GitError.cherryPickContinueFailed
            }
        case .revert:
            let result = try await commandRunner.run(.revertContinue)
            guard result.exitCode == 0 else {
                throw GitError.revertContinueFailed
            }
        case .rebase:
            let result = try await commandRunner.run(.rebaseContinue)
            guard result.exitCode == 0 else {
                throw GitError.rebaseContinueFailed
            }
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear {
            if case .commit = $0 { return true }
            return false
        }
        await workingTree.invalidateIndexCache()

        eventSubject.send(.operationContinued(operation: op, isComplete: conflictOperation() == nil))
    }
}

// MARK: - Private
private extension GitRepository {
    /// Read a file under `.git/rebase-merge/<name>` and return its trimmed
    /// non-empty contents. Used by both `rebaseHeadName` and `rebaseOnto`.
    func readRebaseMergeFile(named name: String) -> String? {
        let path = gitURL
            .appendingPathComponent(GitPath.rebaseMerge.rawValue)
            .appendingPathComponent(name)
        guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parse the first single-quoted token out of `.git/MERGE_MSG`. Git writes
    /// "Merge branch 'feature' into main" or "Merge remote-tracking branch
    /// 'origin/feature'" — we want the bare branch name in either case, so we
    /// also drop everything before the last `/`.
    func parseMergeMessageBranch() -> String? {
        let url = gitURL.appendingPathComponent(GitPath.mergeMsg.rawValue)
        guard let content = try? String(contentsOf: url, encoding: .utf8),
              let firstQuote = content.firstIndex(of: "'")
        else { return nil }
        let afterFirst = content.index(after: firstQuote)
        guard let secondQuote = content[afterFirst...].firstIndex(of: "'") else { return nil }
        let raw = String(content[afterFirst..<secondQuote])
        return raw.components(separatedBy: "/").last
    }

}
