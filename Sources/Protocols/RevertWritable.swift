import Foundation

public protocol RevertWritable: Actor {
    /// Create a new commit that undoes changes from a specific commit
    func revertCommit(_ commitHash: String) async throws

    /// Contine current revert
    func revertContinue() async throws

    /// Abort currenet revert
    func revertAbort() async throws
}
