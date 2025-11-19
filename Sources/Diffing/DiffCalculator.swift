import Foundation

public protocol DiffCalculatorProtocol: Actor {
    /// Calculate diff between two tree states
    func calculateDiff(
        currentTree: [String: String],   // path -> blob hash
        parentTree: [String: String]?,   // path -> blob hash (nil for root commit)
        blobLoader: @Sendable (String) async throws -> Blob?
    ) async throws -> [String: CommitedFile]
}

// MARK: -
public actor DiffCalculator {
    public init() {}
}

// MARK: - GitDiffCalculatorProtocol
extension DiffCalculator: DiffCalculatorProtocol {
    public func calculateDiff(
        currentTree: [String: String],
        parentTree: [String: String]?,
        blobLoader: @Sendable (String) async throws -> Blob?
    ) async throws -> [String: CommitedFile] {
        // Root commit: everything is added
        guard let parentTree else {
            return try await buildAddedFiles(from: currentTree, blobLoader: blobLoader)
        }
        
        // Compare trees
        return try await compareTrees(
            current: currentTree,
            parent: parentTree,
            blobLoader: blobLoader
        )
    }
}

// MARK: - Private Helpers
private extension DiffCalculator {
    func buildAddedFiles(
        from paths: [String: String],
        blobLoader: @Sendable (String) async throws -> Blob?
    ) async throws -> [String: CommitedFile] {
        var result: [String: CommitedFile] = [:]
        
        for (path, blobHash) in paths {
            guard let blob = try await blobLoader(blobHash) else { continue }
            
            result[path] = CommitedFile(
                path: path,
                blob: blob,
                changeType: .added
            )
        }
        
        return result
    }
    
    func compareTrees(
        current: [String: String],
        parent: [String: String],
        blobLoader: @Sendable (String) async throws -> Blob?
    ) async throws -> [String: CommitedFile] {
        var result: [String: CommitedFile] = [:]
        
        // Build reverse maps for rename detection
        let currentByBlob = Dictionary(grouping: current.keys, by: { current[$0]! })
            .compactMapValues { $0.first }
        let parentByBlob = Dictionary(grouping: parent.keys, by: { parent[$0]! })
            .compactMapValues { $0.first }
        
        var renamedBlobIds = Set<String>()
        
        // 1. Detect renames
        let commonBlobIds = Set(currentByBlob.keys).intersection(parentByBlob.keys)
        
        for blobId in commonBlobIds {
            let oldPath = parentByBlob[blobId]!
            let newPath = currentByBlob[blobId]!
            
            guard oldPath != newPath else { continue }
            
            if let blob = try await blobLoader(blobId) {
                result[newPath] = CommitedFile(
                    path: newPath,
                    blob: blob,
                    changeType: .renamed(from: oldPath)
                )
                renamedBlobIds.insert(blobId)
            }
        }
        
        // 2. Detect added and modified
        for (path, blobHash) in current where !renamedBlobIds.contains(blobHash) {
            if let parentBlobHash = parent[path] {
                if parentBlobHash != blobHash {
                    // Modified
                    if let blob = try await blobLoader(blobHash) {
                        result[path] = CommitedFile(
                            path: path,
                            blob: blob,
                            changeType: .modified
                        )
                    }
                }
            } else {
                // Added
                if let blob = try await blobLoader(blobHash) {
                    result[path] = CommitedFile(
                        path: path,
                        blob: blob,
                        changeType: .added
                    )
                }
            }
        }
        
        // 3. Detect deleted
        for (path, blobHash) in parent where !renamedBlobIds.contains(blobHash) {
            if current[path] == nil {
                if let blob = try await blobLoader(blobHash) {
                    result[path] = CommitedFile(
                        path: path,
                        blob: blob,
                        changeType: .deleted
                    )
                }
            }
        }
        
        return result
    }
}
