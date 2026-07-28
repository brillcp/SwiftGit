import Foundation

public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int

    var failureDescription: String {
        let standardError = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardError.isEmpty {
            return standardError
        }

        let standardOutput = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !standardOutput.isEmpty {
            return standardOutput
        }

        return "Git exited with status \(exitCode)."
    }

    /// True when either output stream mentions "conflict" — used by
    /// merge/rebase/cherry-pick/revert/workflow paths to distinguish a
    /// halted-at-conflict state from a real runtime error.
    public var indicatesConflict: Bool {
        (stderr + stdout).localizedCaseInsensitiveContains("conflict")
    }

    public var indicatesEmptyCherryPick: Bool {
        let combined = stderr + stdout
        return combined.localizedCaseInsensitiveContains("previous cherry-pick is now empty") ||
            combined.localizedCaseInsensitiveContains("nothing to commit, working tree clean")
    }

    public var indicatesPullReject: Bool {
        let combined = stderr + stdout
        return combined.localizedCaseInsensitiveContains("diverg") ||
        combined.localizedCaseInsensitiveContains("non-fast-forward") ||
        combined.localizedCaseInsensitiveContains("would clobber") ||
        combined.localizedCaseInsensitiveContains("need to specify how to reconcile") ||
        combined.localizedCaseInsensitiveContains("not possible to fast-forward")
    }
}
