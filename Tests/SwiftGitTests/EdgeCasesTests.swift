import Testing
import Foundation
@testable import SwiftGit

@Suite("Edge Cases Tests")
struct EdgeCasesTests {
    @Test func testEmptyRepository() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let refReader = RefReader(repoURL: repoURL, cache: ObjectCache())
        
        let refs = try await refReader.getRefs()
        #expect(refs.count == 0)
        
        let head = try await refReader.getHEAD()
        #expect(head == nil)
        
        let locator = ObjectLocator(
            repoURL: repoURL,
            packIndexManager: PackIndexManager(repoURL: repoURL)
        )
        
        let fakeHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let location = try await locator.locate(fakeHash)
        #expect(location == nil)
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

    @Test func testInvalidPackedRefsFormat() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        
        // Malformed packed-refs
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        invalid line without hash
        notahash refs/heads/main
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
        """
        try writePackedRefs(packedRefsContent, to: repoURL)
        
        let refReader = RefReader(repoURL: repoURL, cache: ObjectCache())

        // Should not crash, should skip invalid lines
        let refs = try await refReader.getRefs()
        #expect(refs.count == 0) // All lines were invalid
    }

    @Test func testInvalidHEADContent() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        
        // Invalid HEAD content
        try writeHEAD("this is not a valid ref or hash", to: repoURL)
        
        let refReader = RefReader(repoURL: repoURL, cache: ObjectCache())
        
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
}

// MARK: - Private helpers
private extension EdgeCasesTests {
    func writePackedRefs(_ content: String, to repoURL: URL) throws {
        let gitDir = repoURL.appendingPathComponent(GitPath.git.rawValue)
        let packedFile = gitDir.appendingPathComponent(GitPath.packedRefs.rawValue)
        try content.write(to: packedFile, atomically: true, encoding: .utf8)
    }
    
    func writeHEAD(_ content: String, to repoURL: URL) throws {
        let gitDir = repoURL.appendingPathComponent(GitPath.git.rawValue)
        let headFile = gitDir.appendingPathComponent(GitPath.head.rawValue)
        try content.write(to: headFile, atomically: true, encoding: .utf8)
    }
}
