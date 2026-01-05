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
        
        let currentTree = try await getTreePaths(commit.tree)
        
        var parentTree: [String: String]? = nil
        if let parentId = commit.parents.first,
           let parentCommit = try await getCommit(parentId) {
            parentTree = try await getTreePaths(parentCommit.tree)
        }
        
        return try await diffCalculator.calculateDiff(
            currentTree: currentTree,
            parentTree: parentTree,
            blobLoader: { [weak self] blobHash in
                try await self?.getBlob(blobHash)
            }
        )
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
        // Validate message
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.emptyCommitMessage
        }
        
        // Check if there are staged changes
        let snapshot = try await getRepoSnapshot()
        let staged = try await workingTree.stagedChanges(snapshot: snapshot)
        guard !staged.isEmpty else {
            throw GitError.nothingToCommit
        }
        
        let result = try await commandRunner.run(
            .commit(message: message, author: nil),
            stdin: nil,
            in: url
        )
        
        guard result.exitCode == 0 else {
            throw GitError.commitFailed
        }

        // Invalidate cache (index is reset after commit)
        await invalidateAllCaches()
    }
}

// MARK: - Private helpers
private extension GitRepository {
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
