import Foundation

public protocol ObjectReadable: Actor {
    /// Get a tree by hash
    func getTree(_ hash: String) async throws -> Tree?
    
    /// Get a blob by hash
    func getBlob(_ hash: String) async throws -> Blob?
    
    /// Stream a large blob without loading entirely into memory
    func streamBlob(_ hash: String) -> AsyncThrowingStream<Data, Error>
    
    /// Get all file paths in a tree (flattened)
    func getTreePaths(_ treeHash: String) async throws -> [String: String]
}
