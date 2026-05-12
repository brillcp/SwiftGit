import Foundation

/// Protocol for creating and deleting tags
public protocol TagWritable: Actor {
    /// Create a lightweight or annotated tag at the given ref
    func createTag(name: String, ref: String, message: String?) async throws
    /// Delete a local tag by name
    func deleteTag(name: String) async throws

    /// Delete a tag from the remote
    func deleteRemoteTag(name: String, remote: String) async throws

    /// Push a single local tag to the remote.
    func pushTag(name: String, remote: String) async throws
}
