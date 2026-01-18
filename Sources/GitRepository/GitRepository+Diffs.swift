import Foundation

extension GitRepository: DiffReadable {
    public func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk] {
        guard let commit = try await getCommit(commitId) else { return [] }

        guard let parentId = commit.parents.first else {
            let result = try await commandRunner.run(
                .showFile(commitId: commitId, path: path)
            )

            return await diffParser.parse(result.stdout)
        }

        let result = try await commandRunner.run(
            .diffCommits(from: parentId, to: commitId, path: path)
        )

        return await diffParser.parse(result.stdout)
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
