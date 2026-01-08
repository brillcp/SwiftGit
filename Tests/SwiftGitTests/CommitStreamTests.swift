import Testing
import Foundation
@testable import SwiftGit

@Suite("Commit Stream Tests")
struct CommitStreamTests {
    @Test func testCommitCacheInvalidation() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_cache_\(UUID().uuidString).txt"
        
        // Create and stage a file
        try createTestFile(in: repoURL, named: testFile, content: "Test content")
        try await repository.stageFile(at: testFile)
        
        // Get index SHA before commit
        let indexURL = repoURL.appendingPathComponent(".git/index")
        let modDateBefore = try FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate] as? Date
        
        print("\n=== BEFORE COMMIT ===")
        print("Index modDate: \(modDateBefore!)")
        
        let stagedBefore = try await repository.getWorkingTreeStatus().files.values.filter(\.isStaged)
        print("Staged count: \(stagedBefore.count)")
        
        // Small delay to ensure we're in a different millisecond
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Commit
        try await repository.commit(message: "Test commit")
        
        // Check index modDate after commit
        let modDateAfter = try FileManager.default.attributesOfItem(atPath: indexURL.path)[.modificationDate] as? Date
        
        print("\n=== AFTER COMMIT ===")
        print("Index modDate: \(modDateAfter!)")
        print("ModDate changed: \(modDateBefore != modDateAfter)")
        print("Time difference: \(modDateAfter!.timeIntervalSince(modDateBefore!))s")
        
        // Try reading staged multiple times
        for i in 1...3 {
            let staged = try await repository.getWorkingTreeStatus().files.filter(\.value.isStaged)
            print("\nLoad \(i):")
            print("  Staged count: \(staged.count)")
            print("  Keys: \(staged.keys)")
        }
        
        // Cleanup
        try gitReset(in: repoURL, hard: true)
        try? FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
    }

    @Test func testCommitClearsStaged() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_commit_\(UUID().uuidString).txt"
        
        // Create and stage a file
        try createTestFile(in: repoURL, named: testFile, content: "Test content")
        try await repository.stageFile(at: testFile)
        
        // Verify file is staged
        let stagedBefore = try await repository.getWorkingTreeStatus().files.filter(\.value.isStaged)
        #expect(stagedBefore[testFile] != nil, "File should be staged before commit")
        
        // Commit
        try await repository.commit(message: "Test commit")
        
        // Verify staged is now empty
        let stagedAfter = try await repository.getWorkingTreeStatus().files.filter(\.value.isStaged)
        print("\n=== AFTER COMMIT ===")
        print("Staged files: \(stagedAfter.keys)")
        print("Count: \(stagedAfter.count)")
        print("=== END ===\n")
        
        #expect(stagedAfter.isEmpty, "Should have no staged files after commit")
        #expect(stagedAfter[testFile] == nil, "Test file should not be staged after commit")
        
        // Cleanup
        try gitReset(in: repoURL, hard: true)
        try? FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
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
            print("Load \(i): \(staged.count) staged files")
            #expect(staged.isEmpty, "Load \(i) should show no staged files")
        }
        
        // Cleanup
        try gitReset(in: repoURL, hard: true)
        try? FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
    }

    @Test func testCommitLoadingPerformance() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Warm up (load pack indexes, etc.)
        _ = try await repository.getHEAD()
        
        // Measure commit loading
        let start = Date()
        let commits = try await repository.getAllCommits(limit: 2048)
        let elapsed = Date().timeIntervalSince(start)
        
        print("\n=== COMMIT LOADING PERFORMANCE ===")
        print("Loaded \(commits.count) commits in \(elapsed)s")
        print("Average per commit: \(elapsed / Double(commits.count))s")
        print("=== END ===\n")
        
        #expect(commits.count > 0, "Should load at least some commits")
    }

    @Test func testIndividualCommitLoadSpeed() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        guard let headHash = try await repository.getHEAD() else {
            Issue.record("No HEAD found")
            return
        }
        
        // First load (cold cache)
        let coldStart = Date()
        _ = try await repository.getCommit(headHash)
        let coldElapsed = Date().timeIntervalSince(coldStart)
        
        // Second load (warm cache)
        let warmStart = Date()
        _ = try await repository.getCommit(headHash)
        let warmElapsed = Date().timeIntervalSince(warmStart)
        
        print("\n=== INDIVIDUAL COMMIT LOAD ===")
        print("Cold cache: \(coldElapsed)s")
        print("Warm cache: \(warmElapsed)s")
        print("=== END ===\n")
        
        // Warm cache should be <1ms
        #expect(warmElapsed < 0.001, "Cached commit load took \(warmElapsed)s")
        
        // Cold cache should be <50ms
        #expect(coldElapsed < 0.05, "First commit load took \(coldElapsed)s")
    }

    @Test func testPackIndexCacheEffectiveness() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Get a series of commits (should share pack file ranges)
        let commits = try await repository.getAllCommits(limit: 50)
        
        guard commits.count >= 10 else {
            Issue.record("Not enough commits to test")
            return
        }
        
        // Load first 10 commits individually
        let start = Date()
        for commit in commits.prefix(10) {
            _ = try await repository.getCommit(commit.id)
        }
        let elapsed = Date().timeIntervalSince(start)
        
        print("\n=== PACK CACHE TEST ===")
        print("Re-loaded 10 commits in \(elapsed)s")
        print("Average: \(elapsed / 10.0)s per commit")
        print("=== END ===\n")
        
        // With cache, should be very fast (all cached)
        #expect(elapsed < 0.01, "10 cached commits took \(elapsed)s (expected <10ms)")
    }

    @Test func testCommitDiffMatchesGit() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Use a known commit hash from GitKraken
        let commitHash = "a842fa5f80d0163f4030c6ee47b2c673a3ac1826"  // The one from your screenshots
        
        // Get your diff
        let yourChanges = try await repository.getChangedFiles(commitHash)
        
        print("\n=== YOUR CHANGED FILES (\(yourChanges.count)) ===")
        for (path, file) in yourChanges.sorted(by: { $0.key < $1.key }) {
            print("  [\(file.changeType)] \(path)")
        }
        
        // Get Git's diff
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = [
            "-C", repoURL.path,
            "diff-tree", "--no-commit-id", "--name-status", "-r",
            commitHash
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            let gitChanges = output.split(separator: String.newLine)
            
            print("\n=== GIT CHANGED FILES (\(gitChanges.count)) ===")
            for line in gitChanges {
                print("  \(line)")
            }
            
            // Compare
            let yourPaths = Set(yourChanges.keys)
            let gitPaths = Set(gitChanges.map { line in
                String(line.split(separator: "\t").last!)
            })
            
            let extra = yourPaths.subtracting(gitPaths)
            let missing = gitPaths.subtracting(yourPaths)
            
            if !extra.isEmpty {
                print("\n❌ EXTRA FILES (false positives):")
                for path in extra.sorted() {
                    print("  \(path)")
                }
            }
            
            if !missing.isEmpty {
                print("\n❌ MISSING FILES (false negatives):")
                for path in missing.sorted() {
                    print("  \(path)")
                }
            }
            
            if extra.isEmpty && missing.isEmpty {
                print("\n✅ Perfect match!")
            }
        }
    }

    @Test func testGetAllRefs() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let allRefs = try await repository.getRefs().flatMap(\.value)
        
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
    
    @Test func testStreamAllCommitsCount() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        let commits = try await repository.getAllCommits(limit: 512)
        
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
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        
        // Hash of commit you expect to see (from GitKraken)
        let expectedHash = "068ce37832990168f161a46548a6d9868378f5c5"  // Replace with actual hash
        
        var found = false
        var commitCount = 0
        
        let commits = try await repository.getAllCommits(limit: 512)
        for commit in commits {
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
