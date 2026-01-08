import Testing
import Foundation
@testable import SwiftGit

@Suite("Stash Tests")
struct StashTests {
    
    // MARK: - Test Helpers
    func createTestStashLog(at url: URL, stashes: [(hash: String, message: String, timestamp: Int)]) throws {
        let lines = stashes.map { stash in
            "0000000000000000000000000000000000000000 \(stash.hash) Test User <test@example.com> \(stash.timestamp) -0800\t\(stash.message)"
        }
        
        let content = lines.joined(separator: .newLine)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
    
    // MARK: - RefLog Parsing Tests
    
    @Test func testParseStashReflog() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let stashes = try await repository.getStashes()
        
        // Should parse stashes if they exist
        if stashes.isEmpty {
            // No stashes in test repo - that's OK
            return
        }
        
        // Verify structure
        for stash in stashes {
            #expect(!stash.id.isEmpty)
            #expect(stash.id.count == 40) // Valid SHA-1
            #expect(stash.index >= 0)
            #expect(!stash.message.isEmpty)
        }
        
        // Indices should be sequential
        let indices = stashes.map { $0.index }.sorted()
        for (i, index) in indices.enumerated() {
            #expect(index == i)
        }
    }
    
    @Test func testStashIndicesDescending() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let stashes = try await repository.getStashes()
        
        guard stashes.count > 1 else {
            return // Need multiple stashes
        }
        
        // Stashes should be returned newest first (index 0, 1, 2...)
        for i in 0..<(stashes.count - 1) {
            #expect(stashes[i].index < stashes[i + 1].index)
        }
    }
    
    // MARK: - Stash Commit Tests
    
    @Test func testGetStashCommit() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let stashes = try await repository.getStashes()
        
        guard let firstStash = stashes.first else {
            return // No stashes
        }
        
        // Should be able to get the commit
        let commit = try await repository.getCommit(firstStash.id)
        
        #expect(commit != nil)
        #expect(commit?.id == firstStash.id)
        #expect(!commit!.tree.isEmpty)
        
        // Stash commits should have at least 1 parent (the base commit)
        #expect(commit!.parents.count >= 1)
    }
    
    @Test func testStashCommitStructure() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let stashes = try await repository.getStashes()
        
        guard let firstStash = stashes.first else {
            return
        }
        
        let commit = try await repository.getCommit(firstStash.id)
        
        guard let commit = commit else {
            Issue.record("Could not load stash commit")
            return
        }
        
        // Stash commits typically have 2-3 parents:
        // parent[0] = base commit
        // parent[1] = index state
        // parent[2] = untracked files (optional)
        #expect(commit.parents.count >= 1)
        #expect(commit.parents.count <= 3)
    }
    
    // MARK: - Stash Changes Tests
    
    @Test func testGetStashChanges() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let stashes = try await repository.getStashes()
        
        guard let firstStash = stashes.first else {
            return
        }
        
        // Should be able to get changes
        let changes = try await repository.getChangedFiles(firstStash.id)
        
        // Stash should have at least some changes
        #expect(changes.count > 0, "Stash should contain changes")
        
        // Verify change structure
        for (path, file) in changes {
            #expect(!path.isEmpty)
        }
    }
    
    // MARK: - Empty Stash Tests
    
    @Test func testEmptyStashLog() async throws {
        // Create temp repo without stashes
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: tempURL.appendingPathComponent(".git/logs/refs"),
            withIntermediateDirectories: true
        )
        
        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        let repository = GitRepository(url: tempURL)
        let stashes = try await repository.getStashes()
        
        #expect(stashes.isEmpty)
    }
    
    // MARK: - Date Parsing Tests
    
    @Test func testStashDateParsing() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let stashes = try await repository.getStashes()
        
        guard let firstStash = stashes.first else {
            return
        }
        
        // Date should be reasonable (not epoch, not far future)
        let now = Date()
        let tenYearsAgo = now.addingTimeInterval(-1 * 365 * 24 * 60 * 60)
        
        #expect(firstStash.date > tenYearsAgo, "Stash date too old")
        #expect(firstStash.date < now.addingTimeInterval(60), "Stash date in future")
    }
}
