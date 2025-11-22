import Foundation

public enum ObjectLocation: Sendable {
    case loose(url: URL)
    case packed(location: PackObjectLocation)
}

// MARK: - Protocol
public protocol ObjectLocatorProtocol: Actor {
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
    private let repoURL: URL
    private let packIndexManager: PackIndexManagerProtocol
    
    // Lazy caches
    private var looseObjectCache: [String: URL] = [:]
    private var scannedPrefixes: Set<String> = []
    
    public init(
        repoURL: URL,
        packIndexManager: PackIndexManagerProtocol
    ) {
        self.repoURL = repoURL
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
        // Ensure all prefixes are scanned
        try await scanAllPrefixesIfNeeded()
        
        for hash in looseObjectCache.keys {
            let shouldContinue = try await visitor(hash)
            if !shouldContinue {
                return false
            }
        }
        return true
    }

    public func enumeratePackedHashes(_ visitor: @Sendable (String) async throws -> Bool) async throws -> Bool {
        try await packIndexManager.enumeratePackedHashes(visitor)
    }

    public func invalidate() async {
        looseObjectCache.removeAll()
        scannedPrefixes.removeAll()
        await packIndexManager.invalidate()
    }
}

// MARK: - Private
private extension ObjectLocator {
    var gitURL: URL {
        repoURL.appendingPathComponent(GitPath.git.rawValue)
    }
    
    var objectsURL: URL {
        gitURL.appendingPathComponent(GitPath.objects.rawValue)
    }

    func findLooseObject(_ hash: String) async throws -> URL? {
        let hashLower = hash.lowercased()
        
        // Check cache first
        if let cached = looseObjectCache[hashLower] {
            return cached
        }
        
        // Try direct path (fastest - single file check)
        let prefix = String(hashLower.prefix(2))
        let suffix = String(hashLower.dropFirst(2))
        let directURL = objectsURL.appendingPathComponent("\(prefix)/\(suffix)")
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directURL.path) {
            looseObjectCache[hashLower] = directURL
            return directURL
        }
        
        // Not found via direct path - scan prefix directory if we haven't
        if !scannedPrefixes.contains(prefix) {
            try await scanPrefix(prefix)
        }
        
        // Check cache again after scan
        return looseObjectCache[hashLower]
    }
    
    /// Scan a single prefix directory (e.g., "ab")
    func scanPrefix(_ prefix: String) async throws {
        let prefixURL = objectsURL.appendingPathComponent(prefix)
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: prefixURL.path) else {
            scannedPrefixes.insert(prefix)
            return
        }
        
        // Scan off main thread
        let objects = try await Task.detached {
            try Self.scanPrefixDirectory(prefixURL: prefixURL, prefix: prefix, fileManager: fileManager)
        }.value
        
        // Cache results
        for (hash, url) in objects {
            looseObjectCache[hash] = url
        }
        
        scannedPrefixes.insert(prefix)
    }

    /// Scan all prefixes (for enumeration)
    func scanAllPrefixesIfNeeded() async throws {
        // If we've scanned all 256 prefixes, we're done
        if scannedPrefixes.count == 256 {
            return
        }
        
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: objectsURL.path) else {
            return
        }
        
        // Get all prefix directories
        let contents = try fileManager.contentsOfDirectory(
            at: objectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        for item in contents {
            let prefix = item.lastPathComponent
            
            // Only 2-char hex prefixes
            guard prefix.count == 2, prefix.allSatisfy({ $0.isHexDigit }) else {
                continue
            }
            
            // Skip if already scanned
            if scannedPrefixes.contains(prefix) {
                continue
            }
            
            try await scanPrefix(prefix)
        }
    }
    
    /// Scan a prefix directory - static for Task.detached
    static func scanPrefixDirectory(
        prefixURL: URL,
        prefix: String,
        fileManager: FileManager
    ) throws -> [String: URL] {
        var objects: [String: URL] = [:]
        
        let files = try fileManager.contentsOfDirectory(
            at: prefixURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        
        for file in files {
            let suffix = file.lastPathComponent
            let hash = (prefix + suffix).lowercased()
            objects[hash] = file
        }
        
        return objects
    }
}
