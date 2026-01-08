import Testing
import Foundation
@testable import SwiftGit

@Suite("Staging Operations Tests")
struct StagingTests {
    @Test func testStageModifiedFile() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_stage_modified.txt"
        let repository = GitRepository(url: repoURL)

        // Setup: Create and commit a file
        try createTestFile(in: repoURL, named: testFile, content: "original")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "add test file")

        // Modify the file
        try modifyTestFile(in: repoURL, named: testFile)

        // Verify file is unstaged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix(" M "), "File should be modified but unstaged")
        } else {
            Issue.record("No status line for file")
        }

        // Stage the file
        try await repository.stageFile(at: testFile)

        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be staged")
        } else {
            Issue.record("No status line for file")
        }
    }

    @Test func testStageNewFile() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

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
        try await repository.stageFile(at: testFile)

        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("A  "), "File should be staged as new")
        } else {
            Issue.record("No status line for file")
        }
        try deleteTestFile(in: repoURL, named: testFile)
    }

    @Test func testStageDeletedFile() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_stage_deleted.txt"
        let repository = GitRepository(url: repoURL)

        // Setup: Create and commit a file (assume it exists in repo)
        // For this test, use an existing tracked file or create one first
        try createTestFile(in: repoURL, named: testFile, content: "to delete")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "add file to delete")

        // Delete the file
        try deleteTestFile(in: repoURL, named: testFile)

        // Verify file is deleted but not staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix(" D "), "File should be deleted but unstaged")
        } else {
            Issue.record("No status line for file")
        }

        // Stage the deletion
        try await repository.stageFile(at: testFile)

        // Verify deletion is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("D  "), "Deletion should be staged")
        } else {
            Issue.record("No status line for file")
        }

        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testStageNonExistentFile() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Try to stage a file that doesn't exist
        do {
            try await repository.stageFile(at: "nonexistent_file.txt")
            Issue.record("Should have thrown an error for non-existent file")
        } catch {
            // Expected to fail
            #expect(error is GitError)
        }
    }

    // MARK: - Stage All Tests

    @Test func testStageAll() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

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
        try await repository.stageAllFiles()

        // Verify all files are staged
        let status = try gitStatus(in: repoURL)
        for file in testFiles {
            #expect(status.contains("A  \(file)"), "\(file) should be staged")
        }
    }

    // MARK: - Unstage Tests

    @Test func testUnstageFile() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_unstage_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)

        // Create and stage a file
        try createTestFile(in: repoURL, named: testFile, content: "test")
        try await repository.stageFile(at: testFile)

        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("A  "), "File should be staged")
        } else {
            Issue.record("No status line for file")
        }

        // Unstage the file
        try await repository.unstageFile(at: testFile)

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
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFiles = [
            "test_unstage_all_1_\(UUID().uuidString).txt",
            "test_unstage_all_2_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)

        // Create and stage files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test")
        }
        try await repository.stageAllFiles()

        // Unstage all
        try await repository.unstageAllFiles()

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
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_commit_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)

        // Create and stage file
        try createTestFile(in: repoURL, named: testFile, content: "Hello")
        try await repository.stageFile(at: testFile)

        // Verify file is staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("A  "), "File should be staged")
        }

        // Commit
        try await repository.commit(message: "Add test file")

        // Verify no staged changes
        let staged = try await repository.getWorkingTreeStatus().files.values.filter(\.isStaged)
        #expect(staged.isEmpty, "Should have no staged changes after commit")

        // Verify file is now tracked and clean
        let status = try gitStatus(in: repoURL)
        #expect(!status.contains(testFile), "File should not appear in status (clean)")

        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testCommitEmptyMessage() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Try to commit with empty message
        do {
            try await repository.commit(message: "")
            Issue.record("Should have thrown error for empty message")
        } catch GitError.emptyCommitMessage {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func testCommitNothingStaged() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Try to commit with nothing staged
        do {
            try await repository.commit(message: "Test commit")
            Issue.record("Should have thrown error for nothing to commit")
        } catch GitError.nothingToCommit {
            // Expected
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test func testCommitMultipleFiles() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFiles = [
            "test_commit_multi_1_\(UUID().uuidString).txt",
            "test_commit_multi_2_\(UUID().uuidString).txt"
        ]
        let repository = GitRepository(url: repoURL)

        // Create and stage files
        for file in testFiles {
            try createTestFile(in: repoURL, named: file, content: "test")
        }
        try await repository.stageAllFiles()

        // Commit
        try await repository.commit(message: "Add multiple test files")

        // Verify no staged changes
        let staged = try await repository.getWorkingTreeStatus().files.values.filter(\.isStaged)
        #expect(staged.isEmpty, "Should have no staged changes after commit")
    }
}

// MARK: - Test Helpers
private extension StagingTests {    
    func modifyTestFile(in repoURL: URL, named: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        try (content + "\nmodified").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func deleteTestFile(in repoURL: URL, named: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try FileManager.default.removeItem(at: fileURL)
    }
}