import Testing
import Foundation
@testable import SwiftGit

@Suite("Staging Operations Tests")
struct StagingTests {
    @Test func testStageModifiedFile() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFile = "test_stage_modified.txt"
        let repository = GitRepository(url: repoURL)
        
        // Setup: Create and commit a file
        try createTestFile(in: repoURL, named: testFile, content: "original")
        try gitAdd(in: repoURL, pathspec: testFile)
        try gitCommit(in: repoURL, message: "add test file")
        
        // Modify the file
        try modifyTestFile(in: repoURL, named: testFile)
        
        // Verify file is unstaged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix(" M "), "File should be modified but unstaged")
        } else {
            Issue.record("No status line for file")
        }
        
        // Stage the file
        _ = try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be staged")
        } else {
            Issue.record("No status line for file")
        }
        
        // Cleanup
        try gitReset(in: repoURL)
        try gitCheckout(in: repoURL, file: testFile)
    }
    
    @Test func testStageNewFile() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFile = "test_stage_new_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)
        
        // Create a new file
        try createTestFile(in: repoURL, named: testFile, content: "new file")
        
        // Verify file is untracked
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("?? "), "File should be untracked")
        } else {
            Issue.record("No status line for file")
        }
        
        // Stage the file
        _ = try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("A  "), "File should be staged as new")
        } else {
            Issue.record("No status line for file")
        }
        
        // Cleanup
        try gitReset(in: repoURL)
        try deleteTestFile(in: repoURL, named: testFile)
    }
    
    @Test func testStageDeletedFile() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFile = "test_stage_deleted.txt"
        let repository = GitRepository(url: repoURL)
        
        // Setup: Create and commit a file (assume it exists in repo)
        // For this test, use an existing tracked file or create one first
        try createTestFile(in: repoURL, named: testFile, content: "to delete")
        try gitAdd(in: repoURL, pathspec: testFile)
        try gitCommit(in: repoURL, message: "add file to delete")
        
        // Delete the file
        try deleteTestFile(in: repoURL, named: testFile)
        
        // Verify file is deleted but not staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix(" D "), "File should be deleted but unstaged")
        } else {
            Issue.record("No status line for file")
        }
        
        // Stage the deletion
        _ = try await repository.stageFile(at: testFile)
        
        // Verify deletion is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("D  "), "Deletion should be staged")
        } else {
            Issue.record("No status line for file")
        }
        
        // Cleanup
        try gitReset(in: repoURL)
        try gitCheckout(in: repoURL, file: testFile)
    }
    
    @Test func testStageNonExistentFile() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        
        // Try to stage a file that doesn't exist
        do {
            _ = try await repository.stageFile(at: "nonexistent_file.txt")
            Issue.record("Should have thrown an error for non-existent file")
        } catch {
            // Expected to fail
            #expect(error is GitError)
        }
    }
    
    // MARK: - Stage All Tests
    
    @Test func testStageAll() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFiles = [
            "test_all_1_\(UUID().uuidString).txt",
            "test_all_2_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)
        
        // Create multiple test files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test")
        }
        
        // Stage all changes
        _ = try await repository.stageFiles()
        
        // Verify all files are staged
        let status = try gitStatus(in: repoURL)
        for file in testFiles {
            #expect(status.contains("A  \(file)"), "\(file) should be staged")
        }
        
        // Cleanup
        try gitReset(in: repoURL)
        for file in testFiles {
            try deleteTestFile(in: repoURL, named: file)
        }
    }
    
    // MARK: - Unstage Tests
    
    @Test func testUnstageFile() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFile = "test_unstage_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)
        
        // Create and stage a file
        try createTestFile(in: repoURL, named: testFile, content: "test")
        _ = try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("A  "), "File should be staged")
        } else {
            Issue.record("No status line for file")
        }
        
        // Unstage the file
        _ = try await repository.unstageFile(at: testFile)
        
        // Verify file is unstaged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("?? "), "File should be untracked again")
        } else {
            Issue.record("No status line for file")
        }
        
        // Cleanup
        try deleteTestFile(in: repoURL, named: testFile)
    }
    
    @Test func testUnstageAll() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFiles = [
            "test_unstage_all_1_\(UUID().uuidString).txt",
            "test_unstage_all_2_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)
        
        // Create and stage files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test")
        }
        _ = try await repository.stageFiles()
        
        // Unstage all
        _ = try await repository.unstageFiles()
        
        // Verify all files are unstaged
        for file in testFiles {
            if let line = try statusLine(for: file, in: repoURL) {
                #expect(line.hasPrefix("?? "), "\(file) should be untracked")
            } else {
                Issue.record("No status line for file")
            }
        }
        
        // Cleanup
        for file in testFiles {
            try deleteTestFile(in: repoURL, named: file)
        }
    }
    
    // MARK: - Commit Tests
    @Test func testCommit() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let testFile = "test_commit_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)
        
        // Create and stage file
        try createTestFile(in: repoURL, named: testFile, content: "Hello")
        _ = try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("A  "), "File should be staged")
        }
        
        // Commit
        try await repository.commit(message: "Add test file", author: nil)
        
        // Verify no staged changes
        let staged = try await repository.getStagedChanges()
        #expect(staged.isEmpty, "Should have no staged changes after commit")
        
        // Verify file is now tracked and clean
        let status = try gitStatus(in: repoURL)
        #expect(!status.contains(testFile), "File should not appear in status (clean)")
        
        // Cleanup
        try gitReset(in: repoURL)
        try? deleteTestFile(in: repoURL, named: testFile)
    }

    @Test func testCommitEmptyMessage() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let repository = GitRepository(url: repoURL)
        
        // Try to commit with empty message
        do {
            try await repository.commit(message: "", author: nil)
            Issue.record("Should have thrown error for empty message")
        } catch GitError.emptyCommitMessage {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func testCommitNothingStaged() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let repository = GitRepository(url: repoURL)
        
        // Try to commit with nothing staged
        do {
            try await repository.commit(message: "Test commit", author: nil)
            Issue.record("Should have thrown error for nothing to commit")
        } catch GitError.nothingToCommit {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func testCommitMultipleFiles() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let testFiles = [
            "test_commit_multi_1_\(UUID().uuidString).txt",
            "test_commit_multi_2_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)
        
        // Create and stage files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test")
        }
        _ = try await repository.stageFiles()
        
        // Commit
        try await repository.commit(message: "Add multiple test files", author: nil)
        
        // Verify no staged changes
        let staged = try await repository.getStagedChanges()
        #expect(staged.isEmpty, "Should have no staged changes after commit")
        
        // Cleanup
        try gitReset(in: repoURL)
        for file in testFiles {
            try? deleteTestFile(in: repoURL, named: file)
        }
    }
}

