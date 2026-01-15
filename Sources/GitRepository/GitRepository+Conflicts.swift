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
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.mergeHead.rawValue).path) {
            try await commandRunner.run(.mergeAbort, stdin: nil)
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue).path) {
            try await commandRunner.run(.cherryPickAbort, stdin: nil)
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.revertHead.rawValue).path) {
            try await commandRunner.run(.revertAbort, stdin: nil)
        }

        await invalidateAllCaches()
    }
}
