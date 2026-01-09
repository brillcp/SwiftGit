import Foundation

extension GitRepository: DiffReadable {
    public func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk] {
        guard let commit = try await getCommit(commitId) else { return [] }

        let newBlob = try await getBlob(at: path, treeHash: commit.tree)

        var oldBlob: Blob? = nil
        if let parentId = commit.parents.first, let parentCommit = try await getCommit(parentId) {
            oldBlob = try await getBlob(at: path, treeHash: parentCommit.tree)
        }

        let diffPair = DiffPair(old: oldBlob, new: newBlob)

        return try await diffGenerator.generateHunks(
            oldContent: diffPair.old?.text ?? "",
            newContent: diffPair.new?.text ?? ""
        )
    }

    public func getFileDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        guard workingFile.unstaged != nil else { return [] }

        let result = try await commandRunner.run(
            .diff(path: workingFile.path, staged: false),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.diffFailed
        }

        let hunks = await diffParser.parse(result.stdout)
        return await diffParser.enhanceWithWordDiff(hunks)
    }

    /// Get diff for staged changes (index vs HEAD)
    public func getStagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        guard workingFile.staged != nil else { return [] }

        let result = try await commandRunner.run(
            .diff(path: workingFile.path, staged: true),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            throw GitError.diffFailed
        }

        let hunks = await diffParser.parse(result.stdout)
        return await diffParser.enhanceWithWordDiff(hunks)
    }
}

// MARK: - Private helpers
private extension GitRepository {
    func getBlob(at path: String, treeHash: String) async throws -> Blob? {
        let paths = try await getTreePaths(treeHash)
        guard let blobHash = paths[path] else { return nil }
        return try await getBlob(blobHash)
    }
}