import Foundation

extension GitRepository: DiscardManageable {
    public func discardFile(at path: String) async throws {
        let fileURL = url.appendingPathComponent(path)
        let indexSnapshot = try await workingTree.indexSnapshot()
        
        // Check if file is in the index (tracked)
        let isTracked = indexSnapshot.entriesByPath[path] != nil
        
        if isTracked {
            // Tracked file - restore from index/HEAD
            let result = try await commandRunner.run(.restore(path: path), stdin: nil, in: url)
            
            guard result.exitCode == 0 else {
                throw GitError.discardFileFailed(path: path)
            }
        } else {
            // Untracked file - delete from filesystem
            guard fileManager.fileExists(atPath: fileURL.path) else {
                return // Already gone
            }
            try fileManager.removeItem(at: fileURL)
        }
        await workingTree.invalidateIndexCache()
    }

    public func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)
        
        let result = try await commandRunner.run(
            .applyPatch(cached: false),
            stdin: patch,
            in: url
        )

        guard result.exitCode == 0 else {
            throw GitError.discardHunkFailed(path: file.path)
        }
    }

    public func discardAllFiles() async throws {
        // Reset tracked files and staged changes to HEAD
        let result = try await commandRunner.run(.resetHardHEAD, stdin: nil, in: url)

        guard result.exitCode == 0 else {
            throw GitError.discardAllFailed
        }

        // Remove untracked files and directories
        try await commandRunner.run(.clean(force: true, directories: true), stdin: nil, in: url)

        // Invalidate caches after mutations
        await workingTree.invalidateIndexCache()
    }

    /// Discard all unstaged changes and remove all untracked files/directories, preserving staged changes
    public func discardUnstagedAndUntracked() async throws {
        // Revert unstaged changes in tracked files
        try await commandRunner.run(.restoreAll, stdin: nil, in: url)

        // Remove untracked files and directories
        try await commandRunner.run(.clean(force: true, directories: true), stdin: nil, in: url)

        // Invalidate caches after mutations
        await workingTree.invalidateIndexCache()
    }
}
