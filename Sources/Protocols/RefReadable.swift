import Foundation
import Collections

/// Protocol for reading Git refs (branches, tags, HEAD)
public protocol RefReadable: Actor {
    /// Get all refs in the repository
    func getRefs() async throws -> OrderedDictionary<String, [GitRef]>

    /// Get the names of tags that exist on the given remote
    func getRemoteTagNames(remote: String) async throws -> Set<String>
}
