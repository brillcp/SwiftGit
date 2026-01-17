import Foundation
import CommonCrypto

public protocol WorkingTreeReaderProtocol: Actor {
    func indexSnapshot() async throws -> GitIndexSnapshot

    /// Compute the current working tree status
    func computeStatus(snapshot: RepoSnapshot) async throws -> WorkingTreeStatus

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

        return compareStates(
            headTree: snapshot.headTree,
            index: snapshot.indexMap,
            workingTree: workingComplete,
            conflictedPaths: snapshot.conflictedPaths
        )
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

        let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let modDate = attrs[.modificationDate] as? Date,
              let sizeNum = attrs[.size] as? UInt64 else { return nil }

        let sizeMatches = sizeNum == UInt64(entry.size)
        let mtimeMatches = abs(modDate.timeIntervalSince(entry.mtime)) < 0.001

        if mtimeMatches && sizeMatches {
            return entry.sha1
        }

        let devAttr = attrs[.systemNumber] as? NSNumber
        let inoAttr = attrs[.systemFileNumber] as? NSNumber
        let dev = UInt64(devAttr?.uint64Value ?? 0)
        let ino = UInt64(inoAttr?.uint64Value ?? 0)
        let mtimeNs = UInt64(entry.mtimeNSec)
        let identity = FileIdentity(dev: dev, ino: ino, size: sizeNum, mtimeNs: mtimeNs)

        if let cached: String = await cache.get(.fileHash(identity: identity)) {
            return cached
        }

        let computed = try computeFileHash(at: fileURL)
        await cache.set(.fileHash(identity: identity), value: computed)

        return computed
    }

    func computeFileHash(at url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        try fileHandle.seek(toOffset: 0)

        let header = "blob \(fileSize)\0"

        var context = CC_SHA1_CTX()
        CC_SHA1_Init(&context)

        header.utf8.withContiguousStorageIfAvailable { ptr in
            _ = CC_SHA1_Update(&context, ptr.baseAddress, CC_LONG(ptr.count))
        }

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
        var indexedPaths = Set<String>(minimumCapacity: indexEntries.count)
        var indexedDirs = Set<String>(minimumCapacity: indexEntries.count)

        for entry in indexEntries {
            indexedPaths.insert(entry.path)

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

            if indexedPaths.contains(fullPath) {
                continue
            }

            let resourceValues = try itemURL.resourceValues(forKeys: [.isDirectoryKey])

            if resourceValues.isDirectory == true {
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
                let hash = try computeFileHash(at: itemURL)
                result[fullPath] = hash
            }
        }
    }

    func compareStates(
        headTree: [String: String],
        index: [String: String],
        workingTree: [String: String],
        conflictedPaths: Set<String>
    ) -> WorkingTreeStatus {
        var files: [String: WorkingTreeFile] = [:]
        let allPaths = Set(headTree.keys).union(index.keys).union(workingTree.keys)
        files.reserveCapacity(allPaths.count)

        var stagedDeletions: [String: String] = [:]
        var stagedAdditions: [String: String] = [:]
        var unstagedDeletions: [String: String] = [:]
        var unstagedAdditions: [String: String] = [:]

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
                    stagedAdditions[path] = indexOid
                }
            } else if let headOid = headOid {
                stagedDeletions[path] = headOid
            }

            // Unstaged changes (Index → Working Tree)
            if let workingOid = workingOid {
                if let indexOid = indexOid {
                    if workingOid != indexOid {
                        unstaged = .modified
                    }
                } else {
                    unstagedAdditions[path] = workingOid
                }
            } else if let indexOid = indexOid {
                unstagedDeletions[path] = indexOid
            }

            if staged != nil || unstaged != nil {
                files[path] = WorkingTreeFile(
                    path: path,
                    staged: staged,
                    unstaged: unstaged
                )
            }
        }

        // Detect renames
        detectRenames(
            deletions: stagedDeletions,
            additions: stagedAdditions,
            files: &files,
            isStaged: true
        )

        detectRenames(
            deletions: unstagedDeletions,
            additions: unstagedAdditions,
            files: &files,
            isStaged: false
        )

        // Mark conflicted files
        for path in conflictedPaths {
            files[path] = WorkingTreeFile(
                path: path,
                staged: .conflicted,
                unstaged: .conflicted
            )
        }

        return WorkingTreeStatus(files: files)
    }

    func detectRenames(
        deletions: [String: String],
        additions: [String: String],
        files: inout [String: WorkingTreeFile],
        isStaged: Bool
    ) {
        var hashToDeleted: [String: String] = [:]
        for (path, hash) in deletions {
            hashToDeleted[hash] = path
        }

        for (newPath, hash) in additions {
            if let oldPath = hashToDeleted[hash] {
                // Found a rename!
                let changeType = GitChangeType.renamed(from: oldPath)

                if isStaged {
                    files[newPath] = WorkingTreeFile(
                        path: newPath,
                        staged: changeType,
                        unstaged: files[newPath]?.unstaged
                    )
                    files.removeValue(forKey: oldPath)
                } else {
                    files[newPath] = WorkingTreeFile(
                        path: newPath,
                        staged: files[newPath]?.staged,
                        unstaged: changeType
                    )
                    files.removeValue(forKey: oldPath)
                }

                hashToDeleted.removeValue(forKey: hash)
            } else {
                // Real addition
                let changeType: GitChangeType = isStaged ? .added : .untracked
                if isStaged {
                    files[newPath] = WorkingTreeFile(
                        path: newPath,
                        staged: changeType,
                        unstaged: files[newPath]?.unstaged
                    )
                } else {
                    files[newPath] = WorkingTreeFile(
                        path: newPath,
                        staged: files[newPath]?.staged,
                        unstaged: changeType
                    )
                }
            }
        }

        // Real deletions
        for (path, _) in hashToDeleted {
            if isStaged {
                files[path] = WorkingTreeFile(
                    path: path,
                    staged: .deleted,
                    unstaged: files[path]?.unstaged
                )
            } else {
                files[path] = WorkingTreeFile(
                    path: path,
                    staged: files[path]?.staged,
                    unstaged: .deleted
                )
            }
        }
    }
}
