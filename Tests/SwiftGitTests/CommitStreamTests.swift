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
    
    @Test func testFindSpecificBranch() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let allRefs = try await repository.getRefs().flatMap(\.value)

        // Look for branches with "2848" in the name
        let branches2848 = allRefs.filter { $0.name.contains("2848") }
        
        print("\n=== BRANCHES CONTAINING '2848' ===")
        for ref in branches2848 {
            print("  \(ref.type): \(ref.name) -> \(ref.hash.prefix(7))")
        }
        
        if branches2848.isEmpty {
            print("  ❌ No branches found with '2848'")
        }
        
        // Look for branches with "IOS" in the name
        let branchesIOS = allRefs.filter { $0.name.contains("IOS") }
        
        print("\n=== BRANCHES CONTAINING 'IOS' ===")
        for ref in branchesIOS {
            print("  \(ref.type): \(ref.name) -> \(ref.hash.prefix(7))")
        }
    }
    
    // MARK: - Commit Reachability Tests
    
    @Test func testCommitExists() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Test with a known commit hash from GitKraken
        let testHash = "PUT_HASH_HERE"  // Replace with hash of "feat: add weekday to calendar"
        
        if let commit = try await repository.getCommit(testHash) {
            print("\n✅ Commit EXISTS:")
            print("  Hash: \(commit.id.prefix(7))")
            print("  Title: \(commit.title)")
            print("  Author: \(commit.author)")
            print("  Date: \(commit.author.timestamp)")
            print("  Parents: \(commit.parents.count)")
            for (i, parent) in commit.parents.enumerated() {
                print("    parent[\(i)]: \(parent.prefix(7))")
            }
        } else {
            print("\n❌ Commit NOT FOUND: \(testHash)")
        }
    }
    
    @Test func testStreamAllCommitsStartingPoints() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Manually replicate streamAllCommits logic to see starting points
        let allRefs = try await repository.getRefs().flatMap(\.value)

        let startingRefs = allRefs.filter { ref in
            switch ref.type {
            case .stash: false
            default: true
            }
        }
        
        print("\n=== STARTING POINTS FOR STREAM ===")
        print("Total starting refs: \(startingRefs.count)")
        
        for ref in startingRefs.sorted(by: { $0.name < $1.name }) {
            print("  [\(ref.type)] \(ref.name) -> \(ref.hash.prefix(7))")
        }
    }
    
    @Test func testCompareWithGitLog() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        // Get our commits
        let ourCommits: [String] = try await repository.getAllCommits(limit: 100).map(\.id)
        print("\n=== OUR COMMITS (first 100) ===")
        print("Count: \(ourCommits.count)")
        
        // Compare with git log --all
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "log", "--all", "--pretty=format:%H", "-n", "100"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let gitCommits = output.split(separator: String.newLine).map(String.init)
            
            print("\n=== GIT LOG --all (first 100) ===")
            print("Count: \(gitCommits.count)")
            
            // Find commits in git but not in our stream
            let missing = gitCommits.filter { !ourCommits.contains($0) }
            
            if missing.isEmpty {
                print("\n✅ All git commits found in our stream")
            } else {
                print("\n❌ Missing \(missing.count) commits:")
                for hash in missing.prefix(10) {
                    print("  \(hash.prefix(7))")
                }
            }
            
            // Find commits in our stream but not in git (shouldn't happen)
            let extra = ourCommits.filter { !gitCommits.contains($0) }
            if !extra.isEmpty {
                print("\n⚠️  Extra \(extra.count) commits in our stream:")
                for hash in extra.prefix(10) {
                    print("  \(hash.prefix(7))")
                }
            }
        }
    }
    
    @Test func testStashesInStream() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Get stashes separately
        let stashes = try await repository.getStashes()
        
        print("\n=== STASHES ===")
        print("Count: \(stashes.count)")
        for stash in stashes {
            print("  \(stash.message): \(stash.id.prefix(7)) - \(stash.message)")
        }
        
        // Check if stashes appear in stream
        var stashCommitsInStream = Set<String>()
        
        let commits = try await repository.getAllCommits(limit: 2048)
        for commit in commits {
            if stashes.contains(where: { $0.id == commit.id }) {
                stashCommitsInStream.insert(commit.id)
            }
        }

        print("\n=== STASHES IN STREAM ===")
        print("Found: \(stashCommitsInStream.count) / \(stashes.count)")
        
        for stash in stashes {
            if stashCommitsInStream.contains(stash.id) {
                print("  ✅ \(stash.message)")
            } else {
                print("  ❌ \(stash.message) MISSING")
            }
        }
    }

    @Test func testCommitComparison() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Get OUR commits
        var ourCommits: [Commit] = []
        var seenHashes = Set<String>()
        
        let commits = try await repository.getAllCommits(limit: 512)

        for commit in commits {
            if !seenHashes.contains(commit.id) {
                seenHashes.insert(commit.id)
                ourCommits.append(commit)
            }
        }
        
        // Sort by date
        ourCommits.sort { $0.author.timestamp > $1.author.timestamp }
        
        print("\n=== OUR COMMITS (sorted by date) ===")
        print("Total: \(ourCommits.count)")
        print("\nFirst 30:")
        for (i, commit) in ourCommits.prefix(30).enumerated() {
            let dateStr = ISO8601DateFormatter().string(from: commit.author.timestamp)
            print("\(i+1). [\(dateStr)] \(commit.title)")
        }
        
        // Get GIT's commits
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = [
            "-C", repoURL.path,
            "log", "--all",
            "--pretty=format:%H|%ai|%s",
            "-n", "30"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            print("\n=== GIT LOG --all (sorted by date) ===")
            let lines = output.split(separator: String.newLine)
            print("Total: \(lines.count)")
            print("\nFirst 30:")
            for (i, line) in lines.enumerated() {
                let parts = line.split(separator: "|")
                if parts.count >= 3 {
                    print("\(i+1). [\(parts[1])] \(parts[2])")
                }
            }
        }
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
