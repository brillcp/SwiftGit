import Foundation

public protocol GitRepositoryProtocol: Actor {
    /// Repository URL
    var url: URL { get }
    
    /// Get a commit by hash (lazy loaded)
    func getCommit(_ hash: String) async throws -> Commit?
    
    func getAllCommits(limit: Int?) async throws -> [Commit]

    func streamCommits(
        from startCommit: String,
        limit: Int?
    ) -> AsyncThrowingStream<Commit, Error>

    /// Get changed files for a commit
    func getChangedFiles(_ commitId: String) async throws -> [String: CommitedFile]

    func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk]
    func getFileDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk]

    /// Get a tree by hash (lazy loaded)
    func getTree(_ hash: String) async throws -> Tree?
    
    /// Get a blob by hash (lazy loaded)
    func getBlob(_ hash: String) async throws -> Blob?
    
    /// Stream a large blob without loading entirely into memory
    func streamBlob(_ hash: String) -> AsyncThrowingStream<Data, Error>
    
    func getWorkingTreeStatus() async throws -> WorkingTreeStatus?
    func getStagedChanges() async throws -> [String: WorkingTreeFile]
    func getUnstagedChanges() async throws -> [String: WorkingTreeFile]
    func getUntrackedFiles() async throws -> [String]

    /// Walk a tree recursively, calling visitor for each entry
    /// Visitor returns true to continue, false to stop
    func walkTree(_ treeHash: String, visitor: (Tree.Entry) async throws -> Bool) async throws
    
    /// Get all file paths in a tree (flattened)
    func getTreePaths(_ treeHash: String) async throws -> [String: String] // path -> blob hash
    
    /// Get all refs (branches, tags, etc.)
    func getRefs() async throws -> [GitRef]
    
    /// Get current HEAD commit hash
    func getHEAD() async throws -> String?
    
    /// Get HEAD branch name (nil if detached)
    func getHEADBranch() async throws -> String?
    
    func getBranches() async throws -> Branches

    func getStashes() async throws -> [Stash]
    
    /// Get commit history starting from a commit
    func getHistory(from commitHash: String, limit: Int?) async throws -> [Commit]
    
    /// Check if an object exists (without loading it)
    func objectExists(_ hash: String) async throws -> Bool
    
    func enumerateObjects(_ visitor: @Sendable (String) async throws -> Bool) async throws
}

