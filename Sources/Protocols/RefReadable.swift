import Foundation

/// Protocol for reading Git refs (branches, tags, HEAD)
public protocol RefReadable: Actor {
    /// Get all refs in the repository
    func getRefs() async throws -> [String: [GitRef]]
}

/// Protocol for working with tags
public protocol TagReadable: Actor {
    /// Get all tags in the repository
    func getTags() async throws -> [GitRef]
}