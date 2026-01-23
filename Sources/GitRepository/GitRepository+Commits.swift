import Foundation

extension GitRepository: CommitReadable {
    public func getCommit(_ hash: String) async throws -> Commit? {
        let result = try await commandRunner.run(.showCommit(hash: hash))

        guard result.exitCode == 0 else {
            throw GitError.commitNotFound
        }

        let line = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return try Commit.parse(from: line)
    }

    public func getAllCommits(limit: Int) async throws -> [Commit] {
        try await commandRunner.streamCommits(limit: limit).reduce(into: [Commit]()) { $0.append($1) }
    }

    public func getCommittedFiles(_ commitId: String) async throws -> [String: CommittedFile] {
        let result = try await commandRunner.run(
            .diffTree(commitId: commitId)
        )

        guard result.exitCode == 0 else {
            throw GitError.getCommittedFilesFailed
        }

        return await workingTreeParser.parseFilesNullDelimited(result.stdout)
    }

    public func getStashedFiles(_ stashId: String) async throws -> [String: CommittedFile] {
        let result = try await commandRunner.run(
            .stashShow(ref: stashId)
        )

        guard result.exitCode == 0 else {
            throw GitError.diffFailed
        }

        return await workingTreeParser.parseFilesNewlineDelimited(result.stdout)
    }

    public func getHEAD() async throws -> String? {
        try await refReader.getHEAD()
    }

    public func getHEADBranch() async throws -> String? {
        try await refReader.getHEADBranch()
    }
}

// MARK: - CommitWritable
extension GitRepository: CommitWritable {
    public func commit(message: String) async throws {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.emptyCommitMessage
        }

        let result = try await commandRunner.run(
            .commit(message: message, author: nil)
        )

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout
            if output.contains("nothing to commit") ||
               output.contains("no changes added to commit") {
                throw GitError.nothingToCommit
            }
            throw GitError.commitFailed
        }

        await cache.remove(.head)
        await workingTree.invalidateIndexCache()

        let hash = try await getHEAD() ?? ""
        eventSubject.send(.committed(hash: hash))
    }
}
