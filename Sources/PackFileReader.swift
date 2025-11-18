import Foundation

struct PackObject {
    let hash: String
    let type: ObjectType
    let data: Data
}

enum ObjectType: String {
    case commit
    case tree
    case blob
    case tag
}

protocol PackFileReaderProtocol {
    /// Read object at a specific offset in pack file
    func readObject(at location: PackObjectLocation) throws -> PackObject
    
    /// Check if pack file is memory-mapped
    var isMapped: Bool { get }
    
    /// Unmap pack file if mapped (to reduce memory pressure)
    func unmap()
}
