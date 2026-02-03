import Foundation

/// Protocol for remote operations (fetch, pull)
public protocol RemoteWritable: Actor {
    /// Fetch updates from a remote
    func fetch(remote: String?, prune: Bool) async throws

    /// Pull changes from a remote into the current branch
    func pull(remote: String?, branch: String?) async throws
}
