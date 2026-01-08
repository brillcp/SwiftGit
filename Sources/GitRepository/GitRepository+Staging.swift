import Foundation

extension GitRepository: StagingManageable {
    public func stageFile(at path: String) async throws {
        let result = try await commandRunner.run(.add(path: path), stdin: nil, in: url)

        guard result.exitCode == 0 else {
            throw GitError.stageFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
    }

    public func stageAllFiles() async throws {
        let result = try await commandRunner.run(.addAll, stdin: nil, in: url)

        guard result.exitCode == 0 else {
            throw GitError.stageAllFailed
        }

        await workingTree.invalidateIndexCache()
    }

    public func unstageFile(at path: String) async throws {
        let result = try await commandRunner.run(.reset(path: path), stdin: nil, in: url)

        guard result.exitCode == 0 else {
            throw GitError.unstageFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
    }

    public func unstageAllFiles() async throws {
        let result = try await commandRunner.run(.resetAll, stdin: nil, in: url)

        guard result.exitCode == 0 else {
            throw GitError.unstageAllFailed
        }

        await workingTree.invalidateIndexCache()
    }

    public func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        // Check if file is in index
        let snapshot = try await workingTree.indexSnapshot()
        let entries = snapshot.entries
        let fileInIndex = entries.contains { $0.path == file.path }

        if !fileInIndex {
            throw GitError.fileNotInIndex(path: file.path)
        }

        if file.unstaged == .untracked {
            throw GitError.cannotStageHunkFromUntrackedFile
        }

        // Save old blob SHA BEFORE staging
        let oldBlobSha = entries.first(where: { $0.path == file.path })?.sha1

        let patch = patchGenerator.generatePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(cached: true),
            stdin: patch,
            in: url
        )

        guard result.exitCode == 0 else {
            throw GitError.stageHunkFailed(path: file.path)
        }

        await workingTree.invalidateIndexCache()

        if let oldBlobSha {
            await cache.remove(.blob(hash: oldBlobSha))
        }
    }

    public func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        // Validation
        let snapshot = try await workingTree.indexSnapshot()
        let entries = snapshot.entries
        let fileInIndex = entries.contains { $0.path == file.path }

        if !fileInIndex {
            throw GitError.fileNotInIndex(path: file.path)
        }

        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(cached: true),
            stdin: patch,
            in: url
        )

        guard result.exitCode == 0 else {
            throw GitError.unstageHunkFailed(path: file.path)
        }

        await workingTree.invalidateIndexCache()

        try await cleanupTrailingNewlineChange(for: file.path)
    }
}

// MARK: - Private helper
private extension GitRepository {
    func cleanupTrailingNewlineChange(for path: String) async throws {
        let snapshot = try await getRepoSnapshot()

        guard let blobHash = snapshot.headTree[path],
              let headBlob = try await getBlob(blobHash) else {
            return
        }

        // Get INDEX content
        guard let indexEntry = snapshot.indexMap[path],
              let indexBlob = try await getBlob(indexEntry)
        else { return }

        let headContent = headBlob.text
        let indexContent = indexBlob.text

        // Check if only difference is trailing newline
        let headTrimmed = headContent?.trimmingCharacters(in: .newlines)
        let indexTrimmed = indexContent?.trimmingCharacters(in: .newlines)

        if headTrimmed == indexTrimmed && headContent != indexContent {
            // Only difference is trailing newlines - unstage it
            try await commandRunner.run(.reset(path: path), stdin: nil, in: url)
        }
    }
}