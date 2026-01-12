import Foundation

extension GitRepository: StagingManageable {
    public func stageFile(at path: String) async throws {
        let result = try await commandRunner.run(.add(path: path), stdin: nil)

        guard result.exitCode == 0 else {
            throw GitError.stageFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.fileStaged(path: path))
    }

    public func stageAllFiles() async throws {
        let result = try await commandRunner.run(.addAll, stdin: nil)

        guard result.exitCode == 0 else {
            throw GitError.stageAllFailed
        }

        await workingTree.invalidateIndexCache()
    }

    public func unstageFile(at path: String) async throws {
        let result = try await commandRunner.run(.reset(path: path), stdin: nil)

        guard result.exitCode == 0 else {
            throw GitError.unstageFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.fileUnstaged(path: path))
    }

    public func unstageAllFiles() async throws {
        let result = try await commandRunner.run(.resetAll, stdin: nil)

        guard result.exitCode == 0 else {
            throw GitError.unstageAllFailed
        }

        await workingTree.invalidateIndexCache()
    }

    public func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        try await checkIndex(for: file)

        if file.unstaged == .untracked {
            throw GitError.cannotStageHunkFromUntrackedFile
        }

        // Save old blob SHA BEFORE staging
        let path = file.path
        let snapshot = try await workingTree.indexSnapshot()
        let entries = snapshot.entries
        let oldBlobSha = entries.first(where: { $0.path == path })?.sha1

        let patch = patchGenerator.generatePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(cached: true),
            stdin: patch
        )

        guard result.exitCode == 0 else {
            throw GitError.stageHunkFailed(path: path)
        }

        await workingTree.invalidateIndexCache()

        if let oldBlobSha {
            await cache.remove(.blob(hash: oldBlobSha))
        }
        eventSubject.send(.hunkStaged(hunk: hunk, path: path))
    }

    public func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        try await checkIndex(for: file)

        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(cached: true),
            stdin: patch
        )

        let path = file.path

        guard result.exitCode == 0 else {
            throw GitError.unstageHunkFailed(path: path)
        }

        await workingTree.invalidateIndexCache()

        try await cleanupTrailingNewlineChange(for: path)
        eventSubject.send(.hunkUnstaged(hunk: hunk, path: path))
    }
}

// MARK: - Private helper
private extension GitRepository {
    func checkIndex(for file: WorkingTreeFile) async throws {
        let snapshot = try await workingTree.indexSnapshot()
        let entries = snapshot.entries
        let fileInIndex = entries.contains { $0.path == file.path }

        if !fileInIndex {
            throw GitError.fileNotInIndex(path: file.path)
        }
    }

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
            try await commandRunner.run(.reset(path: path), stdin: nil)
        }
    }
}
