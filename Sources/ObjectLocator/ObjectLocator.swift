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

    /// Get pack index for url
    func getPackIndex(for packURL: URL) async throws -> PackIndexProtocol?
}

// MARK: -
public actor ObjectLocator {
    private let repoURL: URL
    private let packIndexManager: PackIndexManagerProtocol
    private let fileManager: FileManager
    
    public init(
        repoURL: URL,
        packIndexManager: PackIndexManagerProtocol,
        fileManager: FileManager = .default
    ) {
        self.repoURL = repoURL
        self.packIndexManager = packIndexManager
        self.fileManager = fileManager
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
        
        // Try direct path (fastest - single file check)
        let prefix = String(hashLower.prefix(2))
        let suffix = String(hashLower.dropFirst(2))
        let directURL = objectsURL.appendingPathComponent("\(prefix)/\(suffix)")
        
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }
        
        // Not found
        return nil
    }
}
