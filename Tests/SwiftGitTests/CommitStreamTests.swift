import Testing
import Foundation
@testable import SwiftGit

@Suite("Commit Stream Tests")
struct CommitStreamTests {
    // MARK: - Refs Loading Tests
    @Test func testGetAllRefs() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        let allRefs = try await repository.getRefs()
        
        print("\n=== ALL REFS (\(allRefs.count) total) ===")
        
        let localBranches = allRefs.filter { $0.type == .localBranch }
        print("\nLocal Branches (\(localBranches.count)):")
        for ref in localBranches.sorted(by: { $0.name < $1.name }) {
            print("  \(ref.name) -> \(ref.hash.prefix(7))")
        }
        
        let remoteBranches = allRefs.filter { $0.type == .remoteBranch }
        print("\nRemote Branches (\(remoteBranches.count)):")
        for ref in remoteBranches.sorted(by: { $0.name < $1.name }) {
            print("  \(ref.name) -> \(ref.hash.prefix(7))")
        }
        
        let tags = allRefs.filter { $0.type == .tag }
        print("\nTags (\(tags.count)):")
        for ref in tags.sorted(by: { $0.name < $1.name }) {
            print("  \(ref.name) -> \(ref.hash.prefix(7))")
        }
        
        #expect(allRefs.count > 0, "Should have at least some refs")
    }
    
    @Test func testFindSpecificBranch() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        let allRefs = try await repository.getRefs()
        
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
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
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
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        
        // Manually replicate streamAllCommits logic to see starting points
        let allRefs = try await repository.getRefs()
        
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
    
    @Test func testStreamAllCommitsCount() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        
        var commits: [Commit] = []
        
        for try await commit in await repository.streamAllCommits(limit: nil) {
            commits.append(commit)
        }
        
        print("\n=== STREAMED COMMITS ===")
        print("Total commits: \(commits.count)")
        
        // Show first 10
        print("\nFirst 10 commits:")
        for commit in commits.prefix(10) {
            print("  \(commit.id.prefix(7)) - \(commit.title)")
        }
        
        // Show last 10
        print("\nLast 10 commits:")
        for commit in commits.suffix(10) {
            print("  \(commit.id.prefix(7)) - \(commit.title)")
        }
        
        #expect(commits.count > 0, "Should stream at least some commits")
    }
    
    @Test func testSpecificCommitInStream() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        
        // Hash of commit you expect to see (from GitKraken)
        let expectedHash = "bc4fb3fbd8c83c2a1a66beb973b2b8c1ba764630"  // Replace with actual hash
        
        var found = false
        var commitCount = 0
        
        for try await commit in await repository.streamAllCommits(limit: nil) {
            commitCount += 1
            if commit.id == expectedHash {
                found = true
                print("\n✅ FOUND commit in stream at position \(commitCount):")
                print("  \(commit.id.prefix(7)) - \(commit.title)")
                break
            }
        }
        
        if !found {
            print("\n❌ Commit \(expectedHash.prefix(7)) NOT in stream")
            print("   Checked \(commitCount) commits")
        }
        
        #expect(found, "Expected commit should be in stream")
    }
    
    @Test func testCompareWithGitLog() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        #if os(macOS)
        // Get our commits
        var ourCommits: [String] = []
        for try await commit in await repository.streamAllCommits(limit: 100) {
            ourCommits.append(commit.id)
        }
        
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
            let gitCommits = output.split(separator: "\n").map(String.init)
            
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
        #else
        print("\n⏭️ Skipping git log comparison on this platform (Process is unavailable)")
        #endif
    }
    
    @Test func testStashesInStream() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
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
        
        for try await commit in await repository.streamAllCommits(limit: nil) {
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
}

// MARK: - Test Helpers
private extension CommitStreamTests {
    func getTestRepoURL() -> URL? {
        let testRepoPath = "/Users/vg/Documents/Dev/quartr-ios"
        let url = URL(fileURLWithPath: testRepoPath)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        return url
    }
}
