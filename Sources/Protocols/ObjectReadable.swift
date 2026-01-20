import Foundation

public protocol ObjectReadable: Actor {
    /// Get a tree by hash
    func getTree(_ hash: String) async throws -> Tree?

    /// Get all file paths in a tree (flattened)
    func getTreePaths(_ treeHash: String) async throws -> [String: String]
}
