import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int

    /// True when either output stream mentions "conflict" — used by
    /// merge/rebase/cherry-pick/revert/workflow paths to distinguish a
    /// halted-at-conflict state from a real runtime error.
    public var indicatesConflict: Bool {
        let combined = stderr + stdout
        return combined.localizedCaseInsensitiveContains("conflict")
    }
}