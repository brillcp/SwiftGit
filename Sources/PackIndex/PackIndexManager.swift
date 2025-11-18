import Foundation

public protocol PackIndexManagerProtocol: Actor {
    /// Find object in any loaded pack file
    func findObject(_ hash: String) async throws -> PackObjectLocation?
    
    func enumeratePackedHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool

    /// Invalidate cached pack indexes
    func invalidate()
}

// MARK: - PackIndexManager Implementation
public actor PackIndexManager {
    private let gitURL: URL
    private let fileManager: FileManager
    
    // Lazy-loaded pack indexes
    private var packIndexes: [PackIndexProtocol] = []
    private var indexesLoaded = false
    
    public init(gitURL: URL, fileManager: FileManager = .default) {
        self.gitURL = gitURL
        self.fileManager = fileManager
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
        let indexes = try await Task.detached {
            try Self.loadAllPackIndexes(gitURL: gitURL, fileManager: .default)
        }.value

        packIndexes = indexes
        indexesLoaded = true
    }
    
    /// Scan pack directory and load all .idx files
    private static func loadAllPackIndexes(gitURL: URL, fileManager: FileManager) throws -> [PackIndexProtocol] {
        let packURL = gitURL.appendingPathComponent("objects/pack")
        
        guard fileManager.fileExists(atPath: packURL.path) else {
            return []
        }
        
        let packFiles = try fileManager.contentsOfDirectory(
            at: packURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        var indexes: [PackIndexProtocol] = []
        
        // Find all .idx files
        let idxFiles = packFiles.filter { $0.pathExtension == "idx" }
        
        for idxFile in idxFiles {
            // Find corresponding .pack file
            let packFile = idxFile
                .deletingPathExtension()
                .appendingPathExtension("pack")
            
            guard fileManager.fileExists(atPath: packFile.path) else {
                continue
            }
            
            // Load the index
            let packIndex = PackIndex()
            try packIndex.load(idxURL: idxFile, packURL: packFile)
            indexes.append(packIndex)
        }
        
        return indexes
    }
}
