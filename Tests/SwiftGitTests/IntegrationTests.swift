import Testing
import Foundation
@testable import SwiftGit
import CryptoKit

@Suite("Integration Tests")
struct IntegrationTests {
    @Test func testFullCommitWorkflow() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Initial commit (realistic - repo has history)
        try createTestFile(in: repoURL, named: "README.md", content: "Initial")
        try await repository.stageFile(at: "README.md")
        try await repository.commit(message: "Initial commit")

        // NOW test the workflow (this is what users do daily)

        // Create file
        try createTestFile(in: repoURL, named: "file.txt", content: "Content")

        // Check status - untracked
        let status1 = try await repository.getWorkingTreeStatus()
        #expect(status1.files["file.txt"]?.unstaged == .untracked)

        // Stage
        try await repository.stageFile(at: "file.txt")
        let status2 = try await repository.getWorkingTreeStatus()
        #expect(status2.files["file.txt"]?.staged == .added)

        // Commit
        try await repository.commit(message: "Add file")

        // Verify committed (no changes left)
        let status3 = try await repository.getWorkingTreeStatus()
        #expect(status3.files["file.txt"] == nil, "No changes after commit")

        // Read commit
        guard let hash = try await repository.getHEAD() else {
            Issue.record("No HEAD")
            return
        }
        let commit = try await repository.getCommit(hash)
        #expect(commit?.title == "Add file")
    }

    @Test func testStageUnstageWorkflow() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create initial commit
        try createTestFile(in: repoURL, named: "file.txt", content: "Initial")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        // Modify file
        try createTestFile(in: repoURL, named: "file.txt", content: "Modified")

        // Stage
        try await repository.stageFile(at: "file.txt")
        let status1 = try await repository.getWorkingTreeStatus()
        #expect(status1.files["file.txt"]?.staged == .modified)

        // Unstage
        try await repository.unstageFile(at: "file.txt")
        let status2 = try await repository.getWorkingTreeStatus()
        #expect(status2.files["file.txt"]?.unstaged == .modified)
        #expect(status2.files["file.txt"]?.staged == nil)

        // Stage again
        try await repository.stageFile(at: "file.txt")
        let status3 = try await repository.getWorkingTreeStatus()
        #expect(status3.files["file.txt"]?.staged == .modified)
    }
}
