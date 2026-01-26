import Foundation

extension GitRepository: DiffReadable {
    public func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk] {
        let cacheKey = CacheKey.fileDiff(commitId: commitId, path: path)
        if let cached: [DiffHunk] = await cache.get(cacheKey) {
            return cached
        }

        guard let commit = try await getCommit(commitId) else { return [] }

        let hunks = try await fetchFileDiff(for: commit, at: path)

        if !hunks.isEmpty {
            await cache.set(cacheKey, value: hunks)
        }

        return hunks
    }

    public func getUnstagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        guard workingFile.unstaged != nil else { return [] }

        let isUntracked = workingFile.unstaged == .untracked
        let isDeleted = workingFile.unstaged == .deleted

        let result = try await commandRunner.run(
            .diff(path: workingFile.path, staged: false, untracked: isUntracked, deleted: isDeleted)
        )

        guard result.exitCode == 0 || (isUntracked && result.exitCode == 1) else {
            throw GitError.diffFailed
        }

        let hunks = await diffParser.parse(result.stdout)
        return hunks
    }

    public func getStagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        guard workingFile.staged != nil else { return [] }

        let result = try await commandRunner.run(
            .diff(path: workingFile.path, staged: true, untracked: false, deleted: workingFile.staged == .deleted)
        )

        guard result.exitCode == 0 else {
            throw GitError.diffFailed
        }

        let hunks = await diffParser.parse(result.stdout)
        return hunks
    }

    public func getRawStagedDiff() async throws -> String {
        let result = try await commandRunner.run(
            .diff(path: ".", staged: true, untracked: false, deleted: false)
        )

        guard result.exitCode == 0 else {
            throw GitError.diffFailed
        }

        return result.stdout
    }

    public func getFileContent(at path: String, ref: String) async throws -> String {
        let result = try await commandRunner.run(
            .showFile(commitId: ref, path: path)
        )

        guard result.exitCode == 0 else {
            if result.stderr.contains("does not exist") || result.stderr.contains("unknown revision") {
                throw GitError.fileNotFound(path: path, ref: ref)
            }
            throw GitError.getFileContentFailed(path: path, ref: ref)
        }

        return result.stdout
    }
}

// MARK: - Private functions
private extension GitRepository {
    func fetchFileDiff(for commit: Commit, at path: String) async throws -> [DiffHunk] {
        // Stash commits have 3 parents (HEAD, index, untracked)
        if commit.parents.count == 3 {
            // Try regular diff first (for tracked files in stash)
            let parentId = commit.parents[0]
            let result = try await commandRunner.run(.diffCommits(from: parentId, to: commit.id, path: path))

            if !result.stdout.isEmpty {
                return await diffParser.parse(result.stdout)
            }

            // Fall back to untracked file diff
            return try await getDiffForUntrackedStashFile(commitId: commit.id, path: path)
        }

        // Merge commits have 2 parents
        if commit.parents.count == 2 {
            return try await getDiffForMergeCommit(commitId: commit.id, path: path)
        }

        // Regular commits have 1 parent
        guard let parentId = commit.parents.first else { return [] }
        return try await getDiffForRegularCommit(commitId: commit.id, parentId: parentId, path: path)
    }

    func getDiffForInitialCommit(commitId: String, path: String) async throws -> [DiffHunk] {
        let result = try await commandRunner.run(.showFile(commitId: commitId, path: path))
        return await diffParser.parse(result.stdout)
    }

    func getDiffForMergeCommit(commitId: String, path: String) async throws -> [DiffHunk] {
        let result = try await commandRunner.run(.showFileDiff(commitId: commitId, path: path))
        return await diffParser.parse(result.stdout)
    }

    func getDiffForRegularCommit(commitId: String, parentId: String, path: String) async throws -> [DiffHunk] {
        let result = try await commandRunner.run(.diffCommits(from: parentId, to: commitId, path: path))

        if result.stdout.isEmpty {
            return try await getDiffForUntrackedStashFile(commitId: commitId, path: path)
        }

        return await diffParser.parse(result.stdout)
    }

    func getDiffForUntrackedStashFile(commitId: String, path: String) async throws -> [DiffHunk] {
        guard let commit = try await getCommit(commitId), commit.parents.count >= 3 else {
            return []
        }

        let untrackedParent = commit.parents[2]
        let result = try await commandRunner.run(.diffFromEmpty(to: untrackedParent, path: path))

        guard result.exitCode == 0 else { return [] }
        return await diffParser.parse(result.stdout)
    }
}
