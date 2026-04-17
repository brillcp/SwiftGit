import Foundation

public protocol ConflictWritable: Actor {
    /// Abort current merge/cherry-pick/revert/rebase operation
    func abortOperation() async throws

    /// Continue current merge/cherry-pick/revert/rebase operation
    func continueOperation() async throws

    /// Skip the current commit in an in-progress rebase.
    /// Only meaningful for `.rebase` — throws for other operations.
    func skipOperation() async throws
}
