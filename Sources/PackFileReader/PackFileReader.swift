import Foundation

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
        let handle = try getPackHandle(for: location.packURL)
        
        var cache: [Int: (type: String, data: Data)] = [:]
        
        guard let (typeStr, data) = try readPackObjectAtOffset(
            handle: handle,
            offset: location.offset,
            packIndex: packIndex,
            cache: &cache
        ) else {
            throw PackError.objectNotFound
        }
        
        switch typeStr {
        case "commit":
            let commit = try commitParser.parse(hash: location.hash, data: data)
            return .commit(commit)
        case "tree":
            let tree = try treeParser.parse(hash: location.hash, data: data)
            return .tree(tree)
        case "blob":
            let blob = try blobParser.parse(hash: location.hash, data: data)
            return .blob(blob)
        case "tag":
            throw PackError.unsupportedObjectType("tag")
        default:
            throw PackError.unsupportedObjectType(typeStr)
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

    func readPackObjectAtOffset(
        handle: FileHandle,
        offset: Int,
        packIndex: PackIndexProtocol,
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
                packIndex: packIndex,
                cache: &cache
            ) else { return nil }
            
            let result = try deltaResolver.apply(delta: deltaData, to: base.1)
            cache[offset] = (base.0, result)
            return (base.0, result)
            
        case 7: // REF_DELTA
            let baseHashData = try readBytes(from: handle, offset: dataOffset, count: 20)
            let baseHash = baseHashData.toHexString()
            
            // ✅ Lazy lookup - only loads this hash's range
            guard let baseLoc = packIndex.findObject(baseHash) else {
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
                offset: baseLoc.offset,
                packIndex: packIndex,
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
