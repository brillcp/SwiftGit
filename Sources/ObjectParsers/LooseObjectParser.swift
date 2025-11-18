import Foundation

public enum ParsedObject: Sendable {
    case commit(Commit)
    case tree(Tree)
    case blob(Blob)
    case tag // not implemented yet
}

public protocol LooseObjectParserProtocol {
    /// Parse a loose object file (decompresses and parses header)
    func parse(hash: String, data: Data) throws -> ParsedObject
}

// MARK: -
public final class LooseObjectParser {
    private let commitParser: any CommitParserProtocol
    private let treeParser: any TreeParserProtocol
    private let blobParser: any BlobParserProtocol
    
    public init(
        commitParser: any CommitParserProtocol = CommitParser(),
        treeParser: any TreeParserProtocol = TreeParser(),
        blobParser: any BlobParserProtocol = BlobParser()
    ) {
        self.commitParser = commitParser
        self.treeParser = treeParser
        self.blobParser = blobParser
    }
}

// MARK: - LooseObjectParserProtocol
extension LooseObjectParser: LooseObjectParserProtocol {
    public func parse(hash: String, data: Data) throws -> ParsedObject {
        let decompressed = data.decompressed
        let (type, objectData) = try splitHeader(decompressed)

        switch type {
        case "commit":
            let commit = try commitParser.parse(hash: hash, data: objectData)
            return .commit(commit)
        case "tree":
            let tree = try treeParser.parse(hash: hash, data: objectData)
            return .tree(tree)
        case "blob":
            let blob = try blobParser.parse(hash: hash, data: objectData)
            return .blob(blob)
        case "tag":
            // TODO: Implement tag parsing
            throw ParseError.unsupportedObjectType(type)
        default:
            throw ParseError.unsupportedObjectType(type)
        }
    }
}

// MARK: - Private Helpers
private extension LooseObjectParser {
    /// Split Git object header from content
    /// Format: "type size\0content"
    func splitHeader(_ data: Data) throws -> (type: String, content: Data) {
        var remainder = data
        
        // Read type (up to space)
        guard let spaceIndex = remainder.firstIndex(of: 0x20) else {
            throw ParseError.malformedHeader
        }
        
        let typeData = remainder[..<spaceIndex]
        guard let type = String(data: typeData, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }
        
        // Skip the space
        remainder = remainder[(spaceIndex + 1)...]
        
        // Read size (up to null terminator)
        guard let nullIndex = remainder.firstIndex(of: 0x00) else {
            throw ParseError.malformedHeader
        }
        
        // We could validate size here, but Git doesn't always match
        // let sizeData = remainder[..<nullIndex]
        // let size = Int(String(data: sizeData, encoding: .utf8) ?? "") ?? 0
        
        // Skip the null byte and return remaining content
        let content = remainder[(nullIndex + 1)...]
        
        return (type, Data(content))
    }
}

// MARK: - Parse Errors
enum ParseError: Error, CustomStringConvertible {
    case malformedHeader
    case invalidEncoding
    case unsupportedObjectType(String)
    case malformedCommit
    case malformedTree
    case missingRequiredField(String)
    
    var description: String {
        switch self {
        case .malformedHeader:
            return "Git object header is malformed"
        case .invalidEncoding:
            return "Git object data is not valid UTF-8"
        case .unsupportedObjectType(let type):
            return "Unsupported Git object type: \(type)"
        case .malformedCommit:
            return "Commit data is malformed"
        case .malformedTree:
            return "Tree data is malformed"
        case .missingRequiredField(let field):
            return "Required field missing: \(field)"
        }
    }
}
