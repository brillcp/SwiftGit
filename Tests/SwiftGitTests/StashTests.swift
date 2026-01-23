import Testing
import Foundation
@testable import SwiftGit

@Suite("Stash Tests")
struct StashTests {
    @Test func testCreateAndListStash() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create initial commit
        try createTestFile(in: repoURL, named: "file.txt", content: "Initial")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        // Modify and stash
        try createTestFile(in: repoURL, named: "file.txt", content: "Modified")
        try await repository.stageFile(at: "file.txt")
        try await repository.stashPush(message: "Test stash")

        // Verify stash exists
        let stashes = try await repository.getStashes()
        #expect(stashes.count == 1, "Should have 1 stash")
        #expect(stashes[0].index == 0, "First stash should have index 0")
        #expect(stashes[0].message.contains("Test stash"), "Should have correct message")

        // Verify stash commit structure
        let commit = try await repository.getCommit(stashes[0].id)
        #expect(commit != nil, "Should be able to load stash commit")
        #expect(commit!.parents.count >= 1, "Stash should have at least 1 parent")
    }

    @Test func testApplyStash() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup
        try createTestFile(in: repoURL, named: "file.txt", content: "Initial")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        // Stash changes
        try createTestFile(in: repoURL, named: "file.txt", content: "Modified")
        try await repository.stageFile(at: "file.txt")
        try await repository.stashPush(message: "Test stash")

        // Verify working tree is clean
        let cleanStatus = try await repository.getWorkingTreeStatus()
        #expect(cleanStatus.files.isEmpty, "Working tree should be clean after stash")

        // Apply stash
        try await repository.stashApply(index: 0)

        // Verify changes are back
        let afterStatus = try await repository.getWorkingTreeStatus()
        #expect(!afterStatus.files.isEmpty, "Should have changes after apply")

        // Stash should still exist (apply doesn't delete)
        let stashes = try await repository.getStashes()
        #expect(stashes.count == 1, "Apply should not delete stash")
    }

    @Test func testPopStash() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup
        try createTestFile(in: repoURL, named: "file.txt", content: "Initial")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        // Stash changes
        try createTestFile(in: repoURL, named: "file.txt", content: "Modified")
        try await repository.stageFile(at: "file.txt")
        try await repository.stashPush(message: "Test stash")

        // Pop stash
        try await repository.stashPop(index: 0)

        // Verify changes are back
        let afterStatus = try await repository.getWorkingTreeStatus()
        #expect(!afterStatus.files.isEmpty, "Should have changes after pop")

        // Stash should be deleted (pop removes it)
        let stashes = try await repository.getStashes()
        #expect(stashes.isEmpty, "Pop should delete stash")
    }

    @Test func testDropStash() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Setup and create stash
        try createTestFile(in: repoURL, named: "file.txt", content: "Initial")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Initial")

        try createTestFile(in: repoURL, named: "file.txt", content: "Modified")
        try await repository.stageFile(at: "file.txt")
        try await repository.stashPush(message: "Test stash")

        // Verify stash exists
        let before = try await repository.getStashes()
        #expect(before.count == 1)

        // Drop stash
        try await repository.stashDrop(index: 0)

        // Verify stash is gone
        let after = try await repository.getStashes()
        #expect(after.isEmpty, "Stash should be deleted")
    }

    @Test func testGetChangedFilesForStash() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create initial commit
        try createTestFile(in: repoURL, named: "file1.txt", content: "Content 1")
        try createTestFile(in: repoURL, named: "file2.txt", content: "Content 2")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Initial")

        // Make changes (don't commit)
        try createTestFile(in: repoURL, named: "file1.txt", content: "Modified")
        try createTestFile(in: repoURL, named: "file3.txt", content: "New file")

        // Stash the changes
        try await repository.stashPush(message: "Test stash")

        // Get stashes
        let stashes = try await repository.getStashes()

        guard let firstStash = stashes.first,
              let stashCommit = try await repository.getCommit(firstStash.id) else {
            Issue.record("No stash found")
            return
        }

        // Get changed files from stash
        let changes = try await repository.getStashedFiles(stashCommit.id)

        #expect(changes.count >= 2, "Stash should show at least 2 changed files")
        #expect(changes["file1.txt"] != nil, "file1.txt should be in stash")
        #expect(changes["file3.txt"] != nil, "file3.txt should be in stash")
    }
}

func gitStash(in repoURL: URL) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    task.arguments = ["-C", repoURL.path, "stash"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    try task.run()
    task.waitUntilExit()
}
