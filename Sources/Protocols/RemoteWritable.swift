import Foundation

/// Protocol for remote operations (fetch, pull, remote management)
public protocol RemoteWritable: Actor {
    /// Fetch updates from a remote
    func fetch(remote: String?, prune: Bool) async throws

    /// Pull changes from a remote into the current branch
    func pull(remote: String?, branch: String?) async throws

    /// Add a named remote to the repository
    func addRemote(name: String, url: String, at repoURL: URL) async throws
}
