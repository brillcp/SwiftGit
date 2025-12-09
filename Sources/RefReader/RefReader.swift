import Foundation

public protocol RefReaderProtocol: Actor {
    /// Get all refs (branches, tags, etc.)
    func getRefs() async throws -> [String: [GitRef]]
    
    /// Get HEAD commit SHA
    func getHEAD() async throws -> String?
    
    /// Get HEAD branch name (nil if detached)
    func getHEADBranch() async throws -> String?

    func getStashes() async throws -> [Stash]
}

// MARK: -
public actor RefReader {
    private let repoURL: URL
    private let fileManager: FileManager
    private let objectExistsCheck: ((String) async throws -> Bool)?
    private let cache: ObjectCacheProtocol
    
    public init(
        repoURL: URL,
        fileManager: FileManager = .default,
        objectExistsCheck: ((String) async throws -> Bool)? = nil,
        cache: ObjectCacheProtocol
    ) {
        self.repoURL = repoURL
        self.fileManager = fileManager
        self.objectExistsCheck = objectExistsCheck
        self.cache = cache
    }
}

// MARK: - RefReaderProtocol
extension RefReader: RefReaderProtocol {
    public func getRefs() async throws -> [String: [GitRef]] {
        // Check cache
        if let cached: [String: [GitRef]] = await cache.get(.refs) {
            return cached
        }
        
        var refsByName: [String: GitRef] = [:]
        
        // Read loose refs
        let looseHeads = try readLooseRefs(relativePath: "refs/heads", type: .localBranch)
        let looseRemotes = try readLooseRefs(relativePath: "refs/remotes", type: .remoteBranch)
        let looseTags = try readLooseRefs(relativePath: "refs/tags", type: .tag)
        
        for ref in looseHeads + looseRemotes + looseTags {
            let key = "\(ref.type):\(ref.name)"
            refsByName[key] = ref
        }
        
        // Read packed refs
        let packedRefs = try readPackedRefs()
        for ref in packedRefs {
            let key = "\(ref.type):\(ref.name)"
            if refsByName[key] == nil {
                refsByName[key] = ref
            }
        }
        
        // Group by commit hash
        let refs = Dictionary(grouping: refsByName.values, by: { $0.hash })
        
        // Cache it
        await cache.set(.refs, value: refs)
        
        return refs
    }
    
    public func getHEAD() async throws -> String? {
        // Check cache
        if let cached: String = await cache.get(.head) {
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
                if let objectExistsCheck {
                    result = try await objectExistsCheck(raw) ? raw : nil
                } else {
                    result = raw
                }
            } else {
                result = nil
            }
        }
        
        // Cache if successful
        if let result {
            await cache.set(.head, value: result)
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
        
        let refsHeads = "ref: refs/heads/"
        if headContent.hasPrefix(refsHeads) {
            return String(headContent.dropFirst(refsHeads.count))
        }
        
        return nil // Detached HEAD
    }
    
    public func getStashes() async throws -> [Stash] {
        let stashLogURL = gitURL.appendingPathComponent("logs/refs/stash")
        
        guard fileManager.fileExists(atPath: stashLogURL.path) else {
            return []
        }
        
        let content = try String(contentsOf: stashLogURL, encoding: .utf8)
        let lines = content.split(separator: String.newLine)
        
        var stashes: [Stash] = []
        
        for (index, line) in lines.enumerated().reversed() {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let metadata = parts[0].split(separator: " ")
            guard metadata.count >= 5 else { continue }
            
            let stashHash = String(metadata[1])
            
            // Verify object exists if check is available
            if let objectExistsCheck {
                guard try await objectExistsCheck(stashHash) else {
                    continue
                }
            }
            
            let message = String(parts[1])
            
            // Parse timestamp
            let timestampStr = String(metadata[3])
            let date: Date
            if let timestamp = TimeInterval(timestampStr) {
                date = Date(timeIntervalSince1970: timestamp)
            } else {
                date = Date()
            }
            
            stashes.append(
                Stash(
                    id: stashHash,
                    index: lines.count - index - 1,
                    message: message,
                    date: date
                )
            )
        }
        
        return stashes
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
        
        // Compute base components once for robust relative path derivation
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let baseCount = baseComponents.count
        
        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            
            // Derive the ref name as the path relative to baseURL using pathComponents
            let fileComponents = fileURL.standardizedFileURL.pathComponents
            guard fileComponents.count > baseCount else { continue }
            
            // Ensure the prefix matches; if not, fall back to dropping common prefix safely
            let hasCommonPrefix = zip(baseComponents, fileComponents).allSatisfy { $0 == $1 }
            let relativeComponents: [String]
            if hasCommonPrefix {
                relativeComponents = Array(fileComponents.dropFirst(baseCount))
            } else {
                // Fallback: use URL's path(relativeTo:) style construction by removing baseURL.path prefix if present
                let fullPath = fileURL.path
                let basePath = baseURL.path.hasSuffix("/") ? String(baseURL.path.dropLast()) : baseURL.path
                if fullPath.hasPrefix(basePath + "/") {
                    let startIndex = fullPath.index(fullPath.startIndex, offsetBy: basePath.count + 1)
                    relativeComponents = fullPath[startIndex...].split(separator: "/").map(String.init)
                } else {
                    // If we cannot determine a safe relative path, skip
                    continue
                }
            }
            let name = relativeComponents.joined(separator: "/")
            
            // Read just enough bytes for a SHA (40-64 chars + potential whitespace)
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe).prefix(128),
                  let content = String(data: data, encoding: .utf8) else {
                continue
            }
            
            // Get first line only
            let hash = content.split(separator: String.newLine, maxSplits: 1).first?
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
                guard peeledID.isValidSHA else {
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
            
            guard sha.isValidSHA else {
                continue // Skip invalid hash
            }
            
            let heads = "refs/heads/"
            let remotes = "refs/remotes/"
            let tags = "refs/tags/"
            
            if name.hasPrefix(heads) {
                refs.append(
                    GitRef(
                        name: String(name.dropFirst(heads.count)),
                        hash: sha,
                        type: .localBranch
                    )
                )
            } else if name.hasPrefix(remotes) {
                refs.append(
                    GitRef(
                        name: String(name.dropFirst(remotes.count)),
                        hash: sha,
                        type: .remoteBranch
                    )
                )
            } else if name.hasPrefix(tags) {
                refs.append(
                    GitRef(
                        name: String(name.dropFirst(tags.count)),
                        hash: sha,
                        type: .tag
                    )
                )
            }
        }
        
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
    
    func resolveReference(_ refPath: String) async throws -> String? {
        // 1. Try loose ref first (single file read - O(1))
        let refURL = gitURL.appendingPathComponent(refPath)
        
        if fileManager.fileExists(atPath: refURL.path) {
            let hash = try String(contentsOf: refURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            if hash.isValidSHA {
                if let objectExistsCheck {
                    return try await objectExistsCheck(hash) ? hash : nil
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
}
