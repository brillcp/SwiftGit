import Foundation
import CommonCrypto

public protocol WorkingTreeReaderProtocol: Actor {
    func indexSnapshot() async throws -> GitIndexSnapshot

    /// Compute the current working tree status
    func computeStatus(snapshot: RepoSnapshot) async throws -> WorkingTreeStatus

    /// Get untracked files
    func untrackedFiles() async throws -> [String]

    /// Invalidate index cache
    func invalidateIndexCache() async
}

// MARK: -
public actor WorkingTreeReader {
    private let repoURL: URL
    private let fileManager: FileManager
    private let indexReader: GitIndexReaderProtocol
    private let cache: ObjectCacheProtocol

    public init(
        repoURL: URL,
        indexReader: GitIndexReaderProtocol,
        fileManager: FileManager = .default,
        cache: ObjectCacheProtocol
    ) {
        self.repoURL = repoURL
        self.fileManager = fileManager
        self.indexReader = indexReader
        self.cache = cache
    }
}

// MARK: - WorkingTreeReaderProtocol
extension WorkingTreeReader: WorkingTreeReaderProtocol {
    public func indexSnapshot() async throws -> GitIndexSnapshot {
        do {
            return try await indexReader.readIndex(at: indexURL)
        } catch GitIndexError.fileNotFound {
            return GitIndexSnapshot(entries: [], version: 2)
        }
    }

    public func computeStatus(snapshot: RepoSnapshot) async throws -> WorkingTreeStatus {
        let untracked = try await scanForUntrackedFiles(indexEntries: snapshot.index)
        var workingComplete = try await checkWorkingTreeAgainstIndex(indexEntries: snapshot.index)

        workingComplete.merge(untracked) { _, new in new }

        var status = compareStates(
            headTree: snapshot.headTree,
            index: snapshot.indexMap,
            workingTree: workingComplete
        )

        // Mark conflicted files (now available from snapshot)
        for path in snapshot.conflictedPaths {
            status.files[path] = WorkingTreeFile(
                path: path,
                staged: .conflicted,
                unstaged: .conflicted
            )
        }

        return status
    }

    public func untrackedFiles() async throws -> [String] {
        let indexEntries = try await indexSnapshot()
        let untracked = try await scanForUntrackedFiles(indexEntries: indexEntries.entries)
        return Array(untracked.keys)
    }

    public func invalidateIndexCache() async {
        let url = indexURL
        await cache.remove(.indexSnapshot(url: url))
    }
}

// MARK: - Private
private extension WorkingTreeReader {
    var gitURL: URL {
        repoURL.appendingPathComponent(GitPath.git.rawValue)
    }

    var indexURL: URL {
        gitURL.appendingPathComponent(GitPath.index.rawValue)
    }

    func checkWorkingTreeAgainstIndex(indexEntries: [IndexEntry]) async throws -> [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(indexEntries.count)

        for entry in indexEntries {
            let fileURL = repoURL.appendingPathComponent(entry.path)

            if let hash = try await checkFile(entry: entry, fileURL: fileURL) {
                result[entry.path] = hash
            }
        }

        return result
    }

