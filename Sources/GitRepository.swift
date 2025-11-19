import Foundation

public protocol GitRepositoryProtocol: Actor {
    /// Repository URL
    var url: URL { get }
    
    /// Get a commit by hash (lazy loaded)
    func getCommit(_ hash: String) async throws -> Commit?
    
    /// Get changed files for a commit
    func getChangedFiles(_ commitId: String) async throws -> [String: CommitedFile]

    func getFileDiff(commitId: String, filePath: String) async throws -> [DiffHunk]

    /// Get a tree by hash (lazy loaded)
    func getTree(_ hash: String) async throws -> Tree?
    
    /// Get a blob by hash (lazy loaded)
    func getBlob(_ hash: String) async throws -> Blob?
    
    /// Stream a large blob without loading entirely into memory
    func streamBlob(_ hash: String) -> AsyncThrowingStream<Data, Error>
    
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

    // Parsers
    private let commitParser: any CommitParserProtocol
    private let treeParser: any TreeParserProtocol
    private let blobParser: any BlobParserProtocol
    
    private var securityScopeStarted: Bool = false
    private let fileManager: FileManager

    public let url: URL

    public init(
        url: URL,
        cache: ObjectCacheProtocol = ObjectCache(),
        locator: ObjectLocatorProtocol,
        looseParser: LooseObjectParserProtocol = LooseObjectParser(),
        packReader: PackFileReaderProtocol = PackFileReader(),
        diffCalculator: DiffCalculatorProtocol = DiffCalculator(),
        diffGenerator: DiffGeneratorProtocol = HunkGenerator(),
        commitParser: any CommitParserProtocol = CommitParser(),
        treeParser: any TreeParserProtocol = TreeParser(),
        blobParser: any BlobParserProtocol = BlobParser(),
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.cache = cache
        self.locator = locator
        self.looseParser = looseParser
        self.packReader = packReader
        self.diffCalculator = diffCalculator
        self.diffGenerator = diffGenerator
        self.commitParser = commitParser
        self.treeParser = treeParser
        self.blobParser = blobParser
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

    public func getFileDiff(commitId: String, filePath: String) async throws -> [DiffHunk] {
        guard let commit = try await getCommit(commitId) else { return [] }
        
        let newBlob = try await getBlob(at: filePath, treeHash: commit.tree)

        var oldBlob: Blob? = nil
        if let parentId = commit.parents.first,
           let parentCommit = try await getCommit(parentId) {
            oldBlob = try await getBlob(at: filePath, treeHash: parentCommit.tree)
        }
        
        let oldContent = oldBlob.flatMap { String(data: $0.data, encoding: .utf8) } ?? ""
        let newContent = newBlob.flatMap { String(data: $0.data, encoding: .utf8) } ?? ""
        
        return try await diffGenerator.generateHunks(
            oldContent: oldContent,
            newContent: newContent,
            contextLines: 3
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
        // Check cache
        if let cached: [GitRef] = await cache.get(.refs) { return cached }
        
        var refs: [GitRef] = []
        
        // Read loose refs
        refs.append(contentsOf: try readRefs(from: gitURL, relativePath: "refs/heads", type: .localBranch))
        refs.append(contentsOf: try readRefs(from: gitURL, relativePath: "refs/remotes", type: .remoteBranch))
        refs.append(contentsOf: try readRefs(from: gitURL, relativePath: "refs/tags", type: .tag))
        
        // Read packed refs
        refs.append(contentsOf: try readPackedRefs(gitURL: gitURL))
        
        // Cache refs
        await cache.set(.refs, value: refs)
        return refs
    }
    
    public func getHEAD() async throws -> String? {
        if let cached: String = await cache.get(.head) {
            return cached
        }
        
        let headFile = gitURL.appendingPathComponent("HEAD")
        let headContent = try String(contentsOf: headFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If HEAD points to a ref, resolve it
        if headContent.starts(with: "ref: ") {
            let refPath = String(headContent.dropFirst(5))
            let refFile = gitURL.appendingPathComponent(refPath)
            
            let commitHash = try String(contentsOf: refFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            await cache.set(.head, value: commitHash)
            return commitHash
        } else {
            // Detached HEAD - return the commit hash directly
            await cache.set(.head, value: headContent)
            return headContent
        }
    }
    
    public func getHEADBranch() async throws -> String? {
        let headFile = gitURL.appendingPathComponent("HEAD")
        let headContent = try String(contentsOf: headFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if headContent.starts(with: "ref: refs/heads/") {
            return String(headContent.dropFirst("ref: refs/heads/".count))
        }
        
        return nil // Detached HEAD
    }
    
    public func getBranches() async throws -> Branches {
        let allRefs = try await getRefs()
        
        return Branches(
            local: allRefs.filter { $0.type == .localBranch },
            remote: allRefs.filter { $0.type == .remoteBranch },
            current: try await getHEADBranch()
        )
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
    var gitURL: URL {
        url.appendingPathComponent(".git")
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
            
            let packObject = try await packReader.readObject(at: packLocation, packIndex: packIndex)
            
            switch packObject.type {
            case .commit:
                let commit = try commitParser.parse(hash: hash, data: packObject.data)
                return .commit(commit)
            case .tree:
                let tree = try treeParser.parse(hash: hash, data: packObject.data)
                return .tree(tree)
            case .blob:
                let blob = try blobParser.parse(hash: hash, data: packObject.data)
                return .blob(blob)
            case .tag:
                return nil
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
    
    /// Read refs from a directory
    func readRefs(from gitURL: URL, relativePath: String, type: RefType) throws -> [GitRef] {
        let baseURL = gitURL.appendingPathComponent(relativePath)
        
        guard fileManager.fileExists(atPath: baseURL.path) else { return [] }
        
        var refs: [GitRef] = []
        
        guard let enumerator = fileManager.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            
            let name = fileURL.path.replacingOccurrences(of: baseURL.path + "/", with: "")
            let hash = try String(contentsOf: fileURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            refs.append(GitRef(name: name, hash: hash, type: type))
        }
        
        return refs
    }
    
    /// Read packed-refs file
    func readPackedRefs(gitURL: URL) throws -> [GitRef] {
        let packedURL = gitURL.appendingPathComponent("packed-refs")
        
        guard fileManager.fileExists(atPath: packedURL.path) else { return [] }
        
        let content = try String(contentsOf: packedURL, encoding: .utf8)
        var refs: [GitRef] = []
        var peeledMap: [String: String] = [:]
        
        let lines = content.split(whereSeparator: \.isNewline)
        
        for line in lines {
            let s = line.trimmingCharacters(in: .whitespaces)
            
            if s.isEmpty || s.hasPrefix("#") { continue }
            
            // Peeled tag line
            if s.first == "^" {
                let peeledID = String(s.dropFirst())
                if let last = refs.last {
                    peeledMap[last.hash] = peeledID
                }
                continue
            }
            
            let parts = s.split(separator: " ")
            guard parts.count == 2 else { continue }
            
            let sha = String(parts[0])
            let name = String(parts[1])
            
            if name.hasPrefix("refs/heads/") {
                refs.append(GitRef(
                    name: String(name.dropFirst("refs/heads/".count)),
                    hash: sha,
                    type: .localBranch
                ))
            } else if name.hasPrefix("refs/remotes/") {
                refs.append(GitRef(
                    name: String(name.dropFirst("refs/remotes/".count)),
                    hash: sha,
                    type: .remoteBranch
                ))
            } else if name.hasPrefix("refs/tags/") {
                refs.append(GitRef(
                    name: String(name.dropFirst("refs/tags/".count)),
                    hash: sha,
                    type: .tag
                ))
            }
        }
        
        // Replace annotated tag SHAs with peeled commit SHAs
        for i in refs.indices where refs[i].type == .tag {
            if let peeled = peeledMap[refs[i].hash] {
                refs[i] = GitRef(
                    name: refs[i].name,
                    hash: peeled,
                    type: .tag
                )
            }
        }
        
        return refs
    }
}
