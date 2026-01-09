import Testing
import Foundation
@testable import SwiftGit

@Suite("Commit Tests")
struct CommitTests {
    @Test func testGetCommitFileDiff() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create initial commit
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")

        // Modify file and commit
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nModified Line 2\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Modify line 2")

        // Get the commit hash
        guard let commitHash = try await repository.getHEAD() else {
            Issue.record("No HEAD")
            return
        }

        // Get diff for this file in this commit
        let hunks = try await repository.getFileDiff(for: commitHash, at: testFile)

        // Verify we got hunks
        #expect(!hunks.isEmpty, "Should have at least one hunk")

        // Verify the diff shows the modification
        let hunk = hunks[0]
        let removedLines = hunk.lines.filter { $0.type == .removed }
        let addedLines = hunk.lines.filter { $0.type == .added }

        #expect(removedLines.count == 1, "Should have one removed line")
        #expect(addedLines.count == 1, "Should have one added line")

        // Verify content
        let removedText = removedLines[0].segments.map { $0.text }.joined()
        let addedText = addedLines[0].segments.map { $0.text }.joined()

        #expect(removedText.contains("Line 2"), "Removed line should contain 'Line 2'")
        #expect(addedText.contains("Modified"), "Added line should contain 'Modified'")
    }

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
private extension CommitTests {
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

func createIsolatedTestRepo() throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("test-repo-\(UUID().uuidString)")

    let gitDir = tempDir.appendingPathComponent(GitPath.git.rawValue)
    let objectsDir = gitDir.appendingPathComponent(GitPath.objects.rawValue)
    let refsHeadsDir = gitDir.appendingPathComponent("refs/heads")

    try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: refsHeadsDir, withIntermediateDirectories: true)

    // Add HEAD file
    let headFile = gitDir.appendingPathComponent("HEAD")
    try "ref: refs/heads/main\n".write(to: headFile, atomically: true, encoding: .utf8)

    // Add config file
    let configFile = gitDir.appendingPathComponent("config")
    let config = """
    [core]
        repositoryformatversion = 0
        filemode = true
    [user]
        name = Test User
        email = test@example.com

    """
    try config.write(to: configFile, atomically: true, encoding: .utf8)

    return tempDir
}

func createTestFile(in repoURL: URL, named: String, content: String) throws {
    let fileURL = repoURL.appendingPathComponent(named)
    try content.write(to: fileURL, atomically: true, encoding: .utf8)
}

func statusLine(for file: String, in repoURL: URL) throws -> String? {
    let output = try gitStatus(in: repoURL)
    // Each line is two status columns + space + path
    return output
        .split(separator: "\n")
        .map(String.init)
        .first { $0.hasSuffix(" \(file)") || $0.hasSuffix(file) }
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
