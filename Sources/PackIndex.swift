import Foundation

struct PackObjectLocation {
    let hash: String
    let offset: Int
    let packURL: URL
}

protocol PackIndexProtocol {
    /// Load and parse a pack index file
    func load(idxURL: URL, packURL: URL) throws
    
    /// Find the location of an object by hash
    func findObject(_ hash: String) -> PackObjectLocation?
    
    /// Get all hashes in this pack
    func getAllHashes() -> Set<String>
    
    /// Clear index data
    func clear()
}
