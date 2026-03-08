import Foundation

/// Protocol for adding patterns to .gitignore
public protocol IgnoreWritable: Actor {
    /// Appends a pattern to the repository's .gitignore file, creating it if needed.
    /// Has no effect if the pattern is already present.
    func ignore(pattern: String) async throws
}
