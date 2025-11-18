import Foundation

public protocol PackIndexManagerProtocol: Actor {
    /// Find object in any loaded pack file
    func findObject(_ hash: String) async throws -> PackObjectLocation?
    
    func enumeratePackedHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool

    func getPackIndex(for packURL: URL) async throws -> PackIndexProtocol?

    /// Invalidate cached pack indexes
    func invalidate()
}

// MARK: - PackIndexManager Implementation
public actor PackIndexManager {
    private let gitURL: URL
    
    // Lazy-loaded pack indexes
    private var packIndexes: [PackIndexProtocol] = []
    private var packIndexByURL: [URL: PackIndexProtocol] = [:]
    private var indexesLoaded = false
    
    public init(gitURL: URL) {
        self.gitURL = gitURL
    }
}

// MARK: - PackIndexManagerProtocol
extension PackIndexManager: PackIndexManagerProtocol {
    public func findObject(_ hash: String) async throws -> PackObjectLocation? {
        try await ensureIndexesLoaded()
        
        // Search across all pack indexes
        for packIndex in packIndexes {
            if let location = packIndex.findObject(hash) {
                return location
            }
        }
        
        return nil
    }
    
    public func getPackIndex(for packURL: URL) async throws -> PackIndexProtocol? {
        try await ensureIndexesLoaded()
        return packIndexByURL[packURL]
    }
    
    public func enumeratePackedHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool {
        try await ensureIndexesLoaded()
        
        for packIndex in packIndexes {
            for hash in packIndex.getAllHashes() {
                let shouldContinue = try await visitor(hash)
                if !shouldContinue {
                    return false // Signal to stop
                }
            }
        }
        return true
    }
    
    public func invalidate() {
        packIndexes.forEach { $0.clear() }
        packIndexes.removeAll()
        indexesLoaded = false
    }
}

// MARK: - Private Helpers
private extension PackIndexManager {
    var packURL: URL {
        gitURL.appendingPathComponent("objects/pack")
    }
    
    /// Load all pack indexes lazily on first access
    func ensureIndexesLoaded() async throws {
        guard !indexesLoaded else { return }
        
        let gitURL = self.gitURL
        let (indexes, indexByURL) = try await Task.detached {
            try Self.loadAllPackIndexes(gitURL: gitURL, fileManager: .default)
        }.value

        packIndexes = indexes
        packIndexByURL = indexByURL
        indexesLoaded = true
    }
    
    /// Scan pack directory and load all .idx files
    static func loadAllPackIndexes(gitURL: URL, fileManager: FileManager) throws -> ([PackIndexProtocol], [URL: PackIndexProtocol]) {
        let packURL = gitURL.appendingPathComponent("objects/pack")
        
        guard fileManager.fileExists(atPath: packURL.path) else {
            return ([], [:])
        }
        
        let packFiles = try fileManager.contentsOfDirectory(
            at: packURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        var indexes: [PackIndexProtocol] = []
        var indexByURL: [URL: PackIndexProtocol] = [:]
        
        let idxFiles = packFiles.filter { $0.pathExtension == "idx" }
        
        for idxFile in idxFiles {
            let packFile = idxFile
                .deletingPathExtension()
                .appendingPathExtension("pack")
            
            guard fileManager.fileExists(atPath: packFile.path) else {
                continue
            }
            
            let packIndex = PackIndex()
            try packIndex.load(idxURL: idxFile, packURL: packFile)
            indexes.append(packIndex)
            indexByURL[packFile] = packIndex
        }
        
        return (indexes, indexByURL)
    }
}
