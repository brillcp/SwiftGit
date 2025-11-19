import Foundation

public struct PackObject: Sendable {
    let hash: String
    let type: ObjectType
    let data: Data
}

public enum ObjectType: String, Sendable {
    case commit
    case tree
    case blob
    case tag
}

public protocol PackFileReaderProtocol: Actor {
    /// Check if pack file is memory-mapped
    var isMapped: Bool { get }

    /// Read object at a specific offset in pack file
    func readObject(at location: PackObjectLocation, packIndex: PackIndexProtocol) throws -> PackObject

    /// Unmap pack file if mapped (to reduce memory pressure)
    func unmap()
}

// MARK: -
public actor PackFileReader: @unchecked Sendable {
    private let deltaResolver: DeltaResolverProtocol
    
    // Pack file cache (URL -> Data)
    private var packCache: [URL: Data] = [:]
    
    public var isMapped: Bool {
        !packCache.isEmpty
    }
    
    public init(deltaResolver: DeltaResolverProtocol = DeltaResolver()) {
        self.deltaResolver = deltaResolver
    }
}

// MARK: - PackFileReaderProtocol
extension PackFileReader: PackFileReaderProtocol {
    public func readObject(at location: PackObjectLocation, packIndex: PackIndexProtocol) throws -> PackObject {
        let packData = try getPackData(for: location.packURL)
        
        // Build hash->offset map from pack index for REF_DELTA resolution
        var hashToOffset: [String: Int] = [:]
        for hash in packIndex.getAllHashes() {
            if let loc = packIndex.findObject(hash) {
                hashToOffset[hash] = loc.offset
            }
        }
        
        // Read and resolve the object (handles deltas recursively)
        var cache: [Int: (type: String, data: Data)] = [:]
        
        guard let (typeStr, data) = try readPackObjectAtOffset(
            packData: packData,
            offset: location.offset,
            hashToOffset: hashToOffset,
            cache: &cache
        ) else {
            throw PackError.objectNotFound
        }
        
        guard let type = ObjectType(rawValue: typeStr) else {
            throw PackError.unsupportedObjectType(typeStr)
        }
        
        return PackObject(hash: location.hash, type: type, data: data)
    }
    
    public func unmap() {
        packCache.removeAll()
    }
}

// MARK: - Private Helpers
private extension PackFileReader {
    func getPackData(for url: URL) throws -> Data {
        if let cached = packCache[url] {
            return cached
        }
        
        // Memory-map the pack file
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        packCache[url] = data
        return data
    }
    
    func readPackObjectAtOffset(
        packData: Data,
        offset: Int,
        hashToOffset: [String: Int],
        cache: inout [Int: (type: String, data: Data)]
    ) throws -> (String, Data)? {
        if let cached = cache[offset] { return cached }
        
        var pos = offset
        guard pos < packData.count else { return nil }
        
        // Read object header (variable length)
        var byte = packData[pos]
        pos += 1
        
        let type = Int((byte >> 4) & 0x07)
        var size = Int(byte & 0x0f)
        var shift = 4
        
        // Read variable-length size
        while byte & 0x80 != 0 {
            guard pos < packData.count else { return nil }
            byte = packData[pos]
            pos += 1
            size |= Int(byte & 0x7f) << shift
            shift += 7
        }
        
        switch type {
        case 1, 2, 3, 4:
            // Non-delta types: decompress and return
            guard pos < packData.count else { return nil }
            let compressedData = packData.subdata(in: pos..<packData.count)
            let decompressed = compressedData.decompressed
            let actualData = decompressed.prefix(size)
            
            let typeStr: String
            switch type {
            case 1: typeStr = "commit"
            case 2: typeStr = "tree"
            case 3: typeStr = "blob"
            case 4: typeStr = "tag"
            default: return nil
            }
            cache[offset] = (typeStr, Data(actualData))
            return (typeStr, Data(actualData))
        case 6: // OFS_DELTA
            var basePos = pos
            var c = Int(packData[basePos])
            basePos += 1
            var baseOffset = c & 0x7f
            while c & 0x80 != 0 {
                baseOffset += 1
                c = Int(packData[basePos])
                basePos += 1
                baseOffset = (baseOffset << 7) + (c & 0x7f)
            }
            let baseObjectOffset = offset - baseOffset
            let compressedData = packData.subdata(in: basePos..<packData.count)
            let deltaData = compressedData.decompressed
            
            guard let base = try readPackObjectAtOffset(
                packData: packData,
                offset: baseObjectOffset,
                hashToOffset: hashToOffset,
                cache: &cache
            ) else { return nil }
            
            let result = try deltaResolver.apply(delta: deltaData, to: base.1)
            cache[offset] = (base.0, result)
            return (base.0, result)
        case 7: // REF_DELTA
            guard pos + 20 <= packData.count else { return nil }
            let baseHashData = packData[pos..<(pos+20)]
            pos += 20
            let baseHash = baseHashData.sha1()
            
            // Look up base object offset in the pack index
            guard let baseOffset = hashToOffset[baseHash] else {
                throw PackError.baseObjectNotFound(baseHash)
            }
            
            let compressedData = packData.subdata(in: pos..<packData.count)
            let deltaData = compressedData.decompressed
            
            guard let base = try readPackObjectAtOffset(
                packData: packData,
                offset: baseOffset,
                hashToOffset: hashToOffset,
                cache: &cache
            ) else { return nil }
            
            let result = try deltaResolver.apply(delta: deltaData, to: base.1)
            cache[offset] = (base.0, result)
            return (base.0, result)
        default:
            return nil
        }
    }
}

// MARK: - Pack Errors
enum PackError: Error {
    case objectNotFound
    case baseObjectNotFound(String)
    case unsupportedObjectType(String)
    case corruptedData
    case invalidPackFile
}