// MARK: -
public actor GitRepository {
    private let cache: ObjectCacheProtocol
    private let locator: ObjectLocatorProtocol
    private let looseParser: LooseObjectParserProtocol
    private let packReader: PackFileReaderProtocol
    private let diffCalculator: DiffCalculatorProtocol
    private let diffGenerator: DiffGeneratorProtocol
    private let refReader: RefReaderProtocol
    private let workingTree: WorkingTreeReaderProtocol
    
    private var securityScopeStarted: Bool = false
    private let fileManager: FileManager

    public let url: URL

    public init(
        url: URL,
        cache: ObjectCacheProtocol = ObjectCache(),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.cache = cache
        self.locator = ObjectLocator(
            repoURL: url,
            packIndexManager: PackIndexManager(repoURL: url)
        )
        self.looseParser = LooseObjectParser()
        self.packReader = PackFileReader()
        self.diffCalculator = DiffCalculator()
        self.diffGenerator = DiffGenerator()
        self.refReader = RefReader(
            repoURL: url,
            cache: cache
        )
        self.workingTree = WorkingTreeReader(
            repoURL: url,
            indexReader: GitIndexReader(cache: cache),
            cache: cache
        )
        self.fileManager = fileManager
        self.securityScopeStarted = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if securityScopeStarted {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

// MARK: - GitRepositoryProtocol
extension GitRepository: GitRepositoryProtocol {
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

    /// Get commits from all branches as an array (convenience method)
    public func getAllCommits(limit: Int? = nil) async throws -> [Commit] {
        var commits = [Commit]()
        
        for try await commit in streamAllCommits(limit: limit) {
            commits.append(commit)
        }
        
        // Sort by date (most recent first)
        commits.sort { $0.author.timestamp > $1.author.timestamp }
        return commits
    }

    public func streamCommits(
        from startCommit: String,
        limit: Int? = nil
    ) -> AsyncThrowingStream<Commit, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var visited = Set<String>()
                    var queue = [startCommit]
                    var count = 0
                    
                    while let commitHash = queue.popLast() {
                        // Check limit
                        if let limit, count >= limit {
                            break
                        }
                        
                        // Skip if already visited (handles merge commits)
                        guard !visited.contains(commitHash) else {
                            continue
                        }
                        visited.insert(commitHash)
                        
                        // Load commit
                        guard let commit = try await getCommit(commitHash) else {
                            continue
                        }
                        
                        // Yield commit to stream
                        continuation.yield(commit)
                        count += 1
                        
                        // Add parents to queue (BFS for chronological order)
                        queue.insert(contentsOf: commit.parents, at: 0)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Get changed files for a commit
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

    public func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk] {
        guard let commit = try await getCommit(commitId) else { return [] }
        
        let newBlob = try await getBlob(at: path, treeHash: commit.tree)

        var oldBlob: Blob? = nil
        if let parentId = commit.parents.first, let parentCommit = try await getCommit(parentId) {
            oldBlob = try await getBlob(at: path, treeHash: parentCommit.tree)
        }
        
        let diffPair = DiffPair(old: oldBlob, new: newBlob)
        
        return try await diffGenerator.generateHunks(
            oldContent: diffPair.old?.text ?? "",
            newContent: diffPair.new?.text ?? ""
        )
    }

    public func getFileDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        guard let head = try await getHEAD(),
              let commit = try await getCommit(head)
        else { return [] }
        
        let headTree = try await getTreePaths(commit.tree)
        let snapshot = try await workingTree.readIndex()
        let indexMap = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.path, $0.sha1) })
        
        let resolver = WorkingTreeDiffResolver(
            repoURL: url,
            blobLoader: self
        )
        
        let diffPair = try await resolver.resolveDiff(
            for: workingFile,
            headTree: headTree,
            indexMap: indexMap
        )
        return try await diffGenerator.generateHunks(
            oldContent: diffPair.old?.text ?? "",
            newContent: diffPair.new?.text ?? ""
        )
    }

    public func getTree(_ hash: String) async throws -> Tree? {
        // Check cache
        if let cached: Tree = await cache.get(.tree(hash: hash)) { return cached }
        
        // Load from storage
        guard let parsedObject = try await loadObject(hash: hash),
              case .tree(let tree) = parsedObject
        else { return nil }
        
        // Cache it
        await cache.set(.tree(hash: hash), value: tree)
        return tree
    }
    
    public func getBlob(_ hash: String) async throws -> Blob? {
        // Check cache (only cache small blobs)
        if let cached: Blob = await cache.get(.blob(hash: hash)) { return cached }
        
        // Load from storage
        guard let parsedObject = try await loadObject(hash: hash),
              case .blob(let blob) = parsedObject
        else { return nil }
        
        // Cache only if < 100KB
        if blob.data.count < 100_000 {
            await cache.set(.blob(hash: hash), value: blob)
        }
        
        return blob
    }
    
    public func streamBlob(_ hash: String) -> AsyncThrowingStream<Data, any Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // For now, just load the whole blob and stream it in chunks
                    // TODO: Implement true streaming for large blobs
                    guard let blob = try await getBlob(hash) else {
                        continuation.finish(throwing: RepositoryError.objectNotFound(hash))
                        return
                    }
                    
                    let chunkSize = 8192
                    var offset = 0
                    
                    while offset < blob.data.count {
                        let end = min(offset + chunkSize, blob.data.count)
                        let chunk = blob.data[offset..<end]
                        continuation.yield(Data(chunk))
                        offset = end
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    public func getWorkingTreeStatus() async throws -> WorkingTreeStatus? {
        guard let head = try await getHEAD(),
              let commit = try await getCommit(head)
        else { return nil }
        
        let headTree = try await getTreePaths(commit.tree)
        return try await workingTree.computeStatus(headTree: headTree)
    }

    /// Get only staged changes (HEAD → Index)
    public func getStagedChanges() async throws -> [String: WorkingTreeFile] {
        guard let head = try await getHEAD(),
              let commit = try await getCommit(head)
        else { return [:] }
        
        let headTree = try await getTreePaths(commit.tree)
        return try await workingTree.stagedChanges(headTree: headTree)
    }
    
    /// Get only unstaged changes (Index → Working Tree)
    public func getUnstagedChanges() async throws -> [String: WorkingTreeFile] {
        try await workingTree.unstagedChanges()
    }
    
    /// Get only untracked files
    public func getUntrackedFiles() async throws -> [String] {
        try await workingTree.untrackedFiles()
    }

    public func walkTree(_ treeHash: String, visitor: (Tree.Entry) async throws -> Bool) async throws {
        try await walkTreeRecursive(treeHash: treeHash, currentPath: "", visitor: visitor)
    }
    
    public func getTreePaths(_ treeHash: String) async throws -> [String : String] {
        // Check cache
        if let cached: [String: String] = await cache.get(.treePaths(hash: treeHash)) { return cached }
        
        var paths: [String: String] = [:]
        
        try await walkTree(treeHash) { entry in
            if entry.type == .blob {
                paths[entry.path] = entry.hash
            }
            return true
        }
        
        // Cache the result
        await cache.set(.treePaths(hash: treeHash), value: paths)
        return paths
    }
    
    // MARK: - References
    public func getRefs() async throws -> [GitRef] {
        try await refReader.getRefs()
    }
    
    public func getHEAD() async throws -> String? {
        try await refReader.getHEAD()
    }
        
    public func getHEADBranch() async throws -> String? {
        try await refReader.getHEADBranch()
    }
    
    public func getBranches() async throws -> Branches {
        let allRefs = try await getRefs()
        
        return Branches(
            local: allRefs.filter { $0.type == .localBranch },
            remote: allRefs.filter { $0.type == .remoteBranch },
            current: try await getHEADBranch()
        )
    }
    
    public func getStashes() async throws -> [Stash] {
        try await refReader.getStashes()
    }

    // MARK: - History & Graph
    public func getHistory(from commitHash: String, limit: Int? = nil) async throws -> [Commit] {
        var history: [Commit] = []
        var visited = Set<String>()
        var queue = [commitHash]
        
        while !queue.isEmpty {
            if let limit = limit, history.count >= limit {
                break
            }
            
            let hash = queue.removeFirst()
            
            guard !visited.contains(hash) else { continue }
            visited.insert(hash)
            
            guard let commit = try await getCommit(hash) else { continue }
            history.append(commit)
            
            // Add parents to queue
            queue.append(contentsOf: commit.parents)
        }
        
        return history
    }
    
    public func objectExists(_ hash: String) async throws -> Bool {
        try await locator.exists(hash)
    }
    
    public func enumerateObjects(_ visitor: @Sendable (String) async throws -> Bool) async throws {
        let shouldContinue = try await locator.enumerateLooseHashes(visitor)
        guard shouldContinue else { return }
        
        _ = try await locator.enumeratePackedHashes(visitor)
    }
}

