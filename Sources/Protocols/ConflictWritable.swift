import Foundation

public protocol ConflictWritable: Actor {
    /// Abort current merge/cherry-pick/revert operation
    func abortOperation() async throws

    /// Continue current merge/cherry-pick/revert operation
    func continueOperation() async throws
}
