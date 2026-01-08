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

        // Track which files we've processed
        var processedCurrent = Set<String>()
        var processedParent = Set<String>()

        // 1. Process all files in current tree
        for (newPath, newBlobHash) in current {
            // Check if this exact path existed in parent
            if let parentBlobHash = parent[newPath] {
                if parentBlobHash == newBlobHash {
                    // Same file, unchanged - skip
                    processedCurrent.insert(newPath)
                    processedParent.insert(newPath)
                    continue
                } else {
                    // Same path, different blob - modified
                    if let blob = try await blobLoader(newBlobHash) {
                        result[newPath] = CommitedFile(
                            path: newPath,
                            blob: blob,
                            changeType: .modified
                        )
                    }
                    processedCurrent.insert(newPath)
                    processedParent.insert(newPath)
                    continue
                }
            }

            // Path doesn't exist in parent - could be added or renamed
            // Check if this blob existed at a different path in parent
            if let oldPath = parent.first(where: { $0.value == newBlobHash })?.key,
               current[oldPath] == nil {  // Old path must be gone for it to be a rename
                // This is a rename
                if let blob = try await blobLoader(newBlobHash) {
                    result[newPath] = CommitedFile(
                        path: newPath,
                        blob: blob,
                        changeType: .renamed(from: oldPath)
                    )
                }
                processedCurrent.insert(newPath)
                processedParent.insert(oldPath)
            } else {
                // This is a new file
                if let blob = try await blobLoader(newBlobHash) {
                    result[newPath] = CommitedFile(
                        path: newPath,
                        blob: blob,
                        changeType: .added
                    )
                }
                processedCurrent.insert(newPath)
            }
        }

        // 2. Detect deleted files (files in parent but not processed yet)
        for (oldPath, oldBlobHash) in parent where !processedParent.contains(oldPath) {
            if let blob = try await blobLoader(oldBlobHash) {
                result[oldPath] = CommitedFile(
                    path: oldPath,
                    blob: blob,
                    changeType: .deleted
                )
            }
        }

        return result
    }
}