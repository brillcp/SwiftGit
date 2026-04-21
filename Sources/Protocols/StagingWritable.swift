import Foundation

/// Protocol for staging and unstaging files
public protocol StagingWritable: Actor {
    /// Stage a single file
    func stageFile(at path: String) async throws

    /// Stage multiple files in a single operation
    func stageFiles(paths: [String]) async throws

    /// Stage all files
    func stageAllFiles() async throws

    /// Unstage a single file
    func unstageFile(at path: String) async throws

    /// Unstage multiple files in a single operation
    func unstageFiles(paths: [String]) async throws

    /// Unstage all files
    func unstageAllFiles() async throws

    /// Stage a specific hunk
    func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws

    /// Unstage a specific hunk
    func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws

    /// Stage a single line from a hunk
    func stageLine(at lineIndex: Int, oldNum: Int?, newNum: Int?, in hunk: DiffHunk, file: WorkingTreeFile) async throws

    /// Unstage a single line from a hunk
    func unstageLine(at lineIndex: Int, oldNum: Int?, newNum: Int?, in hunk: DiffHunk, file: WorkingTreeFile) async throws
}
