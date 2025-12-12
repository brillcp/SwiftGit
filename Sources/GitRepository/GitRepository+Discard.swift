import Foundation

extension GitRepository: DiscardManageable {
    public func discardFile(at path: String) async throws {
        // Get file status
        let unstagedChanges = try await workingTree.unstagedChanges()
        guard let file = unstagedChanges[path] else {
            return // File doesn't exist
        }
        
        if file.unstaged == .untracked {
            // Untracked file - delete from filesystem
            let fileURL = url.appendingPathComponent(path)
            try fileManager.removeItem(at: fileURL)
        } else {
            // Tracked file - restore from index/HEAD
            try await commandRunner.run(.restore(path: path), stdin: nil, in: url)
        }
        await workingTree.invalidateIndexCache()
    }

    public func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)
        
        try await commandRunner.run(
            .applyPatch(cached: false),
            stdin: patch,
            in: url
        )
    }

    public func discardAllFiles() async throws {
        try await commandRunner.run(.restoreAll, stdin: nil, in: url)
    }
}
