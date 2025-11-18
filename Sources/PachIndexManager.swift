import Foundation

protocol PackIndexManagerProtocol: Actor {
    /// Find object in any loaded pack file
    func findObject(_ hash: String) async throws -> PackObjectLocation?
    
    /// Get all hashes across all pack files
    func getAllHashes() async throws -> Set<String>
    
    /// Invalidate cached pack indexes
    func invalidate()
}

// MARK: - PackIndexManager Implementation

actor PackIndexManager: PackIndexManagerProtocol {
    private let gitURL: URL
    private let fileManager: FileManager
    
    // Lazy-loaded pack indexes
    private var packIndexes: [PackIndexProtocol] = []
    private var indexesLoaded = false
    
    init(gitURL: URL, fileManager: FileManager = .default) {
        self.gitURL = gitURL
        self.fileManager = fileManager
    }
    
    func findObject(_ hash: String) async throws -> PackObjectLocation? {
        try await ensureIndexesLoaded()
        
        // Search across all pack indexes
        for packIndex in packIndexes {
            if let location = packIndex.findObject(hash) {
                return location
            }
        }
        
        return nil
    }
    
    func getAllHashes() async throws -> Set<String> {
        try await ensureIndexesLoaded()
        
        var allHashes = Set<String>()
        for packIndex in packIndexes {
            allHashes.formUnion(packIndex.getAllHashes())
        }
        
        return allHashes
    }
    
    func invalidate() {
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
        
//        let indexes = try await Task.detached {
//            try Self.loadAllPackIndexes(gitURL: gitURL, fileManager: .default)
//        }.value
//
//        packIndexes = indexes
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
