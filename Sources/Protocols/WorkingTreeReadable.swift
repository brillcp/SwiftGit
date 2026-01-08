import Foundation

/// Protocol for reading working tree status
public protocol WorkingTreeReadable: Actor {
    /// Get the current status of the working tree (staged and unstaged changes)
    func getWorkingTreeStatus() async throws -> WorkingTreeStatus
}