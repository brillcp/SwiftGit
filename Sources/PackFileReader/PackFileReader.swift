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

    /// Parse object at a specific offset in pack file
    func parseObject(
        at location: PackObjectLocation,
        packIndex: PackIndexProtocol
    ) throws -> ParsedObject

    /// Unmap pack file if mapped (to reduce memory pressure)
    func unmap()
}

// MARK: -
public actor PackFileReader: @unchecked Sendable {
    private let deltaResolver: DeltaResolverProtocol
    private let commitParser: any CommitParserProtocol
    private let treeParser: any TreeParserProtocol
    private let blobParser: any BlobParserProtocol

    private var packHandles: [URL: FileHandle] = [:]
    
    public var isMapped: Bool {
        !packHandles.isEmpty
    }
    
    public init(
        deltaResolver: DeltaResolverProtocol = DeltaResolver(),
        commitParser: any CommitParserProtocol = CommitParser(),
        treeParser: any TreeParserProtocol = TreeParser(),
        blobParser: any BlobParserProtocol = BlobParser()
    ) {
        self.deltaResolver = deltaResolver
        self.commitParser = commitParser
        self.treeParser = treeParser
        self.blobParser = blobParser
    }
}

// MARK: - PackFileReaderProtocol
extension PackFileReader: PackFileReaderProtocol {
    public func parseObject(
        at location: PackObjectLocation,
        packIndex: PackIndexProtocol
    ) throws -> ParsedObject {
        // Read the pack object (handles deltas)
        let packObject = try readObject(at: location, packIndex: packIndex)
        
        // Route to appropriate parser based on type
        switch packObject.type {
        case .commit:
            let commit = try commitParser.parse(hash: packObject.hash, data: packObject.data)
            return .commit(commit)
            
        case .tree:
            let tree = try treeParser.parse(hash: packObject.hash, data: packObject.data)
            return .tree(tree)
            
        case .blob:
            let blob = try blobParser.parse(hash: packObject.hash, data: packObject.data)
            return .blob(blob)
            
        case .tag:
            throw PackError.unsupportedObjectType("tag")
        }
    }

    public func unmap() {
        // Close all file handles
        for handle in packHandles.values {
            try? handle.close()
        }
        packHandles.removeAll()
    }
}

// MARK: - Private Helpers
private extension PackFileReader {
    func getPackHandle(for url: URL) throws -> FileHandle {
        if let handle = packHandles[url] {
            return handle
        }
        let handle = try FileHandle(forReadingFrom: url)
        packHandles[url] = handle
        return handle
    }

    func readBytes(from handle: FileHandle, offset: Int, count: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(offset))
        guard let data = try handle.read(upToCount: count) else {
            throw PackError.corruptedData
        }
        return data
    }

    func readObject(at location: PackObjectLocation, packIndex: PackIndexProtocol) throws -> PackObject {
        let handle = try getPackHandle(for: location.packURL)  // Changed!
        
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
            handle: handle,
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

    func readPackObjectAtOffset(
        handle: FileHandle,  // Changed from packData: Data!
        offset: Int,
        hashToOffset: [String: Int],
        cache: inout [Int: (type: String, data: Data)]
    ) throws -> (String, Data)? {
        if let cached = cache[offset] { return cached }
        
        // Read header bytes (up to 10 bytes for variable-length encoding)
        let headerData = try readBytes(from: handle, offset: offset, count: 10)
        
        var pos = 0
        var byte = headerData[pos]
        pos += 1
        
        let type = Int((byte >> 4) & 0x07)
        var size = Int(byte & 0x0f)
        var shift = 4
        
        // Read variable-length size
        while byte & 0x80 != 0 {
            guard pos < headerData.count else { throw PackError.corruptedData }
            byte = headerData[pos]
            pos += 1
            size |= Int(byte & 0x7f) << shift
            shift += 7
        }
        
        let dataOffset = offset + pos
        
        switch type {
        case 1, 2, 3, 4:
            // Non-delta types: decompress and return
            // Estimate compressed size (usually 50-70% of uncompressed)
            let estimatedCompressed = Int(Double(size) * 1.5) + 1024
            let compressedData = try readBytes(from: handle, offset: dataOffset, count: estimatedCompressed)
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
            // Read offset encoding
            let offsetData = try readBytes(from: handle, offset: dataOffset, count: 10)
            var basePos = 0
            var c = Int(offsetData[basePos])
            basePos += 1
            var baseOffset = c & 0x7f
            while c & 0x80 != 0 {
                baseOffset += 1
                c = Int(offsetData[basePos])
                basePos += 1
                baseOffset = (baseOffset << 7) + (c & 0x7f)
            }
            let baseObjectOffset = offset - baseOffset
            
            // Read delta data
            let deltaOffset = dataOffset + basePos
            let estimatedDeltaSize = Int(Double(size) * 1.5) + 1024
            let compressedDelta = try readBytes(from: handle, offset: deltaOffset, count: estimatedDeltaSize)
            let deltaData = compressedDelta.decompressed
            
            // Recursively resolve base
            guard let base = try readPackObjectAtOffset(
                handle: handle,
                offset: baseObjectOffset,
                hashToOffset: hashToOffset,
                cache: &cache
            ) else { return nil }
            
            let result = try deltaResolver.apply(delta: deltaData, to: base.1)
            cache[offset] = (base.0, result)
            return (base.0, result)
            
        case 7: // REF_DELTA
            // Read base hash (20 bytes)
            let baseHashData = try readBytes(from: handle, offset: dataOffset, count: 20)
            let baseHash = baseHashData.sha1()
            
            // Look up base object offset
            guard let baseOffset = hashToOffset[baseHash] else {
                throw PackError.baseObjectNotFound(baseHash)
            }
            
            // Read delta data
            let deltaOffset = dataOffset + 20
            let estimatedDeltaSize = Int(Double(size) * 1.5) + 1024
            let compressedDelta = try readBytes(from: handle, offset: deltaOffset, count: estimatedDeltaSize)
            let deltaData = compressedDelta.decompressed
            
            // Recursively resolve base
            guard let base = try readPackObjectAtOffset(
                handle: handle,
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
