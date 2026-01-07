import Foundation

extension GitRepository: StashReadable {
    public func getStashes() async throws -> [Stash] {
        try await refReader.getStashes()
    }
}

// MARK: - StashManageable
extension GitRepository: StashManageable {
    /// Save current changes to stash
    public func stashPush(message: String? = nil) async throws {
        let result = try await commandRunner.run(
            .stashPush(message: message),
            stdin: nil,
            in: url
        )
        
        guard result.exitCode == 0 else {
            // Check if "No local changes to save"
            let output = result.stderr + result.stdout
            if output.contains("No local changes") {
                throw GitError.nothingToStash
            }
            throw GitError.stashFailed
        }
        
        await workingTree.invalidateIndexCache()
        await cache.remove(.refs)
    }
    
    /// Apply and remove most recent stash
    public func stashPop(index: Int? = nil) async throws {
        let result = try await commandRunner.run(
            .stashPop(index: index),
            stdin: nil,
            in: url
        )
        
        guard result.exitCode == 0 else {
            throw GitError.stashPopFailed
        }
        
        // Invalidate caches
        await workingTree.invalidateIndexCache()
        await cache.remove(.refs) // Stash list changed
    }
    
    /// Apply stash without removing it
    public func stashApply(index: Int? = nil) async throws {
        let result = try await commandRunner.run(
            .stashApply(index: index),
            stdin: nil,
            in: url
        )
        
        guard result.exitCode == 0 else {
            throw GitError.stashApplyFailed
        }
        
        // Invalidate caches
        await workingTree.invalidateIndexCache()
        // Note: refs don't change (stash still exists)
    }
    
    /// Delete a stash
    public func stashDrop(index: Int) async throws {
        let result = try await commandRunner.run(
            .stashDrop(index: index),
            stdin: nil,
            in: url
        )
        
        guard result.exitCode == 0 else {
            throw GitError.stashDropFailed
        }
        
        // Invalidate refs cache (stash list changed)
        await cache.remove(.refs)
    }
}
