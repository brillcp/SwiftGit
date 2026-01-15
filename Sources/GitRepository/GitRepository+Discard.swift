import Foundation

extension GitRepository: DiscardWritable {
    public func discardFile(at path: String) async throws {
        let fileURL = url.appendingPathComponent(path)
        let indexSnapshot = try await workingTree.indexSnapshot()

        let isTracked = indexSnapshot.entriesByPath[path] != nil

        if isTracked {
            let result = try await commandRunner.run(.restore(path: path), stdin: nil)

            guard result.exitCode == 0 else {
                throw GitError.discardFileFailed(path: path)
            }
        } else {
            guard fileManager.fileExists(atPath: fileURL.path) else { return }
            try fileManager.removeItem(at: fileURL)
        }
        await workingTree.invalidateIndexCache()
        eventSubject.send(.fileDiscarded(path: path))
    }

    public func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)

        let result = try await commandRunner.run(
            .applyPatch(cached: false),
            stdin: patch
        )

        let path = file.path
        guard result.exitCode == 0 else {
            throw GitError.discardHunkFailed(path: path)
        }
        eventSubject.send(.hunkDiscarded(hunk: hunk, path: path))
    }

    public func discardAllFiles() async throws {
        let result = try await commandRunner.run(.resetHardHEAD, stdin: nil)

        guard result.exitCode == 0 else {
            throw GitError.discardAllFailed
        }

        try await commandRunner.run(.clean(force: true, directories: true), stdin: nil)

        await workingTree.invalidateIndexCache()
        eventSubject.send(.allFilesDiscarded)
    }

    public func discardUnstagedChanges() async throws {
        let restore = try await commandRunner.run(.restoreAll, stdin: nil)

        guard restore.exitCode == 0 else {
            throw GitError.restoreFailed
        }

        let clean = try await commandRunner.run(.clean(force: true, directories: true), stdin: nil)

        guard clean.exitCode == 0 else {
            throw GitError.cleanFailed
        }

        await workingTree.invalidateIndexCache()
        eventSubject.send(.allFilesDiscarded)
    }
}
