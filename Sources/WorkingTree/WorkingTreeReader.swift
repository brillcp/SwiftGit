import Foundation

public protocol WorkingTreeReaderProtocol: Actor {
    /// Compute the current working tree status
    func computeStatus(headTree: [String: String]) async throws -> WorkingTreeStatus
    
    /// Get staged changes (HEAD → Index)
    func stagedChanges() async throws -> [String: WorkingTreeFile]
    
    /// Get unstaged changes (Index → Working Tree)
    func unstagedChanges() async throws -> [String: WorkingTreeFile]
    
    /// Get untracked files
    func untrackedFiles() async throws -> [String]
}

// MARK: -
public actor WorkingTreeReader {
    private let repoURL: URL
    private let fileManager: FileManager
    private let indexReader: GitIndexReaderProtocol
    private let refReader: RefReaderProtocol
    
    public init(
        repoURL: URL,
        refReader: RefReaderProtocol,
        indexReader: GitIndexReaderProtocol = GitIndexReader(),
        fileManager: FileManager = .default
    ) {
        self.repoURL = repoURL
        self.refReader = refReader
        self.fileManager = fileManager
        self.indexReader = indexReader
    }
}

// MARK: - WorkingTreeReaderProtocol
extension WorkingTreeReader: WorkingTreeReaderProtocol {
    public func computeStatus(headTree: [String: String]) async throws -> WorkingTreeStatus {
        // 1. Read index
        let indexEntries = try await readIndex()
        let index = Dictionary(uniqueKeysWithValues: indexEntries.map { ($0.path, $0.sha1) })
        
        // 2. Scan working tree
        let working = try await checkWorkingTreeAgainstIndex(indexEntries: indexEntries)
        
        // 3. Compute status
        return compareStates(
            headTree: headTree,
            index: index,
            workingTree: working
        )
    }
    
    public func stagedChanges() async throws -> [String: WorkingTreeFile] {
        [:]
    }
    
    public func unstagedChanges() async throws -> [String: WorkingTreeFile] {
        [:]
    }
    
    public func untrackedFiles() async throws -> [String] {
        []
    }
}

// MARK: - Private
private extension WorkingTreeReader {
    func readIndex() async throws -> [IndexEntry] {
        let indexURL = repoURL.appendingPathComponent(".git/index")
        
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }
        
        let snapshot = try await indexReader.readIndex(at: indexURL)
        return snapshot.entries
    }
    
    func checkWorkingTreeAgainstIndex(indexEntries: [IndexEntry]) async throws -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(indexEntries.count)
        
        for entry in indexEntries {
            let fileURL = repoURL.appendingPathComponent(entry.path)
            
            if let hash = try checkFile(entry: entry, fileURL: fileURL) {
                result[entry.path] = hash
            }
            // If nil, file was deleted - don't add to result
        }
        
        return result
    }
    
    func checkFile(entry: IndexEntry, fileURL: URL) throws -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil // File deleted
        }
        
        // Get file stats - fast syscall
        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let modDate = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? UInt64 else {
            return nil
        }
        
        // Git's optimization: if mtime and size match, file is unchanged
        let mtimeMatches = abs(modDate.timeIntervalSince(entry.mtime)) < 0.001 // 1ms tolerance
        let sizeMatches = size == UInt64(entry.size)
        
        if mtimeMatches && sizeMatches {
            // File unchanged - reuse hash from index (NO HASHING!)
            return entry.sha1
        }
        
        // File changed - compute new hash
        return try computeFileHash(at: fileURL)
    }
    
    func computeFileHash(at url: URL) throws -> String {
        "hash"
    }

    func compareStates(
        headTree: [String: String],
        index: [String: String],
        workingTree: [String: String]
    ) -> WorkingTreeStatus {
        .init(files: [:])
    }

    func scanForUntrackedFiles(
        indexedPaths: Set<String>,
        indexedDirs: Set<String>
    ) async throws -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(64)
        
        try await scanDirectoryForUntracked(
            at: repoURL,
            relativePath: "",
            indexedPaths: indexedPaths,
            indexedDirs: indexedDirs,
            result: &result
        )
        
        return result
    }

    func scanDirectoryForUntracked(
        at dirURL: URL,
        relativePath: String,
        indexedPaths: Set<String>,
        indexedDirs: Set<String>,
        result: inout [String: String]
    ) async throws {
        
    }
    
    /*
    func getHEADTree() async throws -> [String: String] {
        [:]
    }
    
    func scanWorkingTree() async throws -> [String: String] {
        [:]
    }
    
    func computeStatus(
        head: [String: String],
        index: [String: String],
        working: [String: String]
    ) async -> WorkingTreeStatus {
        // Compare and compute status
        WorkingTreeStatus(files: [:])
    }
     */
}
