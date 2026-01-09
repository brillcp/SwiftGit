import Foundation

extension GitRepository: CommitReadable {
    public func getCommit(_ hash: String) async throws -> Commit? {
        // Check cache first
        if let cached: Commit = await cache.get(.commit(hash: hash)) { return cached }

        // Load from storage
        guard let parsedObject = try await loadObject(hash: hash),
              case .commit(let commit) = parsedObject
        else { return nil }

        // Cache it
        await cache.set(.commit(hash: hash), value: commit)
        return commit
    }

    public func getAllCommits(limit: Int) async throws -> [Commit] {
        var streamedCommits = [Commit]()

        for try await commit in streamAllCommits(limit: limit) {
            streamedCommits.append(commit)
        }

        return streamedCommits.sorted { $0.author.timestamp < $1.author.timestamp }
    }

    public func getChangedFiles(_ commitId: String) async throws -> [String: CommitedFile] {
        guard let commit = try await getCommit(commitId) else { return [:] }

        // Use git diff-tree to get changed files
        let result = try await commandRunner.run(
            .diffTree(commitId: commitId),
            stdin: nil
        )

        return try await parseChangedFiles(result.stdout, commit: commit)
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
            .commit(message: message, author: nil),
            stdin: nil
        )

        guard result.exitCode == 0 else {
            // Check if it's "nothing to commit"
            let output = result.stderr + result.stdout
            if output.contains("nothing to commit") ||
               output.contains("no changes added to commit") {
                throw GitError.nothingToCommit
            }
            throw GitError.commitFailed
        }

        await invalidateAllCaches()
    }
}

// MARK: - Private helpers
private extension GitRepository {
    func parseChangedFiles(_ output: String, commit: Commit) async throws -> [String: CommitedFile] {
        var files: [String: CommitedFile] = [:]

        let lines = output.split(separator: "\n")

        for line in lines {
            // Format: :100644 100644 hash1 hash2 M\tpath
            // or for renames: :100644 100644 hash1 hash2 R100\told\tnew
            let parts = line.split(separator: "\t")
            guard parts.count >= 2 else { continue }

            let statusPart = parts[0].split(separator: " ").last ?? ""
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

                if let blob = blob {
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

    func streamAllCommits(limit: Int) -> AsyncThrowingStream<Commit, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get all refs
                    let refMap = try await refReader.getRefs()
                    let allRefs = refMap.values.flatMap { $0 }

                    // Filter based on options
                    var startingRefs = allRefs.filter { ref in
                        switch ref.type {
                        case .stash: false
                        default: true
                        }
                    }

                    var stashInternalCommits = Set<String>()  // Track commits to hide
                    let stashes = try await getStashes()
                    for stash in stashes {
                        // Add stash commit
                        startingRefs.append(
                            GitRef(
                                name: stash.message,
                                hash: stash.id,
                                type: .stash
                            )
                        )

                        // Track its internal commits (don't show these)
                        if let stashCommit = try await getCommit(stash.id) {
                            if stashCommit.parents.count >= 2 {
                                stashInternalCommits.insert(stashCommit.parents[1])
                            }
                            if stashCommit.parents.count >= 3 {
                                stashInternalCommits.insert(stashCommit.parents[2])
                            }
                        }
                    }

                    // If no refs, try HEAD
                    if startingRefs.isEmpty {
                        if let head = try await getHEAD() {
                            if let commit = try await getCommit(head) {
                                continuation.yield(commit)
                            }
                            continuation.finish()
                            return
                        } else {
                            continuation.finish()
                            return
                        }
                    }

                    var visited = Set<String>()
                    var queue: [String] = []
                    var count = 0

                    // Start from all branch/tag/stash heads
                    for ref in startingRefs {
                        queue.append(ref.hash)
                    }

                    // BFS traversal
                    while let commitHash = queue.popLast() {
                        // Check limit
                        if count >= limit {
                            break
                        }

                        // Skip if already visited
                        guard !visited.contains(commitHash) else {
                            continue
                        }
                        visited.insert(commitHash)

                        // Load commit
                        guard let commit = try await getCommit(commitHash) else {
                            continue
                        }

                        // Skip internal stash commits
                        if stashInternalCommits.contains(commit.id) {
                            continue
                        }

                        // Yield commit to stream
                        continuation.yield(commit)
                        count += 1

                        // Add parents to queue
                        queue.insert(contentsOf: commit.parents, at: 0)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
