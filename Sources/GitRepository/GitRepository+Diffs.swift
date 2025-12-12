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

        let snapshot = try await getRepoSnapshot()
        
        let resolver = WorkingTreeDiffResolver(
            repoURL: url,
            blobLoader: self
        )
        
        let diffPair = try await resolver.resolveDiff(
            for: workingFile,
            headTree: snapshot.headTree,
            indexMap: snapshot.indexMap
        )

        return try await diffGenerator.generateHunks(
            oldContent: diffPair.old?.text ?? "",
            newContent: diffPair.new?.text ?? ""
        )
    }
    
    /// Get diff for staged changes (index vs HEAD)
    public func getStagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        let snapshot = try await getRepoSnapshot()
        
        // Get HEAD version
        let headContent: String
        if let headBlobHash = snapshot.headTree[workingFile.path] {
            headContent = try await getBlob(headBlobHash)?.text ?? ""
        } else {
            headContent = ""
        }
        
        // Get index version
        let indexContent: String
        if let indexEntry = snapshot.indexMap[workingFile.path] {
            indexContent = try await getBlob(indexEntry)?.text ?? ""
        } else {
            indexContent = ""
        }
        
        // Diff: HEAD → index (what's staged)
        return try await diffGenerator.generateHunks(
            oldContent: headContent,
            newContent: indexContent
        )
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
