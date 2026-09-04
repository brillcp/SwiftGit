import Foundation

/// Protocol for remote operations (fetch, pull, remote management)
public protocol RemoteWritable: Actor {
    /// Fetch updates from a remote
    func fetch(remote: String?, prune: Bool) async throws

    /// Pull changes from a remote into the current branch
    func pull(remote: String?, branch: String?) async throws

    /// Add a named remote to the repository
    func addRemote(name: String, url: String, at repoURL: URL) async throws

    /// Returns true if a remote with the given name exists in .git/config
    func hasRemote(named name: String) -> Bool
}
