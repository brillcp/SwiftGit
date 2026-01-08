import Testing
import Foundation
@testable import SwiftGit

@Suite("Commit Stream Tests")
struct CommitStreamTests {
    @Test func testMultipleLoadAfterCommit() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_multi_load_\(UUID().uuidString).txt"
        
        // Create and stage a file
        try createTestFile(in: repoURL, named: testFile, content: "Test content")
        try await repository.stageFile(at: testFile)
        
        // Commit
        try await repository.commit(message: "Test commit")
        
        // Load staged multiple times (simulating what your UI does)
        for i in 1...3 {
            let staged = try await repository.getWorkingTreeStatus().files.values.filter(\.isStaged)
            print("Load \(i): \(staged.count) staged files")
            #expect(staged.isEmpty, "Load \(i) should show no staged files")
        }
        
        // Cleanup
        try gitReset(in: repoURL, hard: true)
        try? FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
    }

    @Test func testBasicCommitStreaming() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        
        let repository = GitRepository(url: repoURL)
        
        // Create a few commits
        for i in 1...5 {
            let file = "file\(i).txt"
            try createTestFile(in: repoURL, named: file, content: "Content \(i)")
            try await repository.stageFile(at: file)
            try await repository.commit(message: "Commit \(i)")
        }
        
        // Stream commits
        let commits = try await repository.getAllCommits(limit: 10)
        
        #expect(commits.count == 5, "Should have 5 commits")
        #expect(commits[0].title == "Commit 5", "Most recent commit first")
    }
    
    @Test func testGetCommitByHash() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        
        let repository = GitRepository(url: repoURL)
        
        // Create commit
        try createTestFile(in: repoURL, named: "file.txt", content: "Content")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Test commit")
        
        guard let hash = try await repository.getHEAD() else {
            Issue.record("No HEAD")
            return
        }
        
        // Get commit by hash
        let commit = try await repository.getCommit(hash)
        
        #expect(commit != nil, "Should get commit by hash")
        #expect(commit?.title == "Test commit", "Should have correct title")
    }

    @Test func testGetChangedFiles() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        
        let repository = GitRepository(url: repoURL)
        
        // Create initial commit
        try createTestFile(in: repoURL, named: "file1.txt", content: "Content 1")
        try createTestFile(in: repoURL, named: "file2.txt", content: "Content 2")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Initial")
        
        // Create second commit with changes
        try createTestFile(in: repoURL, named: "file1.txt", content: "Modified")
        try createTestFile(in: repoURL, named: "file3.txt", content: "New file")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Changes")
        
        guard let hash = try await repository.getHEAD() else {
            Issue.record("No HEAD")
            return
        }
        
        // Get changed files
        let changes = try await repository.getChangedFiles(hash)
        
        #expect(changes.count == 2, "Should have 2 changed files")
        #expect(changes["file1.txt"]?.changeType == .modified)
        #expect(changes["file3.txt"]?.changeType == .added)
    }

    @Test func testCompareWithGitLog() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Create commits first!
        for i in 1...5 {
            let file = "file\(i).txt"
            try createTestFile(in: repoURL, named: file, content: "Content \(i)")
            try await repository.stageFile(at: file)
            try await repository.commit(message: "Commit \(i)")
        }
        
        // Get our commits
        let ourCommits = try await repository.getAllCommits(limit: 100).map(\.id)
        
        // Get git commits
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "log", "--all", "--pretty=format:%H", "-n", "100"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            Issue.record("Failed to read git output")
            return
        }
        
        let gitCommits = output.split(separator: "\n").map(String.init)
        
        // Assertions!
        #expect(ourCommits.count == gitCommits.count, "Should have same number of commits")
        #expect(Set(ourCommits) == Set(gitCommits), "Should have exact same commits")
    }
}

// MARK: - Test Helpers
private extension CommitStreamTests {
    func createTestFile(in repoURL: URL, named: String, content: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func gitReset(in repoURL: URL, hard: Bool = false) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        var args = ["-C", repoURL.path, "reset"]
        if hard {
            args.append("--hard")
        }
        args.append("HEAD")
        task.arguments = args
        task.launch()
        task.waitUntilExit()
    }
}
