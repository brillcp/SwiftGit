import Foundation

extension GitRepository: ConflictManageable {
    /// Check if repository is in a conflicted state
    public func hasConflicts() async throws -> Bool {
        let gitURL = url.appendingPathComponent(".git")

        // Check for merge/cherry-pick/revert in progress
        let mergeHead = gitURL.appendingPathComponent("MERGE_HEAD")
        let cherryPickHead = gitURL.appendingPathComponent("CHERRY_PICK_HEAD")
        let revertHead = gitURL.appendingPathComponent("REVERT_HEAD")

        return fileManager.fileExists(atPath: mergeHead.path) ||
               fileManager.fileExists(atPath: cherryPickHead.path) ||
               fileManager.fileExists(atPath: revertHead.path)
    }

    /// Get list of conflicted file paths
    public func getConflictedFiles() async throws -> [String] {
        try await getRepoSnapshot().conflictedPaths
    }

    /// Get the type of operation causing conflicts
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

    /// Abort current operation (merge/cherry-pick/revert)
    public func abortOperation() async throws {        
        if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.mergeHead.rawValue).path) {
            try await commandRunner.run(.mergeAbort, stdin: nil, in: url)
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.cherryPickHead.rawValue).path) {
            try await commandRunner.run(.cherryPickAbort, stdin: nil, in: url)
        } else if fileManager.fileExists(atPath: gitURL.appendingPathComponent(GitPath.revertHead.rawValue).path) {
            try await commandRunner.run(.revertAbort, stdin: nil, in: url)
        }

        await invalidateAllCaches()
    }
}