// MARK: - Repository error
public enum RepositoryError: Error {
    case objectNotFound(String)
    case invalidObjectType
    case corruptedRepository
    case packIndexNotFound
}

// MARK: - Private functions
private extension GitRepository {
    /// Load an object from storage (loose or packed)
    func loadObject(hash: String) async throws -> ParsedObject? {
        guard let location = try await locator.locate(hash) else { return nil }
        
        switch location {
        case .loose(let fileURL):
            let data = try Data(contentsOf: fileURL)
            return try looseParser.parse(hash: hash, data: data)
        case .packed(let packLocation):
            guard let packIndex = try await locator.getPackIndex(for: packLocation.packURL) else {
                throw RepositoryError.packIndexNotFound
            }
            return try await packReader.parseObject(at: packLocation, packIndex: packIndex)
        }
    }
    
    func streamAllCommits(limit: Int? = nil) -> AsyncThrowingStream<Commit, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    // Get all refs
                    let allRefs = try await getRefs()
                    
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
                            // parent[0] = base commit (OK to show, it's real work)
                            // parent[1] = index state (HIDE - internal)
                            // parent[2] = untracked (HIDE - internal)
                            
                            if stashCommit.parents.count >= 2 {
                                // Hide index state commit
                                stashInternalCommits.insert(stashCommit.parents[1])
                            }
                            
                            if stashCommit.parents.count >= 3 {
                                // Hide untracked files commit
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
                        if let limit = limit, count >= limit {
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

    func getBlob(at path: String, treeHash: String) async throws -> Blob? {
        let paths = try await getTreePaths(treeHash)
        guard let blobHash = paths[path] else { return nil }
        return try await getBlob(blobHash)
    }

    /// Recursive tree walking helper
    func walkTreeRecursive(
        treeHash: String,
        currentPath: String,
        visitor: (Tree.Entry) async throws -> Bool
    ) async throws {
        guard let tree = try await getTree(treeHash) else { return }
        
        for entry in tree.entries {
            let fullPath = currentPath.isEmpty ? entry.name : "\(currentPath)/\(entry.name)"
            let entryType: Tree.Entry.EntryType
            
            if entry.mode.hasPrefix("40") || entry.mode == "040000" {
                entryType = .tree
            } else if entry.mode == "120000" {
                entryType = .symlink
            } else if entry.mode == "160000" {
                entryType = .gitlink
            } else {
                entryType = .blob
            }
            
            let treeEntry = Tree.Entry(
                mode: entry.mode,
                type: entryType,
                hash: entry.hash,
                name: entry.name,
                path: fullPath
            )
            
            let shouldContinue = try await visitor(treeEntry)
            if !shouldContinue {
                return
            }
            
            // Recurse into subdirectories
            if entryType == .tree {
                try await walkTreeRecursive(
                    treeHash: entry.hash,
                    currentPath: fullPath,
                    visitor: visitor
                )
            }
        }
    }
}
