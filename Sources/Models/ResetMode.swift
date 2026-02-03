import Foundation

/// The mode for a git reset operation
public enum ResetMode: String, Sendable {
    /// Keep changes in staging area and working directory
    case soft = "--soft"
    /// Keep changes in working directory but unstage them (default git behavior)
    case mixed = "--mixed"
    /// Discard all changes in staging area and working directory
    case hard = "--hard"
}
