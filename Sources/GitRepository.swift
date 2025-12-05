import Foundation

public protocol GitRepositoryProtocol: Actor {
    /// Repository URL
    var url: URL { get }
    
    /// Get a commit by hash (lazy loaded)
    func getCommit(_ hash: String) async throws -> Commit?
    
    func getAllCommits(limit: Int?) async throws -> [Commit]
    func streamAllCommits(limit: Int?) -> AsyncThrowingStream<Commit, Error>

    /// Get changed files for a commit
    func getChangedFiles(_ commitId: String) async throws -> [String: CommitedFile]

    func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk]
    func getFileDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk]
    func getStagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk]

    /// Get a tree by hash (lazy loaded)
    func getTree(_ hash: String) async throws -> Tree?
    
    /// Get a blob by hash (lazy loaded)
    func getBlob(_ hash: String) async throws -> Blob?
    
    /// Stream a large blob without loading entirely into memory
    func streamBlob(_ hash: String) -> AsyncThrowingStream<Data, Error>
    
    func getWorkingTreeStatus() async throws -> WorkingTreeStatus?
    func getStagedChanges() async throws -> [String: WorkingTreeFile]
    func getUnstagedChanges() async throws -> [String: WorkingTreeFile]

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
    
    /// Stage files
    func stageFile(at path: String) async throws
    func stageFiles() async throws
    func unstageFile(at path: String) async throws
    func unstageFiles() async throws

    /// Stage hunks
    func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws
    func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws
    func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws
    
    func discardFile(at path: String) async throws
    func discardAllFiles() async throws

    func commit(message: String, author: String?) async throws
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
    private let commandRunner: GitCommandable
    private let patchGenerator: PatchGenerator

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
        self.commandRunner = CommandRunner()
        self.patchGenerator = PatchGenerator()
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
        var streamedCommits = [Commit]()
        
        for try await commit in streamAllCommits(limit: limit) {
            streamedCommits.append(commit)
        }
        
        return streamedCommits.sorted { $0.author.timestamp < $1.author.timestamp }
    }
    
    public func streamAllCommits(limit: Int? = nil) -> AsyncThrowingStream<Commit, Error> {
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
        let snapshot = try await getRepoSnapshot()
        
        print("\n=== getFileDiff SNAPSHOT DEBUG ===")
        if let entry = snapshot.index.first(where: { $0.path == workingFile.path }) {
            print("Index entry SHA for \(workingFile.path): \(entry.sha1)")
        }
        print("=== END SNAPSHOT ===")
        
        let resolver = WorkingTreeDiffResolver(
            repoURL: url,
            blobLoader: self
        )
        
        let diffPair = try await resolver.resolveDiff(
            for: workingFile,
            headTree: snapshot.headTree,
            indexMap: snapshot.indexMap
        )
        
        print("\n=== getFileDiff DEBUG ===")
        print("File: \(workingFile.path)")
        print("Old content (first 100 chars): \(diffPair.old?.text?.prefix(100) ?? "nil")")
        print("New content (first 100 chars): \(diffPair.new?.text?.prefix(100) ?? "nil")")
        print("=== END DEBUG ===")

        return try await diffGenerator.generateHunks(
            oldContent: diffPair.old?.text ?? "",
            newContent: diffPair.new?.text ?? ""
        )
    }
    
    /// Get diff for staged changes (index vs HEAD)
    public func getStagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk] {
        let snapshot = try await getRepoSnapshot()
        
        // Get HEAD version
        let headContent: String
        if let headBlobHash = snapshot.headTree[workingFile.path] {
            headContent = try await getBlob(headBlobHash)?.text ?? ""
        } else {
            headContent = ""
        }
        
        // Get index version
        let indexContent: String
        if let indexEntry = snapshot.index.first(where: { $0.path == workingFile.path }) {
            indexContent = try await getBlob(indexEntry.sha1)?.text ?? ""
        } else {
            indexContent = ""
        }
        
        // Diff: HEAD → index (what's staged)
        return try await diffGenerator.generateHunks(
            oldContent: headContent,
            newContent: indexContent
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
        let snapshot = try await getRepoSnapshot()
        return try await workingTree.computeStatus(headTree: snapshot.headTree)
    }
    
    /// Get only staged changes (HEAD → Index)
    public func getStagedChanges() async throws -> [String: WorkingTreeFile] {
        let snapshot = try await getRepoSnapshot()
        return try await workingTree.stagedChanges(headTree: snapshot.headTree)
    }
    
    /// Get only unstaged changes (Index → Working Tree)
    public func getUnstagedChanges() async throws -> [String: WorkingTreeFile] {
        try await workingTree.unstagedChanges()
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
    
    // MARK: - Git commands
    public func commit(message: String, author: String?) async throws {
        // Validate message
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitError.emptyCommitMessage
        }
        
        // Check if there are staged changes
        let staged = try await getStagedChanges()
        guard !staged.isEmpty else {
            throw GitError.nothingToCommit
        }
        
        try await commandRunner.run(
            .commit(message: message, author: author),
            stdin: nil,
            in: url
        )
        
        // Invalidate cache (index is reset after commit)
        await workingTree.invalidateIndexCache()
    }

    /// Stage files
    public func stageFile(at path: String) async throws {
        try await commandRunner.run(.add(path: path), stdin: nil, in: url)
        await workingTree.invalidateIndexCache()
    }
    
    /// Stage all files
    public func stageFiles() async throws {
        try await commandRunner.run(.addAll, stdin: nil, in: url)
        await workingTree.invalidateIndexCache()
    }
    
    /// Unstage a file
    public func unstageFile(at path: String) async throws {
        try await commandRunner.run(.reset(path: path), stdin: nil, in: url)
        await workingTree.invalidateIndexCache()
    }
    
    /// Unstage all files
    public func unstageFiles() async throws {
        try await commandRunner.run(.resetAll, stdin: nil, in: url)
        await workingTree.invalidateIndexCache()
    }
    
    /// Discard all changes in a file (restore to index version)
    public func discardFile(at path: String) async throws {
        // Get file status
        guard let status = try await getWorkingTreeStatus(),
              let file = status.files[path] else {
            return // File doesn't exist
        }
        
        if file.unstaged == .untracked {
            // Untracked file - delete from filesystem
            let fileURL = url.appendingPathComponent(path)
            try fileManager.removeItem(at: fileURL)
        } else {
            // Tracked file - restore from index/HEAD
            try await commandRunner.run(.restore(path: path), stdin: nil, in: url)
        }
    }

    /// Discard all unstaged changes
    public func discardAllFiles() async throws {
        try await commandRunner.run(.restoreAll, stdin: nil, in: url)
    }

    /// Stage hunk
    public func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        // Check if file is in index
        let snapshot = try await workingTree.readIndex()
        let fileInIndex = snapshot.contains { $0.path == file.path }
        
        if !fileInIndex {
            throw GitError.fileNotInIndex(path: file.path)
        }

        if file.unstaged == .untracked {
            throw GitError.cannotStageHunkFromUntrackedFile
        }

        // Save old blob SHA BEFORE staging
        let oldBlobSha = snapshot.first(where: { $0.path == file.path })?.sha1
        print("\n=== BEFORE STAGING ===")
        print("Old blob SHA: \(oldBlobSha ?? "nil")")

        let patch = patchGenerator.generatePatch(hunk: hunk, file: file)
        
        try await commandRunner.run(
            .applyPatch(cached: true),
            stdin: patch,
            in: url
        )

        await workingTree.invalidateIndexCache()
        
        if let oldSha = oldBlobSha {
            print("Removing blob from cache: \(oldSha)")
            await cache.remove(.blob(hash: oldSha))
        }
        
        let snapshotAfter = try await workingTree.readIndex()
        let newBlobSha = snapshotAfter.first(where: { $0.path == file.path })?.sha1
        print("New blob SHA: \(newBlobSha ?? "nil")")
        print("SHAs are different: \(oldBlobSha != newBlobSha)")
        print("=== END STAGING ===\n")
    }

    /// Unstage hunk
    public func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        // Validation
        let snapshot = try await workingTree.readIndex()
        let fileInIndex = snapshot.contains { $0.path == file.path }
        
        if !fileInIndex {
            throw GitError.fileNotInIndex(path: file.path)
        }

        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)
        
        try await commandRunner.run(
            .applyPatch(cached: true),
            stdin: patch,
            in: url
        )
        
        await workingTree.invalidateIndexCache()

        try await cleanupTrailingNewlineChange(for: file.path)
    }

    /// Disgard hunk
    public func discardHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws {
        let patch = patchGenerator.generateReversePatch(hunk: hunk, file: file)
        
        try await commandRunner.run(
            .applyPatch(cached: false),
            stdin: patch,
            in: url
        )
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
    struct RepoSnapshot {
        let head: String
        let commit: Commit
        let headTree: [String: String]
        let index: [IndexEntry]
        let indexMap: [String: String]
    }

    func getRepoSnapshot() async throws -> RepoSnapshot {
        guard let head = try await getHEAD(), let commit = try await getCommit(head) else {
            throw GitError.notARepository
        }
        
        let headTree = try await getTreePaths(commit.tree)
        let index = try await workingTree.readIndex()
        let indexMap = Dictionary(uniqueKeysWithValues: index.map { ($0.path, $0.sha1) })
        
        return RepoSnapshot(
            head: head,
            commit: commit,
            headTree: headTree,
            index: index,
            indexMap: indexMap
        )
    }

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

    func cleanupTrailingNewlineChange(for path: String) async throws {
        let snapshot = try await getRepoSnapshot()

        guard let blobHash = snapshot.headTree[path],
              let headBlob = try await getBlob(blobHash) else {
            return
        }
        
        // Get INDEX content
        guard let indexEntry = snapshot.index.first(where: { $0.path == path }),
              let indexBlob = try await getBlob(indexEntry.sha1)
        else { return }
        
        let headContent = headBlob.text
        let indexContent = indexBlob.text
        
        // Check if only difference is trailing newline
        let headTrimmed = headContent?.trimmingCharacters(in: .newlines)
        let indexTrimmed = indexContent?.trimmingCharacters(in: .newlines)
        
        if headTrimmed == indexTrimmed && headContent != indexContent {
            // Only difference is trailing newlines - unstage it
            try await commandRunner.run(.reset(path: path), stdin: nil, in: url)
        }
    }
}
