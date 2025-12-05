import Foundation

public struct PackObjectLocation: Sendable {
    let hash: String
    let offset: Int
    let packURL: URL
}

// MARK: -
public protocol PackIndexProtocol: Sendable {
    /// Load and parse a pack index file
    func load(idxURL: URL, packURL: URL) throws
    
    /// Find the location of an object by hash
    func findObject(_ hash: String) -> PackObjectLocation?
}

// MARK: -
public final class PackIndex: @unchecked Sendable {
    // Loaded eagerly (small - 1KB)
    private var fanoutTable: [UInt32] = []
    private var objectCount: Int = 0
    private var version: Int = 2
    
    // File handle for lazy loading
    private var idxHandle: FileHandle?
    private var idxURL: URL?
    private var packURL: URL?
    
    // Section offsets in .idx file
    private var hashTableOffset: Int = 0
    private var crcTableOffset: Int = 0
    private var offsetTableOffset: Int = 0
    private var largeOffsetTableOffset: Int = 0
}

// MARK: - PackIndexProtocol
extension PackIndex: PackIndexProtocol {
    public func load(idxURL: URL, packURL: URL) throws {
        self.idxURL = idxURL
        self.packURL = packURL
        
        let handle = try FileHandle(forReadingFrom: idxURL)
        self.idxHandle = handle
        
        // Read header (8 bytes)
        guard let headerData = try handle.read(upToCount: 8) else {
            throw PackIndexError.corruptedData
        }
        
        var offset = 0
        let magic = headerData.readUInt32(at: &offset)
        let versionRead = headerData.readUInt32(at: &offset)
        
        guard magic == 0xff744f63, versionRead == 2 else {
            throw PackIndexError.unsupportedPackVersion
        }
        
        self.version = Int(versionRead)
        
        // Read fanout table (256 × 4 bytes = 1KB)
        guard let fanoutData = try handle.read(upToCount: 1024) else {
            throw PackIndexError.corruptedData
        }
        
        var fanoutOffset = 0
        for _ in 0..<256 {
            fanoutTable.append(fanoutData.readUInt32(at: &fanoutOffset))
        }
        
        objectCount = Int(fanoutTable[255])
        
        // Calculate section offsets
        hashTableOffset = 8 + 1024  // header + fanout
        crcTableOffset = hashTableOffset + (objectCount * 20)
        offsetTableOffset = crcTableOffset + (objectCount * 4)
        largeOffsetTableOffset = offsetTableOffset + (objectCount * 4)
    }
    
    public func findObject(_ hash: String) -> PackObjectLocation? {
        let hashLower = hash.lowercased()
        
        guard let firstByte = UInt8(hash.prefix(2), radix: 16) else {
            return nil
        }
        
        let rangeStart = firstByte == 0 ? 0 : Int(fanoutTable[Int(firstByte) - 1])
        let rangeEnd = Int(fanoutTable[Int(firstByte)])
        
        guard rangeStart < rangeEnd else { return nil }
        
        // Search range directly (no cache)
        return try? searchRange(start: rangeStart, end: rangeEnd, targetHash: hashLower)
    }
}

// MARK: - Git Error
public enum PackIndexError: Error {
    case unsupportedPackVersion
    case objectNotFound
    case corruptedData
}

// MARK: - Private
private extension PackIndex {
    func searchRange(start: Int, end: Int, targetHash: String) throws -> PackObjectLocation? {
        guard let handle = idxHandle, let packURL = packURL else {
            throw PackIndexError.corruptedData
        }
        
        let count = end - start
        
        // Read hashes for this range
        let hashOffset = hashTableOffset + (start * 20)
        try handle.seek(toOffset: UInt64(hashOffset))
        
        guard let hashData = try handle.read(upToCount: count * 20) else {
            throw PackIndexError.corruptedData
        }
        
        var hashPos = 0
        for i in 0..<count {
            let hashBytes = hashData[hashPos..<hashPos + 20]
            let hashString = hashBytes.toHexString()
            
            if hashString == targetHash {
                // Found it! Now get the offset
                let offsetOffset = offsetTableOffset + ((start + i) * 4)
                try handle.seek(toOffset: UInt64(offsetOffset))
                
                guard let offsetData = try handle.read(upToCount: 4) else {
                    throw PackIndexError.corruptedData
                }
                
                var tempOffset = 0
                var off = offsetData.readUInt32(at: &tempOffset)
                
                // Handle large offset if needed
                if off & 0x80000000 != 0 {
                    let largeOffsetIndex = Int(off & 0x7fffffff)
                    let largeOffsetPosition = largeOffsetTableOffset + (largeOffsetIndex * 8)
                    try handle.seek(toOffset: UInt64(largeOffsetPosition))
                    
                    guard let largeOffsetData = try handle.read(upToCount: 8) else {
                        throw PackIndexError.corruptedData
                    }
                    
                    var tempLargeOffset = 0
                    let largeOffset = largeOffsetData.readUInt64(at: &tempLargeOffset, index: largeOffsetIndex)
                    off = UInt32(largeOffset)
                }
                
                return PackObjectLocation(
                    hash: hashString,
                    offset: Int(off),
                    packURL: packURL
                )
            }
            
            hashPos += 20
        }
        
        // Not found in this range
        return nil
    }
}
