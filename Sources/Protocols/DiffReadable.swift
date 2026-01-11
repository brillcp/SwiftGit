import Foundation

/// Protocol for generating diffs between versions
public protocol DiffReadable: Actor {
    /// Get diff for a file in a specific commit
    func getFileDiff(for commitId: String, at path: String) async throws -> [DiffHunk]

    /// Get diff for unstaged changes (Index → Working Tree)
    func getFileDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk]

    /// Get diff for staged changes (HEAD → Index)
    func getStagedDiff(for workingFile: WorkingTreeFile) async throws -> [DiffHunk]

    /// Get file content at a specific ref (commit, branch, or stage number)
    func getFileContent(at path: String, ref: String) async throws -> String
}
