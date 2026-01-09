import Foundation

extension GitRepository: DiffReadable {
    public func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk] {
        guard let commit = try await getCommit(commitId) else { return [] }

        // Need a parent to diff against
        guard let parentId = commit.parents.first else {
            // No parent - this is the initial commit
            // Show the file as entirely added
            let result = try await commandRunner.run(
                .showFile(commitId: commitId, path: path),
                stdin: nil
            )

            return await diffParser.parse(result.stdout)
        }

        // Diff this commit against its parent
        let result = try await commandRunner.run(
            .diffCommits(from: parentId, to: commitId, path: path),
            stdin: nil
        )

        return await diffParser.parse(result.stdout)
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
        return hunks
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
        return hunks
    }
}
