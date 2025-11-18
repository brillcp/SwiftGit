import Foundation

struct PackObjectLocation: Sendable {
    let hash: String
    let offset: Int
    let packURL: URL
}

// MARK: -
protocol PackIndexProtocol: Sendable {
    /// Load and parse a pack index file
    func load(idxURL: URL, packURL: URL) throws
    
    /// Find the location of an object by hash
    func findObject(_ hash: String) -> PackObjectLocation?
    
    /// Get all hashes in this pack
    func getAllHashes() -> Set<String>
    
    /// Clear index data
    func clear()
}

// MARK: -
final class PackIndex: @unchecked Sendable {
    private var entries: [String: PackObjectLocation] = [:]
}

// MARK: - PackIndexProtocol
extension PackIndex: PackIndexProtocol {
    func load(idxURL: URL, packURL: URL) throws {
        let idxData = try Data(contentsOf: idxURL)
        
        guard idxData.count > 8 else { return }
        
        var offset = 0
        let magic = idxData.readUInt32(at: &offset)
        let version = idxData.readUInt32(at: &offset)
        
        guard magic == 0xff744f63, version == 2 else {
            throw PackIndexError.unsupportedPackVersion
        }
        
        // Read fanout table to get object count
        var objectCount = 0
        for _ in 0..<256 {
            objectCount = Int(idxData.readUInt32(at: &offset))
        }
        
        // Read all hashes
        var hashes: [String] = []
        for _ in 0..<objectCount {
            let hashData = idxData[offset..<offset+20]
            hashes.append(hashData.map { String(format: "%02x", $0) }.joined())
            offset += 20
        }
        
        // Skip CRCs
        offset += objectCount * 4
        
        // Read offsets
        var offsets: [Int] = []
        var largeOffsetIndices: [(index: Int, largeOffsetIndex: Int)] = []
        
        for i in 0..<objectCount {
            let off = idxData.readUInt32(at: &offset)
            if off & 0x80000000 != 0 {
                let largeOffsetIndex = Int(off & 0x7fffffff)
                largeOffsetIndices.append((index: i, largeOffsetIndex: largeOffsetIndex))
                offsets.append(0)
            } else {
                offsets.append(Int(off))
            }
        }
        
        // Handle large offsets
        if !largeOffsetIndices.isEmpty {
            for (index, largeOffsetIndex) in largeOffsetIndices {
                let largeOffset = idxData.readUInt64(at: &offset, index: largeOffsetIndex)
                offsets[index] = Int(largeOffset)
            }
        }
        
        // Build entries dictionary
        for (hash, offset) in zip(hashes, offsets) {
            entries[hash] = PackObjectLocation(
                hash: hash,
                offset: offset,
                packURL: packURL
            )
        }
    }
    
    func findObject(_ hash: String) -> PackObjectLocation? {
        entries[hash]
    }
    
    func getAllHashes() -> Set<String> {
        Set(entries.keys)
    }
    
    func clear() {
        entries.removeAll()
    }
}

// MARK: - Git Error
enum PackIndexError: Error {
    case unsupportedPackVersion
    case objectNotFound
    case corruptedData
}
