import Foundation

/// Protocol for staging and unstaging files
public protocol StagingManageable: Actor {
    /// Stage a single file
    func stageFile(at path: String) async throws
    
    /// Stage all files
    func stageFiles() async throws
    
    /// Unstage a single file
    func unstageFile(at path: String) async throws
    
    /// Unstage all files
    func unstageFiles() async throws
    
    /// Stage a specific hunk
    func stageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws
    
    /// Unstage a specific hunk
    func unstageHunk(_ hunk: DiffHunk, in file: WorkingTreeFile) async throws
}
