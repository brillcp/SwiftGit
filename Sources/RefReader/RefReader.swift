import Foundation

public protocol RefReaderProtocol: Actor {
    /// Get all refs (branches, tags, etc.)
    func getRefs() async throws -> [GitRef]
    
    /// Resolve a reference path to a commit SHA
    func resolveReference(_ refPath: String) async throws -> String?
    
    /// Get HEAD commit SHA
    func getHEAD() async throws -> String?
    
    /// Get HEAD branch name (nil if detached)
    func getHEADBranch() async throws -> String?
}

// MARK: -
public actor RefReader {
    private let repoURL: URL
    private let fileManager: FileManager
    private let objectExistsCheck: ((String) async throws -> Bool)?
    
    // Optional cache
    private var cachedRefs: [GitRef]?
    private var cachedHEAD: String?
    private var cacheTime: Date?
    private let cacheTimeout: TimeInterval = 1.0 // 1 second cache
    
    public init(
        repoURL: URL,
        fileManager: FileManager = .default,
        objectExistsCheck: ((String) async throws -> Bool)? = nil
    ) {
        self.repoURL = repoURL
        self.fileManager = fileManager
        self.objectExistsCheck = objectExistsCheck
    }
}

// MARK: - RefReaderProtocol
extension RefReader: RefReaderProtocol {
    public func getRefs() async throws -> [GitRef] {
        // Check cache
        if let cached = cachedRefs,
           let cacheTime = cacheTime,
           Date().timeIntervalSince(cacheTime) < cacheTimeout {
            return cached
        }
        
        var refs: [GitRef] = []
        
        // Read loose refs
        refs.append(contentsOf: try readLooseRefs(relativePath: "refs/heads", type: .localBranch))
        refs.append(contentsOf: try readLooseRefs(relativePath: "refs/remotes", type: .remoteBranch))
        refs.append(contentsOf: try readLooseRefs(relativePath: "refs/tags", type: .tag))
        
        // Read packed refs
        refs.append(contentsOf: try readPackedRefs())
        
        // Cache the result
        cachedRefs = refs
        self.cacheTime = Date()
        
        return refs
    }
    
    public func resolveReference(_ refPath: String) async throws -> String? {
        // 1. Try loose ref first (single file read - O(1))
        let refURL = gitURL.appendingPathComponent(refPath)
        
        if fileManager.fileExists(atPath: refURL.path) {
            let hash = try String(contentsOf: refURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if hash.isValidSHA {
                if let existsCheck = objectExistsCheck {
                    return try await existsCheck(hash) ? hash : nil
                }
                return hash
            }
        }
        
        // 2. Search packed-refs directly (single file read, linear scan)
        let packedURL = gitURL.appendingPathComponent(GitPath.packedRefs.rawValue)
        
        guard fileManager.fileExists(atPath: packedURL.path) else {
            return nil
        }
        
        let content = try String(contentsOf: packedURL, encoding: .utf8)
        let lines = content.split(whereSeparator: \.isNewline)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("^") {
                continue
            }
            
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let sha = String(parts[0])
            let name = String(parts[1])
            
            // Direct comparison - packed-refs has full path "refs/heads/main"
            if name == refPath {
                if sha.isValidSHA {
                    if let existsCheck = objectExistsCheck {
                        return try await existsCheck(sha) ? sha : nil
                    }
                    return sha
                }
            }
        }
        
        return nil
    }
    
    public func getHEAD() async throws -> String? {
        // Check cache
        if let cached = cachedHEAD,
           let cacheTime = cacheTime,
           Date().timeIntervalSince(cacheTime) < cacheTimeout {
            return cached
        }
        
        let headURL = gitURL.appendingPathComponent(GitPath.head.rawValue)
        
        guard fileManager.fileExists(atPath: headURL.path) else {
            return nil
        }
        
        let raw = try String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        let result: String?
        
        if raw.hasPrefix("ref: ") {
            let refPath = String(raw.dropFirst(5))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Resolve the reference
            result = try await resolveReference(refPath)
        } else {
            // Detached HEAD - raw should be a commit hash
            if raw.isValidSHA {
                // Optionally verify object exists
                if let existsCheck = objectExistsCheck {
                    result = try await existsCheck(raw) ? raw : nil
                } else {
                    result = raw
                }
            } else {
                result = nil
            }
        }
        
        // Cache if successful
        if let result = result {
            cachedHEAD = result
            self.cacheTime = Date()
        }
        
        return result
    }
    
    public func getHEADBranch() async throws -> String? {
        let headURL = gitURL.appendingPathComponent(GitPath.head.rawValue)
        
        guard fileManager.fileExists(atPath: headURL.path) else {
            return nil
        }
        
        let headContent = try String(contentsOf: headURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if headContent.hasPrefix("ref: refs/heads/") {
            return String(headContent.dropFirst("ref: refs/heads/".count))
        }
        
        return nil // Detached HEAD
    }
}

// MARK: - Private Methods
private extension RefReader {
    var gitURL: URL {
        repoURL.appendingPathComponent(GitPath.git.rawValue)
    }

    /// Read loose refs from a directory
    func readLooseRefs(relativePath: String, type: RefType) throws -> [GitRef] {
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
        
        let basePath = baseURL.path
        let basePathLength = basePath.count + 1
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            
            // Extract name efficiently
            let fullPath = fileURL.path
            guard fullPath.count > basePathLength else { continue }
            let name = String(fullPath.dropFirst(basePathLength))
            
            // Read just enough bytes for a SHA (40-64 chars + potential whitespace)
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe).prefix(128),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            
            // Get first line only
            let hash = content.split(separator: "\n", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            
            // Validate before adding
            guard hash.isValidSHA else { continue }
            
            refs.append(GitRef(name: name, hash: hash, type: type))
        }
        
        return refs
    }
    
    /// Read packed-refs file
    func readPackedRefs() throws -> [GitRef] {
        let packedURL = gitURL.appendingPathComponent(GitPath.packedRefs.rawValue)
        
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
                
                // Validate peeled hash
                guard peeledID.count == 40, peeledID.allSatisfy({ $0.isHexDigit }) else {
                    continue
                }
                
                if let last = refs.last {
                    peeledMap[last.hash] = peeledID
                }
                continue
            }
            
            let parts = s.split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let sha = String(parts[0])
            let name = String(parts[1])
            
            // Validate SHA-1 hash (40 hex characters)
            guard sha.count == 40, sha.allSatisfy({ $0.isHexDigit }) else {
                continue // Skip invalid hash
            }
            
            if name.hasPrefix("refs/heads/") {
                refs.append(
                    GitRef(
                        name: String(name.dropFirst("refs/heads/".count)),
                        hash: sha,
                        type: .localBranch
                    )
                )
            } else if name.hasPrefix("refs/remotes/") {
                refs.append(
                    GitRef(
                        name: String(name.dropFirst("refs/remotes/".count)),
                        hash: sha,
                        type: .remoteBranch
                    )
                )
            } else if name.hasPrefix("refs/tags/") {
                refs.append(
                    GitRef(
                        name: String(name.dropFirst("refs/tags/".count)),
                        hash: sha,
                        type: .tag
                    )
                )
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
