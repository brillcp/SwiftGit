import Foundation

/// Protocol for reading stash information
public protocol StashReadable: Actor {
    /// Get all stashes in the repository
    func getStashes() async throws -> [Stash]
}