import Foundation

public protocol WorkingTreeReaderProtocol: Actor {
    /// Compute the current working tree status
    func status() async throws -> WorkingTreeStatus
    
    /// Get staged changes (HEAD → Index)
    func stagedChanges() async throws -> [String: WorkingTreeFile]
    
    /// Get unstaged changes (Index → Working Tree)
    func unstagedChanges() async throws -> [String: WorkingTreeFile]
    
    /// Get untracked files
    func untrackedFiles() async throws -> [String]
}

// MARK: -
public actor WorkingTreeReader {
    private let repository: GitRepositoryProtocol
    private let repoURL: URL
    private let fileManager: FileManager
    private let indexParser: GitIndexReaderProtocol
    
    public init(
        repository: GitRepositoryProtocol,
        repoURL: URL,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.repoURL = repoURL
        self.fileManager = fileManager
        self.indexParser = GitIndex()
    }
}

// MARK: - WorkingTreeReaderProtocol
extension WorkingTreeReader: WorkingTreeReaderProtocol {
    public func status() async throws -> WorkingTreeStatus {
        // 1. Read index
        let indexEntries = try await readIndex()
        let index = Dictionary(uniqueKeysWithValues: indexEntries.map { ($0.path, $0.sha1) })
        
        // 2. Get HEAD tree
        let head = try await getHEADTree()
        
        // 3. Scan working tree
        let working = try await scanWorkingTree()
        
        // 4. Compute status
        return await computeStatus(head: head, index: index, working: working)
    }
    
    public func stagedChanges() async throws -> [String: WorkingTreeFile] {
        let status = try await status()
        return status.files.filter { $0.value.isStaged }
    }
    
    public func unstagedChanges() async throws -> [String: WorkingTreeFile] {
        let status = try await status()
        return status.files.filter { $0.value.isUnstaged }
    }
    
    public func untrackedFiles() async throws -> [String] {
        let status = try await status()
        return status.files.values
            .filter { $0.unstaged == .untracked }
            .map { $0.path }
    }
}

// MARK: - Private
private extension WorkingTreeReader {
    func readIndex() async throws -> [IndexEntry] {
        []
    }
    
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
}
