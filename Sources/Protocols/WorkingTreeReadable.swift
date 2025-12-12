import Foundation

/// Protocol for reading working tree status
public protocol WorkingTreeReadable: Actor {
    /// Get the current status of the working tree (staged and unstaged changes)
    func getWorkingTreeStatus() async throws -> WorkingTreeStatus
    
    /// Get only staged changes (HEAD → Index)
    func getStagedChanges() async throws -> [String: WorkingTreeFile]
    
    /// Get only unstaged changes (Index → Working Tree)
    func getUnstagedChanges() async throws -> [String: WorkingTreeFile]
}
