import Foundation

/// Protocol for managing stashes (save, apply, drop)
public protocol StashWritable: Actor {
    /// Save current changes to a new stash. Returns the new stash's id.
    @discardableResult
    func stashPush(message: String?) async throws -> Stash.ID?

    /// Apply and remove the most recent stash (or specific stash by index)
    func stashPop(index: Int) async throws

    /// Apply a stash without removing it
    func stashApply(index: Int) async throws

    /// Delete a stash
    func stashDrop(index: Int) async throws

    /// Stash changes for a single file. Returns the new stash's id.
    @discardableResult
    func stashFile(path: String, message: String?) async throws -> Stash.ID?

    /// Stash changes for multiple files in a single git operation. Returns
    /// the new stash's id, or nil when `paths` is empty.
    @discardableResult
    func stashFiles(paths: [String], message: String?) async throws -> Stash.ID?

    /// Restore a single file from a stash without applying the whole stash
    func stashRestoreFile(index: Int, path: String) async throws

    /// Restore multiple files from a stash in a single operation
    func stashRestoreFiles(index: Int, paths: [String]) async throws
}
