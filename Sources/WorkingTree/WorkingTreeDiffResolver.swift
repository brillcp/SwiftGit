import Foundation
import CryptoKit

public struct DiffPair: Sendable {
    public let old: Blob?
    public let new: Blob?
    
    public init(old: Blob?, new: Blob?) {
        self.old = old
        self.new = new
    }
}

// MARK: - BlobLoaderProtocol
public protocol BlobLoaderProtocol: Actor {
    func loadBlob(hash: String) async throws -> Blob?
}

// MARK: - GitRepository conformance
extension GitRepository: BlobLoaderProtocol {
    public func loadBlob(hash: String) async throws -> Blob? {
        try await getBlob(hash)
    }
}

// MARK: - WorkingTreeDiffResolver

public actor WorkingTreeDiffResolver {
    private let repoURL: URL
    private let blobLoader: BlobLoaderProtocol
    private let fileManager: FileManager
    
    public init(
        repoURL: URL,
        blobLoader: BlobLoaderProtocol,
        fileManager: FileManager = .default
    ) {
        self.repoURL = repoURL
        self.blobLoader = blobLoader
        self.fileManager = fileManager
    }
    
    /// Resolve which blobs to compare for a working tree file
    public func resolveDiff(
        for file: WorkingTreeFile,
        headTree: [String: String],
        indexMap: [String: String]
    ) async throws -> DiffPair {
        let path = file.path
        
        switch (file.staged, file.unstaged) {
            
        // ✅ Untracked file (not in index, exists in working tree)
        case (nil, .untracked):
            return DiffPair(
                old: nil,
                new: try await loadWorkingBlob(path: path)
            )
            
        // ✅ Staged changes only (no working tree modifications)
        case (.added, nil):
            return DiffPair(
                old: nil,
                new: try await loadIndexBlob(path: path, indexMap: indexMap)
            )
            
        case (.modified, nil):
            return DiffPair(
                old: try await loadHeadBlob(path: path, headTree: headTree),
                new: try await loadIndexBlob(path: path, indexMap: indexMap)
            )
            
        case (.deleted, nil):
            return DiffPair(
                old: try await loadHeadBlob(path: path, headTree: headTree),
                new: nil
            )
            
        // ✅ Unstaged changes only (working tree modified)
        case (nil, .modified):
            return DiffPair(
                old: try await loadIndexBlob(path: path, indexMap: indexMap),
                new: try await loadWorkingBlob(path: path)
            )
            
        case (nil, .deleted):
            return DiffPair(
                old: try await loadIndexBlob(path: path, indexMap: indexMap),
                new: nil
            )
            
        // ✅ Both staged and unstaged (double modified)
        case (.added, .modified),
             (.modified, .modified):
            return DiffPair(
                old: try await loadIndexBlob(path: path, indexMap: indexMap),
                new: try await loadWorkingBlob(path: path)
            )
            
        case (.modified, .deleted):
            return DiffPair(
                old: try await loadIndexBlob(path: path, indexMap: indexMap),
                new: nil
            )
            
        case (.added, .deleted):
            return DiffPair(
                old: nil,
                new: nil
            )
            
        // ✅ Fallback
        default:
            // Try to find old version (prefer index, fallback to HEAD)
            let old: Blob?
            if let indexBlob = try await loadIndexBlob(path: path, indexMap: indexMap) {
                old = indexBlob
            } else {
                old = try await loadHeadBlob(path: path, headTree: headTree)
            }
            
            // Try to find new version (working tree)
            let new = try await loadWorkingBlob(path: path)
            return DiffPair(old: old, new: new)
        }
    }
}

// MARK: - Private Helpers

private extension WorkingTreeDiffResolver {
    
    /// Load blob from HEAD tree - uses repository's optimized path
    func loadHeadBlob(path: String, headTree: [String: String]) async throws -> Blob? {
        guard let hash = headTree[path] else { return nil }
        return try await blobLoader.loadBlob(hash: hash)
    }
    
    /// Load blob from index - uses repository's optimized path
    func loadIndexBlob(path: String, indexMap: [String: String]) async throws -> Blob? {
        guard let hash = indexMap[path] else { return nil }
        return try await blobLoader.loadBlob(hash: hash)
    }
    
    /// Load blob from working tree - OPTIMIZED with streaming for large files
    func loadWorkingBlob(path: String) async throws -> Blob? {
        let fileURL = repoURL.appendingPathComponent(path)
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        // Check file size
        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let fileSize = attrs[.size] as? UInt64 else {
            return nil
        }
        
        // For large files (> 10MB), stream
        if fileSize > 10_000_000 {
            return try await streamWorkingFile(fileURL: fileURL, fileSize: fileSize)
        } else {
            // Small files - load directly
            let data = try Data(contentsOf: fileURL)
            let hash = computeHash(data: data)
            return Blob(id: hash, data: data)
        }
    }
    
    /// Stream large working tree file in chunks
    func streamWorkingFile(fileURL: URL, fileSize: UInt64) async throws -> Blob {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }
        
        var data = Data()
        data.reserveCapacity(Int(fileSize))
        
        let chunkSize = 65536 // 64KB chunks
        
        while true {
            let chunk = fileHandle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        
        let hash = computeHash(data: data)
        return Blob(id: hash, data: data)
    }
    
    /// Compute Git blob hash: SHA1("blob <size>\0<content>")
    func computeHash(data: Data) -> String {
        let header = "blob \(data.count)\0"
        var combined = Data(header.utf8)
        combined.append(data)
        
        let hash = Insecure.SHA1.hash(data: combined)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
