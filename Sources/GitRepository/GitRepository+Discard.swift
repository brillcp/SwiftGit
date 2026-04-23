import Foundation

extension GitRepository: DiscardWritable {
    public func discardFile(at path: String) async throws {
        let status = try await getWorkingTreeStatus()

        // Check if this is a renamed file
        if let file = status.files[path],
           case .renamed(let oldPath) = file.unstaged {
            // Discard rename: remove new file, restore old file
            let newFileURL = url.appendingPathComponent(path)
            if fileManager.fileExists(atPath: newFileURL.path) {
                try fileManager.removeItem(at: newFileURL)
            }

            // Restore old file from index
            let result = try await commandRunner.run(.restore(path: oldPath))
            guard result.exitCode == 0 else {
                throw GitError.discardFileFailed(path: oldPath)
            }
        } else {
            // Normal discard logic
            let fileURL = url.appendingPathComponent(path)
            let indexSnapshot = try await workingTree.indexSnapshot()
            let isTracked = indexSnapshot.entriesByPath[path] != nil

            if isTracked {
                let result = try await commandRunner.run(.restore(path: path))
                guard result.exitCode == 0 else {
                    throw GitError.discardFileFailed(path: path)
                }
            } else {
                guard fileManager.fileExists(atPath: fileURL.path) else { return }
                try fileManager.removeItem(at: fileURL)
            }
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.fileDiscarded(path: path))
    }

    public func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(patch: patch, cached: false)
        )

        let path = file.path
        guard result.exitCode == 0 else {
            throw GitError.discardHunkFailed(path: path)
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.hunkDiscarded(hunk: hunk, path: path))
    }

    public func discardAllFiles() async throws {
        let result = try await commandRunner.run(.resetHardHEAD)

        guard result.exitCode == 0 else {
            throw GitError.discardAllFailed
        }

        try await commandRunner.run(.clean(force: true, directories: true))

        await workingTree.invalidateIndexCache()
        eventSubject.send(.allFilesDiscarded)
    }

    public func discardUnstagedChanges() async throws {
        let restore = try await commandRunner.run(.restoreAll)

        guard restore.exitCode == 0 else {
            throw GitError.restoreFailed
        }

        let clean = try await commandRunner.run(.clean(force: true, directories: true))

        guard clean.exitCode == 0 else {
            throw GitError.cleanFailed
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.allFilesDiscarded)
    }
}
