import Foundation

/// Protocol for creating tags
public protocol TagWritable: Actor {
    /// Create a lightweight or annotated tag at the given ref
    func createTag(name: String, ref: String, message: String?) async throws
}
