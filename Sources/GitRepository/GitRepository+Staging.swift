import Foundation

extension GitRepository: StagingWritable {
    public func stageFile(at path: String) async throws {
        let status = try await getWorkingTreeStatus()

        var result: CommandResult
        if let file = status.files[path], case .renamed(let oldPath) = file.unstaged {
            result = try await commandRunner.run(.add(path: path))
            result = try await commandRunner.run(.add(path: oldPath))
        } else {
            result = try await commandRunner.run(.add(path: path))
        }

        guard result.exitCode == 0 else {
            throw GitError.stageFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.fileStaged(path: path))
    }

    public func stageAllFiles() async throws {
        let result = try await commandRunner.run(.addAll)

        guard result.exitCode == 0 else {
            throw GitError.stageAllFailed
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.allFilesStaged)
    }

    public func unstageFile(at path: String) async throws {
        let status = try await getWorkingTreeStatus()

        var result: CommandResult
        if let file = status.files[path], case .renamed(let oldPath) = file.staged {
            result = try await commandRunner.run(.reset(path: path))
            result = try await commandRunner.run(.reset(path: oldPath))
        } else {
            result = try await commandRunner.run(.reset(path: path))
        }

        guard result.exitCode == 0 else {
            throw GitError.unstageFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.fileUnstaged(path: path))
    }

    public func unstageAllFiles() async throws {
        let result = try await commandRunner.run(.resetAll)

        guard result.exitCode == 0 else {
            throw GitError.unstageAllFailed
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.allFilesUnstaged)
    }

    public func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        try await checkIndex(for: file)

        if file.unstaged == .untracked {
            throw GitError.cannotStageHunkFromUntrackedFile
        }

        let path = file.path
        let patch = patchGenerator.generatePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(patch: patch, cached: true)
        )

        guard result.exitCode == 0 else {
            throw GitError.stageHunkFailed(path: path)
        }

        await workingTree.invalidateIndexCache()

        eventSubject.send(.hunkStaged(hunk: hunk, path: path))
    }

    public func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        try await checkIndex(for: file)

        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(patch: patch, cached: true)
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
        // Get the staged diff for this specific file to check what's actually staged
        let result = try await commandRunner.run(
            .diff(path: path, staged: true, untracked: false, deleted: false)
        )

        guard result.exitCode == 0 else { return }

        // Parse the diff to see what changes are staged
        let hunks = await diffParser.parse(result.stdout)

        // Check if the only staged changes are trailing newline differences
        if isOnlyTrailingNewlineChanges(hunks) {
            // Only difference is trailing newlines - unstage the file
            try await commandRunner.run(.reset(path: path))
        }
    }

    func isOnlyTrailingNewlineChanges(_ hunks: [DiffHunk]) -> Bool {
        // If no hunks, no changes
        guard !hunks.isEmpty else { return false }

        // Check each hunk to see if it only contains trailing newline changes
        for hunk in hunks {
            var hasTrailingNewlineChange = false

            for line in hunk.lines {
                switch line.type {
                case .unchanged:
                    continue
                case .added, .removed:
                    let lineText = line.segments.map(\.text).joined()

                    // Check if this line is just whitespace/newlines
                    if lineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        hasTrailingNewlineChange = true
                    } else {
                        // If there's any content change, this isn't just trailing newlines
                        return false
                    }
                }
            }

            // If this hunk has no trailing newline changes, it's not what we're looking for
            if !hasTrailingNewlineChange {
                return false
            }
        }

        // All hunks were just trailing newline changes
        return true
    }
}
