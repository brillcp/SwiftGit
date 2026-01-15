import Foundation

/// Protocol for reading Git refs (branches, tags, HEAD)
public protocol RefReadable: Actor {
    /// Get all refs in the repository
    func getRefs() async throws -> [String: [GitRef]]
}
