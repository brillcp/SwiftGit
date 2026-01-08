import Foundation

/// Protocol for managing stashes (save, apply, drop)
public protocol StashManageable: Actor {
    /// Save current changes to a new stash
    func stashPush(message: String?) async throws

    /// Apply and remove the most recent stash (or specific stash by index)
    func stashPop(index: Int?) async throws

    /// Apply a stash without removing it
    func stashApply(index: Int?) async throws

    /// Delete a stash
    func stashDrop(index: Int) async throws
}