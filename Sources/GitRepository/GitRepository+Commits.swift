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
        let result = try await commandRunner.run(
            .log(limit: limit)
        )

        guard result.exitCode == 0 else {
            throw GitError.logFailed
        }

        return try parseLogOutput(result.stdout)
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
    func parseLogOutput(_ output: String) throws -> [Commit] {
        let commitBlocks = output
            .components(separatedBy: "---END---")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var commits: [Commit] = []

        for block in commitBlocks {
            let lines = block.split(separator: String.newLine, omittingEmptySubsequences: false)
            guard lines.count >= 10 else { continue }

            let hash = String(lines[0])
            let parents = String(lines[1]).split(separator: String.space).map(String.init)
            let tree = String(lines[2])
            let authorName = String(lines[3])
            let authorEmail = String(lines[4])
            let authorTimestamp = Date(timeIntervalSince1970: Double(lines[5]) ?? 0)
            let committerName = String(lines[6])
            let committerEmail = String(lines[7])
            let committerTimestamp = Date(timeIntervalSince1970: Double(lines[8]) ?? 0)
            let title = String(lines[9])
            let body = lines[10...].joined(separator: String.newLine)

            commits.append(
                Commit(
                    id: hash,
                    title: title,
                    body: body,
                    author: Author(name: authorName, email: authorEmail, timestamp: authorTimestamp, timezone: ""),
                    committer: Author(name: committerName, email: committerEmail, timestamp: committerTimestamp, timezone: ""),
                    parents: parents,
                    tree: tree
                )
            )
        }

        return commits
    }

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

                // Get new blob
                let newBlob = try await getBlob(at: newPath, treeHash: commit.tree)
                if let blob = newBlob {
                    files[newPath] = CommitedFile(
                        path: newPath,
                        blob: blob,
                        changeType: .renamed(from: oldPath)
                    )
                }
            } else {
                let path = String(parts[1])
                let changeType: GitChangeType

                switch status {
                case "A": changeType = .added
                case "M": changeType = .modified
                case "D": changeType = .deleted
                default: continue
                }

                // Load blob (nil for deleted files)
                let blob: Blob?
                if changeType == .deleted {
                    // Load from parent tree
                    if let parentId = commit.parents.first,
                       let parentCommit = try await getCommit(parentId) {
                        blob = try await getBlob(at: path, treeHash: parentCommit.tree)
                    } else {
                        blob = nil
                    }
                } else {
                    blob = try await getBlob(at: path, treeHash: commit.tree)
                }

                if let blob {
                    files[path] = CommitedFile(path: path, blob: blob, changeType: changeType)
                }
            }
        }

        return files
    }

    func getBlob(at path: String, treeHash: String) async throws -> Blob? {
        let paths = try await getTreePaths(treeHash)
        guard let blobHash = paths[path] else { return nil }
        return try await getBlob(blobHash)
    }
}