    func checkFile(entry: IndexEntry, fileURL: URL) async throws -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil // File deleted
        }

        // Get file stats - fast syscall
        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let modDate = attrs[.modificationDate] as? Date,
              let sizeNum = attrs[.size] as? UInt64 else { return nil }

        let sizeMatches = sizeNum == UInt64(entry.size)
        let mtimeMatches = abs(modDate.timeIntervalSince(entry.mtime)) < 0.001

        // Git's optimization: if mtime + size match, reuse hash
        if mtimeMatches && sizeMatches {
            // File unchanged - reuse hash from index (NO HASHING!)
            return entry.sha1
        }

        // Check cache by file identity (inode + dev + size + mtime)
        let devAttr = attrs[.systemNumber] as? NSNumber
        let inoAttr = attrs[.systemFileNumber] as? NSNumber
        let dev = UInt64(devAttr?.uint64Value ?? 0)
        let ino = UInt64(inoAttr?.uint64Value ?? 0)
        let mtimeNs = UInt64(entry.mtimeNSec)
        let identity = FileIdentity(dev: dev, ino: ino, size: sizeNum, mtimeNs: mtimeNs)

        if let cached: String = await cache.get(.fileHash(identity: identity)) {
            return cached
        }

        // Compute hash
        let computed = try computeFileHash(at: fileURL)

        // Cache with eviction
        await cache.set(.fileHash(identity: identity), value: computed)

        return computed
    }

    func computeFileHash(at url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        // Git blob format: "blob <size>\0<content>"
        let header = "blob \(fileSize)\0"

        var context = CC_SHA1_CTX()
        CC_SHA1_Init(&context)

        // Hash header
        header.utf8.withContiguousStorageIfAvailable { ptr in
            _ = CC_SHA1_Update(&context, ptr.baseAddress, CC_LONG(ptr.count))
        }

        // Stream file content in 64KB chunks
        while true {
            let chunk = fileHandle.readData(ofLength: 65536)
            if chunk.isEmpty { break }

            chunk.withUnsafeBytes { ptr in
                _ = CC_SHA1_Update(&context, ptr.baseAddress, CC_LONG(chunk.count))
            }
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        CC_SHA1_Final(&digest, &context)

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func scanForUntrackedFiles(indexEntries: [IndexEntry]) async throws -> [String: String] {
        // Build indexed paths and dirs
        var indexedPaths = Set<String>(minimumCapacity: indexEntries.count)
        var indexedDirs = Set<String>(minimumCapacity: indexEntries.count)

        for entry in indexEntries {
            indexedPaths.insert(entry.path)

            // Add all parent directories
            var path = entry.path
            while let slashIdx = path.lastIndex(of: "/") {
                path = String(path[..<slashIdx])
                indexedDirs.insert(path)
            }
        }

        var result: [String: String] = [:]

        try await scanDirectoryForUntracked(
            at: repoURL,
            relativePath: "",
            indexedPaths: indexedPaths,
            indexedDirs: indexedDirs,
            result: &result
        )

        return result
    }

    func scanDirectoryForUntracked(
        at dirURL: URL,
        relativePath: String,
        indexedPaths: Set<String>,
        indexedDirs: Set<String>,
        result: inout [String: String]
    ) async throws {
        let contents = try fileManager.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for itemURL in contents {
            let name = itemURL.lastPathComponent

            if name == GitPath.git.rawValue { continue }

            let fullPath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"

            // Skip if already in index
            if indexedPaths.contains(fullPath) {
                continue
            }

            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])

            if resourceValues.isDirectory == true {
                // Only recurse if directory isn't fully tracked
                if !indexedDirs.contains(fullPath) {
                    try await scanDirectoryForUntracked(
                        at: itemURL,
                        relativePath: fullPath,
                        indexedPaths: indexedPaths,
                        indexedDirs: indexedDirs,
                        result: &result
                    )
                }
            } else {
                // Untracked file - compute hash
                let hash = try computeFileHash(at: itemURL)
                result[fullPath] = hash
            }
        }
    }

    func compareStates(
        headTree: [String: String],
        index: [String: String],
        workingTree: [String: String]
    ) -> WorkingTreeStatus {
        var files: [String: WorkingTreeFile] = [:]
        let allPaths = Set(headTree.keys).union(index.keys).union(workingTree.keys)
        files.reserveCapacity(allPaths.count)

        for path in allPaths {
            let headOid = headTree[path]
            let indexOid = index[path]
            let workingOid = workingTree[path]

            var staged: GitChangeType?
            var unstaged: GitChangeType?

            // Staged changes (HEAD → Index)
            if let indexOid = indexOid {
                if let headOid = headOid {
                    if indexOid != headOid {
                        staged = .modified
                    }
                } else {
                    staged = .added
                }
            } else if headOid != nil {
                staged = .deleted
            }

            // Unstaged changes (Index → Working Tree)
            if let workingOid = workingOid {
                if let indexOid = indexOid {
                    if workingOid != indexOid {
                        unstaged = .modified
                    }
                } else {
                    unstaged = .untracked
                }
            } else if indexOid != nil {
                unstaged = .deleted
            }

            // Only add if there are changes
            if staged != nil || unstaged != nil {
                files[path] = WorkingTreeFile(
                    path: path,
                    staged: staged,
                    unstaged: unstaged
                )
            }
        }

        return WorkingTreeStatus(files: files)
    }
}