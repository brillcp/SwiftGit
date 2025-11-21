import Foundation

public protocol GitIndexReaderProtocol: Actor {
    /// Read the Git index file
    func readIndex(at url: URL) async throws -> GitIndexSnapshot
    
    /// Get a specific index entry by path (O(1) lookup)
    func getEntry(for path: String, at url: URL) async throws -> IndexEntry?
}

// MARK: -
public actor GitIndexReader: GitIndexReaderProtocol {
    // Cache
    private var cachedSnapshot: GitIndexSnapshot?
    private var cachedModificationDate: Date?
    private var cacheURL: URL?
    
    public init() {}
    
    public func readIndex(at url: URL) async throws -> GitIndexSnapshot {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw GitIndexError.fileNotFound(url)
        }
        
        // Check cache
        let modDate = try url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        
        if let cached = cachedSnapshot,
           let cachedDate = cachedModificationDate,
           let cachedURL = cacheURL,
           cachedURL == url,
           cachedDate == modDate {
            return cached
        }
        
        // Parse index off main thread
        let snapshot = try await Task.detached(priority: .userInitiated) {
            let data = try Data(contentsOf: url)
            return try Self.parse(data)
        }.value
        
        // Cache result
        cachedSnapshot = snapshot
        cachedModificationDate = modDate
        cacheURL = url
        
        return snapshot
    }
    
    public func getEntry(for path: String, at url: URL) async throws -> IndexEntry? {
        let snapshot = try await readIndex(at: url)
        return snapshot[path]
    }
    
    /// Invalidate cache (call when index is modified)
    public func invalidateCache() {
        cachedSnapshot = nil
        cachedModificationDate = nil
        cacheURL = nil
    }
}

// MARK: - Error
public enum GitIndexError: Error, CustomStringConvertible {
    case invalidHeader
    case unsupportedVersion(Int)
    case corruptedIndex
    case truncatedEntry(at: Int)
    case fileNotFound(URL)
    
    public var description: String {
        switch self {
        case .invalidHeader:
            return "Git index has invalid header"
        case .unsupportedVersion(let v):
            return "Git index version \(v) is not supported (only v2 and v3)"
        case .corruptedIndex:
            return "Git index is corrupted"
        case .truncatedEntry(let index):
            return "Git index entry \(index) is truncated"
        case .fileNotFound(let url):
            return "Git index not found at \(url.path)"
        }
    }
}


// MARK: - Private Parsing
private extension GitIndexReader {
    static func parse(_ data: Data) throws -> GitIndexSnapshot {
        var offset = 0
        
        // Validate minimum size
        guard data.count >= 12 else {
            throw GitIndexError.invalidHeader
        }
        
        // Read header: "DIRC" signature
        let sigData = data[0..<4]
        guard String(bytes: sigData, encoding: .ascii) == "DIRC" else {
            throw GitIndexError.invalidHeader
        }
        offset = 4
        
        // Read version
        let version = Int(data.readUInt32(at: &offset))
        guard version == 2 || version == 3 else {
            throw GitIndexError.unsupportedVersion(version)
        }
        
        // Read entry count
        let entryCount = Int(data.readUInt32(at: &offset))
        
        // Parse entries
        var entries: [IndexEntry] = []
        entries.reserveCapacity(entryCount)
        
        for entryIndex in 0..<entryCount {
            let entry = try parseEntry(from: data, offset: &offset, entryIndex: entryIndex)
            entries.append(entry)
        }
        
        return GitIndexSnapshot(entries: entries, version: version)
    }
    
    static func parseEntry(
        from data: Data,
        offset: inout Int,
        entryIndex: Int
    ) throws -> IndexEntry {
        let startOffset = offset
        
        // Validate minimum entry size (62 bytes before path)
        guard offset + 62 <= data.count else {
            throw GitIndexError.truncatedEntry(at: entryIndex)
        }
        
        // Read timestamps
        let mtime = data.readUInt32(at: &offset)
        let mtimeNSec = data.readUInt32(at: &offset)
        
        // Convert to Date
        let mtimeSeconds = Double(mtime) + (Double(mtimeNSec) / 1_000_000_000.0)
        let modificationDate = Date(timeIntervalSince1970: mtimeSeconds)
        
        // Read metadata
        let mode = data.readUInt32(at: &offset)
        let size = data.readUInt32(at: &offset)
        
        // Read SHA-1 (20 bytes)
        guard offset + 20 <= data.count else {
            throw GitIndexError.truncatedEntry(at: entryIndex)
        }
        let sha1 = data.readHex20(at: &offset)
        
        // Read flags (2 bytes)
        guard offset + 2 <= data.count else {
            throw GitIndexError.truncatedEntry(at: entryIndex)
        }
        _ = data.readUInt16(at: &offset)
        
        // Read NUL-terminated path
        guard offset < data.count else {
            throw GitIndexError.truncatedEntry(at: entryIndex)
        }
        
        let pathStart = offset
        while offset < data.count && data[offset] != 0 {
            offset += 1
        }
        
        guard offset < data.count else {
            throw GitIndexError.truncatedEntry(at: entryIndex)
        }
        
        let rawPath = String(decoding: data[pathStart..<offset], as: UTF8.self)
        offset += 1 // Skip NUL
        
        let path = normalizeIndexPath(rawPath)
        
        // Align to 8-byte boundary
        let entryLength = offset - startOffset
        let padding = (8 - (entryLength % 8)) % 8
        guard offset + padding <= data.count else {
            throw GitIndexError.truncatedEntry(at: entryIndex)
        }
        offset += padding
        
        // Parse file mode
        guard let fileMode = FileMode(rawValue: mode) else {
            // Fallback to regular if mode is unrecognized
            return IndexEntry(
                path: path,
                sha1: sha1,
                size: size,
                mtime: modificationDate,
                fileMode: .regular
            )
        }
        
        return IndexEntry(
            path: path,
            sha1: sha1,
            size: size,
            mtime: modificationDate,
            fileMode: fileMode
        )
    }
    
    static func normalizeIndexPath(_ path: String) -> String {
        if path.hasPrefix("./") {
            return String(path.dropFirst(2))
        }
        return path
    }
}
