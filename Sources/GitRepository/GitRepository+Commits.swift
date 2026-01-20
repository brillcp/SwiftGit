import Foundation

extension GitRepository: CommitReadable {
    public func getCommit(_ hash: String) async throws -> Commit? {
        if let cached: Commit = await cache.get(.commit(hash: hash)) { return cached }

        guard let parsedObject = try await loadObject(hash: hash),
              case .commit(let commit) = parsedObject
        else { return nil }

        await cache.set(.commit(hash: hash), value: commit)
        return commit
    }

    public func getAllCommits(limit: Int) async throws -> [Commit] {
        try await commandRunner.streamCommits(limit: limit).reduce(into: [Commit]()) { $0.append($1) }
    }

    public func getCommittedFiles(_ commitId: String) async throws -> [String: CommitedFile] {
        guard let commit = try await getCommit(commitId) else { return [:] }

        let result = try await commandRunner.run(
            .diffTree(commitId: commitId)
        )

        guard result.exitCode == 0 else {
            throw GitError.getCommittedFilesFailed
        }

        return try await parseChangedFiles(result.stdout, commit: commit)
    }

    public func getStashedFiles(_ stashId: String) async throws -> [String: CommitedFile] {
        guard let stashCommit = try await getCommit(stashId) else { return [:] }

        let result = try await commandRunner.run(
            .stashShow(ref: stashId)
        )

        guard result.exitCode == 0 else {
            throw GitError.diffFailed
        }

        return try await parseChangedFiles(result.stdout, commit: stashCommit)
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

        await invalidateAllCaches()

        let hash = try await getHEAD() ?? ""
        eventSubject.send(.committed(hash: hash))
    }
}

// MARK: - Private helpers
private extension GitRepository {
    func parseChangedFiles(_ output: String, commit: Commit) async throws -> [String: CommitedFile] {
        var files: [String: CommitedFile] = [:]

        let lines = output.split(separator: String.newLine)

        for line in lines {
            // Format: :100644 100644 hash1 hash2 M\tpath
            // or for renames: :100644 100644 hash1 hash2 R100\told\tnew
            let parts = line.split(separator: String.tab)
            guard parts.count >= 2 else { continue }

            let statusPart = parts[0].split(separator: String.space).last ?? ""
            let status = String(statusPart)

            if status.hasPrefix("R") {
                // Rename: old path and new path
                guard parts.count >= 3 else { continue }
                let oldPath = String(parts[1])
                let newPath = String(parts[2])

                files[newPath] = CommitedFile(
                    path: newPath,
                    changeType: .renamed(from: oldPath)
                )
            } else {
                let path = String(parts[1])
                let changeType: GitChangeType

                switch status {
                case "A": changeType = .added
                case "M": changeType = .modified
                case "D": changeType = .deleted
                default: continue
                }

                files[path] = CommitedFile(path: path, changeType: changeType)
            }
        }

        return files
    }
}