// MARK: - Test Helpers
private extension StagingTests {    
    func getTestRepoURL() -> URL? {
        let testRepoPath = "/Users/vg/Documents/Dev/TestRepo"
        let url = URL(fileURLWithPath: testRepoPath)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        return url
    }
    
    func createTestFile(in repoURL: URL, named: String, content: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func modifyTestFile(in repoURL: URL, named: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        try (content + "\nmodified").write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func deleteTestFile(in repoURL: URL, named: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try FileManager.default.removeItem(at: fileURL)
    }
    
    func gitStatus(in repoURL: URL) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "status", "--porcelain"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func gitReset(in repoURL: URL) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "reset", "HEAD", "."]
        task.launch()
        task.waitUntilExit()
    }
    
    func gitCheckout(in repoURL: URL, file: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "checkout", "HEAD", "--", file]
        task.launch()
        task.waitUntilExit()
    }

    func gitAdd(in repoURL: URL, pathspec: String = ".") throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "add", pathspec]
        task.launch()
        task.waitUntilExit()
    }
    
    func gitCommit(in repoURL: URL, message: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "commit", "-m", message]
        task.launch()
        task.waitUntilExit()
    }
    
    func statusLine(for file: String, in repoURL: URL) throws -> String? {
        let output = try gitStatus(in: repoURL)
        // Each line is two status columns + space + path
        return output
            .split(separator: "\n")
            .map(String.init)
            .first { $0.hasSuffix(" \(file)") || $0.hasSuffix(file) }
    }
}
