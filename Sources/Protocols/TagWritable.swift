import Foundation

/// Protocol for creating and deleting tags
public protocol TagWritable: Actor {
    /// Create a lightweight or annotated tag at the given ref
    func createTag(name: String, ref: String, message: String?) async throws
    /// Delete a local tag by name
    func deleteTag(name: String) async throws
}
