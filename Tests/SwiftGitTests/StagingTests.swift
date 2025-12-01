import Testing
import Foundation
@testable import SwiftGit

#if os(macOS)
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
        _ = try await repository.stageFile(at: testFile)
        // Commit it (we'll implement this later, for now just stage)
        
        // Modify the file
        try modifyTestFile(in: repoURL, named: testFile)
        
        // Verify file is unstaged
        var status = try gitStatus(in: repoURL)
        #expect(status.contains(" M \(testFile)"), "File should be modified but unstaged")
        
        // Stage the file
        _ = try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        status = try gitStatus(in: repoURL)
        #expect(status.contains("M  \(testFile)"), "File should be staged")
        
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
        var status = try gitStatus(in: repoURL)
        #expect(status.contains("?? \(testFile)"), "File should be untracked")
        
        // Stage the file
        _ = try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        status = try gitStatus(in: repoURL)
        #expect(status.contains("A  \(testFile)"), "File should be staged as new")
        
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
        
        // Delete the file
        try deleteTestFile(in: repoURL, named: testFile)
        
        // Verify file is deleted but not staged
        var status = try gitStatus(in: repoURL)
        #expect(status.contains(" D \(testFile)"), "File should be deleted but unstaged")
        
        // Stage the deletion
        _ = try await repository.stageFile(at: testFile)
        
        // Verify deletion is staged
        status = try gitStatus(in: repoURL)
        #expect(status.contains("D  \(testFile)"), "Deletion should be staged")
        
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
    
    // MARK: - Stage Multiple Files Tests
    
    @Test func testStageMultipleFiles() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFiles = [
            "test_multi_1_\(UUID().uuidString).txt",
            "test_multi_2_\(UUID().uuidString).txt",
            "test_multi_3_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)
        
        // Create test files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test content")
        }
        
        // Stage all files at once
        _ = try await repository.stageFiles(testFiles)
        
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
    
    @Test func testStageEmptyArray() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        
        // Stage empty array (should succeed but do nothing)
        _ = try await repository.stageFiles([])
        
        // No assertion needed - just verify it doesn't crash
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
        _ = try await repository.stageAll()
        
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
        var status = try gitStatus(in: repoURL)
        #expect(status.contains("A  \(testFile)"), "File should be staged")
        
        // Unstage the file
        _ = try await repository.unstageFile(at: testFile)
        
        // Verify file is unstaged
        status = try gitStatus(in: repoURL)
        #expect(status.contains("?? \(testFile)"), "File should be untracked again")
        
        // Cleanup
        try deleteTestFile(in: repoURL, named: testFile)
    }
    
    @Test func testUnstageMultipleFiles() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let testFiles = [
            "test_unstage_multi_1_\(UUID().uuidString).txt",
            "test_unstage_multi_2_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)
        
        // Create and stage files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test")
        }
        _ = try await repository.stageFiles(testFiles)
        
        // Unstage all files
        _ = try await repository.unstageFiles(testFiles)
        
        // Verify all files are unstaged
        let status = try gitStatus(in: repoURL)
        for file in testFiles {
            #expect(status.contains("?? \(file)"), "\(file) should be untracked")
        }
        
        // Cleanup
        for file in testFiles {
            try deleteTestFile(in: repoURL, named: file)
        }
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
        _ = try await repository.stageAll()
        
        // Unstage all
        _ = try await repository.unstageAll()
        
        // Verify all files are unstaged
        let status = try gitStatus(in: repoURL)
        for file in testFiles {
            #expect(status.contains("?? \(file)"), "\(file) should be untracked")
        }
        
        // Cleanup
        for file in testFiles {
            try deleteTestFile(in: repoURL, named: file)
        }
    }
}

// MARK: - Test Helpers
private extension StagingTests {    
    func getTestRepoURL() -> URL? {
        let testRepoPath = "/Users/vg/Documents/Dev/TestRepo"  // Update this
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
        let content = (try? String(contentsOf: fileURL)) ?? ""
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

}
#endif
