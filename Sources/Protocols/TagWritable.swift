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
    ///
    /// Set `force` to replace a tag of the same name that already exists on the
    /// remote, such as after moving the tag.
    func pushTag(name: String, remote: String, force: Bool) async throws

    /// Move an existing tag to another ref, keeping an annotated tag's message.
    func moveTag(name: String, to ref: String) async throws
}

public extension TagWritable {
    /// Push a single local tag to the remote without replacing an existing remote tag.
    func pushTag(name: String, remote: String) async throws {
        try await pushTag(name: name, remote: remote, force: false)
    }
}
