import Testing
import Foundation
@testable import SwiftGit

@Suite("Edge Cases Tests")
struct EdgeCasesTests {
    @Test func testEmptyRepository() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let refReader = RefReader(commandRunner: CommandRunner(repoURL: repoURL), cache: ObjectCache())

        let refs = try await refReader.getRefs()
        #expect(refs.count == 0)

        let head = try await refReader.getHEAD()
        #expect(head == nil)

        let headBranch = try await refReader.getHEADBranch()
        #expect(headBranch == "main")

        let stashes = try await refReader.getStashes()
        #expect(stashes.isEmpty)
    }

    @Test func testEmptyCommitMessage() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create and stage a file
        try createTestFile(in: repoURL, named: "file.txt", content: "Content")
        try await repository.stageFile(at: "file.txt")

        // Try to commit with empty message
        do {
            try await repository.commit(message: "")
            Issue.record("Expected commit to throw GitError.emptyCommitMessage for empty message")
        } catch {
            // Verify it's the expected error without requiring Equatable conformance
            if let gitError = error as? GitError {
                switch gitError {
                case .emptyCommitMessage:
                    break // expected
                default:
                    Issue.record("Unexpected GitError thrown: \(gitError)")
                }
            } else {
                Issue.record("Unexpected error type thrown: \(error)")
            }
        }

        // Try with whitespace only
        do {
            try await repository.commit(message: "   \n\t  ")
            Issue.record("Expected commit to throw GitError.emptyCommitMessage for whitespace-only message")
        } catch {
            if let gitError = error as? GitError {
                switch gitError {
                case .emptyCommitMessage:
                    break // expected
                default:
                    Issue.record("Unexpected GitError thrown: \(gitError)")
                }
            } else {
                Issue.record("Unexpected error type thrown: \(error)")
            }
        }

        // Valid message should work
        try await repository.commit(message: "Valid message")

        let commits = try await repository.getAllCommits(limit: 1)
        #expect(commits.count == 1, "Should have created commit with valid message")
    }

    @Test func testInvalidHEADContent() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }


        // Invalid HEAD content
        try writeHEAD("this is not a valid ref or hash", to: repoURL)

        let refReader = RefReader(commandRunner: CommandRunner(repoURL: repoURL), cache: ObjectCache())

        let head = try await refReader.getHEAD()
        #expect(head == nil) // Should handle gracefully
    }

    @Test func testDetachedHEAD() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create commit
        try createTestFile(in: repoURL, named: "file.txt", content: "Content")
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: "Test")

        guard let hash = try await repository.getHEAD() else {
            Issue.record("No HEAD")
            return
        }

        // Detach HEAD (write hash directly)
        let headFile = repoURL.appendingPathComponent(".git/HEAD")
        try hash.write(to: headFile, atomically: true, encoding: .utf8)

        // Should still work
        let detachedHead = try await repository.getHEAD()
        #expect(detachedHead == hash, "Should read detached HEAD")
    }

    @Test func testGetMergeCommitFilesWithMultipleParents() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)

        // Create initial commit on main
        try createTestFile(in: repoURL, named: "main.txt", content: "Main content")
        try await repository.stageFile(at: "main.txt")
        try await repository.commit(message: "Initial on main")

        // Create and checkout feature branch
        try await repository.checkoutBranch("feature", createNew: true)

        // Add multiple files on feature branch
        try createTestFile(in: repoURL, named: "feature1.txt", content: "Feature 1")
        try createTestFile(in: repoURL, named: "feature2.txt", content: "Feature 2")
        try createTestFile(in: repoURL, named: "feature3.txt", content: "Feature 3")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Add feature files")

        // Modify main.txt on feature branch
        try createTestFile(in: repoURL, named: "main.txt", content: "Modified on feature")
        try await repository.stageFile(at: "main.txt")
        try await repository.commit(message: "Modify main.txt on feature")

        // Go back to main and add a different file (no conflict)
        try await repository.checkoutBranch("main", createNew: false)
        try createTestFile(in: repoURL, named: "main2.txt", content: "Another main file")
        try await repository.stageFile(at: "main2.txt")
        try await repository.commit(message: "Add main2.txt on main")

        // Merge feature into main (no conflicts)
        try await repository.merge(branch: "feature", noFastForward: true)

        // Get the merge commit (HEAD)
        guard let mergeHash = try await repository.getHEAD() else {
            Issue.record("No HEAD")
            return
        }

        print("📦 Merge commit: \(mergeHash)")

        // Get files changed in merge commit
        let files = try await repository.getCommittedFiles(mergeHash)

        print("📦 Files in merge: \(files.keys.sorted())")
        print("📦 File count: \(files.count)")

        #expect(files.count >= 4, "Should show at least 4 files (main.txt + feature1-3)")
        #expect(files["main.txt"] != nil, "Should include main.txt")
        #expect(files["feature1.txt"] != nil, "Should include feature1.txt")
        #expect(files["feature2.txt"] != nil, "Should include feature2.txt")
        #expect(files["feature3.txt"] != nil, "Should include feature3.txt")

        // Try to get content for each file
        for (path, _) in files {
            print("📦 Getting content for: \(path)")
            let content = try await repository.getFileContent(at: path, ref: mergeHash)
            #expect(!content.isEmpty, "Content for \(path) should not be empty")
            print("📦 Content length for \(path): \(content.count)")
        }
    }
}

// MARK: - Private helpers
private extension EdgeCasesTests {
    func writeHEAD(_ content: String, to repoURL: URL) throws {
        let gitDir = repoURL.appendingPathComponent(GitPath.git.rawValue)
        let headFile = gitDir.appendingPathComponent(GitPath.head.rawValue)
        try content.write(to: headFile, atomically: true, encoding: .utf8)
    }
}
