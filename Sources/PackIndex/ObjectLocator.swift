import Foundation

public enum ObjectLocation: Sendable {
    case loose(url: URL)
    case packed(location: PackObjectLocation)
}

// MARK: - Protocol
public protocol ObjectLocatorProtocol: Actor {  // Add : Actor here
    /// Find where an object is stored (loose or packed)
    func locate(_ hash: String) async throws -> ObjectLocation?
    
    /// Check if object exists without determining location
    func exists(_ hash: String) async throws -> Bool
    
    func enumerateLooseHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool
    func enumeratePackedHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool

    func getPackIndex(for packURL: URL) async throws -> PackIndexProtocol?

    /// Invalidate location cache (when repo changes)
    func invalidate() async
}

// MARK: -
public actor ObjectLocator {
    private let gitURL: URL
    private let packIndexManager: PackIndexManagerProtocol
    
    // Caches
    private var looseObjectIndex: [String: URL]?
    private var indexBuilt = false
    
    public init(
        gitURL: URL,
        packIndexManager: PackIndexManagerProtocol
    ) {
        self.gitURL = gitURL
        self.packIndexManager = packIndexManager
    }
}

// MARK: - ObjectLocatorProtocol
extension ObjectLocator: ObjectLocatorProtocol {
    public func locate(_ hash: String) async throws -> ObjectLocation? {
        if let looseURL = try await findLooseObject(hash) {
            return .loose(url: looseURL)
        }
        
        if let packLocation = try await packIndexManager.findObject(hash) {
            return .packed(location: packLocation)
        }
        
        return nil
    }
    
    public func exists(_ hash: String) async throws -> Bool {
        try await locate(hash) != nil
    }
    
    public func getPackIndex(for packURL: URL) async throws -> PackIndexProtocol? {
        try await packIndexManager.getPackIndex(for: packURL)
    }
    
    public func enumerateLooseHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool {
        try await ensureLooseIndexBuilt()
        
        guard let index = looseObjectIndex else { return true }
        
        for hash in index.keys {
            let shouldContinue = try await visitor(hash)
            if !shouldContinue {
                return false // Signal to stop
            }
        }
        return true
    }

    public func enumeratePackedHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool {
        try await packIndexManager.enumeratePackedHashes(visitor)
    }

    public func invalidate() async {
        looseObjectIndex = nil
        indexBuilt = false
        await packIndexManager.invalidate()
    }
}

// MARK: - Private
private extension ObjectLocator {
    var objectsURL: URL {
        gitURL.appendingPathComponent("objects")
    }
    
    func findLooseObject(_ hash: String) async throws -> URL? {
        try await ensureLooseIndexBuilt()
        return looseObjectIndex?[hash.lowercased()]
    }
    
    func ensureLooseIndexBuilt() async throws {
        guard !indexBuilt else { return }
        
        let gitURL = self.gitURL
        
        let index = try await Task.detached {
            try Self.scanLooseObjects(gitURL: gitURL, fileManager: .default)
        }.value
        
        looseObjectIndex = index
        indexBuilt = true
    }
    
    // Make static so it can be called from Task.detached
    static func scanLooseObjects(gitURL: URL, fileManager: FileManager) throws -> [String: URL] {
        var index: [String: URL] = [:]
        let objectsURL = gitURL.appendingPathComponent("objects")
        
        guard fileManager.fileExists(atPath: objectsURL.path) else {
            return [:]
        }
        
        let prefixDirs = try fileManager.contentsOfDirectory(
            at: objectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for prefixDir in prefixDirs {
            let prefix = prefixDir.lastPathComponent
            
            guard prefix.count == 2,
                  prefix.allSatisfy({ $0.isHexDigit }) else {
                continue
            }
            
            let objectFiles = try fileManager.contentsOfDirectory(
                at: prefixDir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            
            for objectFile in objectFiles {
                let suffix = objectFile.lastPathComponent
                let hash = prefix + suffix
                index[hash] = objectFile
            }
        }
        
        return index
    }
}
