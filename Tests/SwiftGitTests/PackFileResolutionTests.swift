import Testing
import Foundation
@testable import SwiftGit

@Suite("Pack File Resolution Tests")
struct PackFileResolutionTests {
    
    func createTestRepo(in tempDir: URL) throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        let refsDir = gitDir.appendingPathComponent("refs/heads")
        
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
    }
    
    func writeHEAD(_ content: String, to repoURL: URL) throws {
        let headFile = repoURL.appendingPathComponent(".git/HEAD")
        try content.write(to: headFile, atomically: true, encoding: .utf8)
    }
    
    func writePackedRefs(_ content: String, to repoURL: URL) throws {
        let packedFile = repoURL.appendingPathComponent(".git/packed-refs")
        try content.write(to: packedFile, atomically: true, encoding: .utf8)
    }
    
    func createPackFiles(at repoURL: URL, packName: String, hashes: [String]) throws {
        let packDir = repoURL.appendingPathComponent(".git/objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        // Create a minimal .idx file
        let idxURL = packDir.appendingPathComponent("pack-\(packName).idx")
        let packURL = packDir.appendingPathComponent("pack-\(packName).pack")
        
        // Create dummy pack file
        try Data().write(to: packURL)
        
        // Create a simple .idx file with the hashes
        // This is a simplified version - real Git idx format is more complex
        var idxData = Data()
        
        // Header: magic number and version
        idxData.append(contentsOf: [0xff, 0x74, 0x4f, 0x63]) // ÿtOc magic
        idxData.append(contentsOf: [0x00, 0x00, 0x00, 0x02]) // version 2
        
        // Fan-out table (256 entries of 4 bytes each)
        // Each entry is the cumulative count of objects whose first byte is <= that index
        for i in 0..<256 {
            let count = hashes.filter {
                let firstByte = Int($0.prefix(2), radix: 16) ?? 0
                return firstByte <= i
            }.count
            idxData.append(contentsOf: withUnsafeBytes(of: UInt32(count).bigEndian) { Array($0) })
        }
        
        // Object names (sorted SHA-1s)
        let sortedHashes = hashes.sorted()
        for hash in sortedHashes {
            // Convert hex string to 20 bytes
            let bytes = stride(from: 0, to: hash.count, by: 2).compactMap {
                UInt8(hash[$0..<min($0 + 2, hash.count)], radix: 16)
            }
            idxData.append(contentsOf: bytes)
        }
        
        // CRC32 values (4 bytes each) - use dummy values
        for _ in sortedHashes {
            idxData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        }
        
        // Pack file offsets (4 bytes each) - use dummy values
        for i in 0..<sortedHashes.count {
            idxData.append(contentsOf: withUnsafeBytes(of: UInt32(i * 100).bigEndian) { Array($0) })
        }
        
        // Pack checksum (20 bytes) - dummy
        idxData.append(contentsOf: Array(repeating: UInt8(0), count: 20))
        
        // Index checksum (20 bytes) - dummy
        idxData.append(contentsOf: Array(repeating: UInt8(0), count: 20))
        
        try idxData.write(to: idxURL)
    }
    
    // MARK: - The Critical Test!
    
    @Test("Resolve HEAD after git gc with unpushed commits")
    func testResolveHEADAfterGitGCWithUnpushedCommits() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        // Simulate the scenario:
        // 1. You're on main branch
        // 2. You've made commits locally (not pushed)
        // 3. git gc ran - everything is packed, no loose refs
        
        let localCommitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let remoteCommitHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        // After git gc: refs are in packed-refs, no loose ref files
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(localCommitHash) refs/heads/main
        \(localCommitHash) refs/heads/feature
        \(localCommitHash) refs/heads/refactor
        \(remoteCommitHash) refs/remotes/origin/main
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        // HEAD points to main
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        
        // All objects are in pack files
        try createPackFiles(
            at: tempDir,
            packName: "test-pack",
            hashes: [localCommitHash, remoteCommitHash]
        )
        
        // Now test that we can resolve HEAD correctly
        let refReader = RefReader(repoURL: tempDir)
        let head = try await refReader.getHEAD()
        
        print("🔍 Resolved HEAD: \(head ?? "nil")")
        print("🎯 Expected: \(localCommitHash)")
        
        #expect(head == localCommitHash, "HEAD should resolve to local commit hash from packed-refs")
        
        // Also verify the branch name is correct
        let branch = try await refReader.getHEADBranch()
        #expect(branch == "main")
        
        // And verify we can get all refs
        let refs = try await refReader.getRefs()
        print("📦 Found \(refs.count) refs")
        
        #expect(refs.count == 4)
        #expect(refs.contains { $0.name == "main" && $0.hash == localCommitHash && $0.type == .localBranch })
        #expect(refs.contains { $0.name == "feature" && $0.hash == localCommitHash && $0.type == .localBranch })
        #expect(refs.contains { $0.name == "refactor" && $0.hash == localCommitHash && $0.type == .localBranch })
        #expect(refs.contains { $0.name == "origin/main" && $0.hash == remoteCommitHash && $0.type == .remoteBranch })
    }
    
    @Test("ObjectLocator finds object in pack after git gc")
    func testObjectLocatorFindsPackedObject() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let treeHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        let blobHash = "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
        
        // Create pack files with these objects
        try createPackFiles(
            at: tempDir,
            packName: "after-gc",
            hashes: [commitHash, treeHash, blobHash]
        )
        
        // Create locator and scan
        let locator = ObjectLocator(
            gitURL: tempDir,
            packIndexManager: PackIndexManager(gitURL: tempDir)
        )
        
        // Try to locate each object
        print("🔍 Looking for commit: \(commitHash)")
        let commitLocation = try await locator.locate(commitHash)
        #expect(commitLocation != nil, "Should find commit in pack")
        
        print("🔍 Looking for tree: \(treeHash)")
        let treeLocation = try await locator.locate(treeHash)
        #expect(treeLocation != nil, "Should find tree in pack")
        
        print("🔍 Looking for blob: \(blobHash)")
        let blobLocation = try await locator.locate(blobHash)
        #expect(blobLocation != nil, "Should find blob in pack")
        
        // Verify they're all packed (not loose)
        if case .packed = commitLocation {
            // Good!
        } else {
            Issue.record("Commit should be in pack, not loose")
        }
    }
    
    @Test("Full workflow: getHEAD → getCommit after git gc")
    func testFullWorkflowAfterGitGC() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        
        // Setup: packed refs + packed objects
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(commitHash) refs/heads/main
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        try createPackFiles(at: tempDir, packName: "gc-pack", hashes: [commitHash])
        
        // Create repository
        let locator = ObjectLocator(
            gitURL: tempDir,
            packIndexManager: PackIndexManager(gitURL: tempDir)
        )
        let refReader = RefReader(
            repoURL: tempDir,
            objectExistsCheck: { hash in
                try await locator.exists(hash)
            }
        )
                
        // Step 1: Get HEAD (this was failing before!)
        print("🔍 Step 1: Getting HEAD...")
        let head = try await refReader.getHEAD()
        print("✅ HEAD resolved to: \(head ?? "nil")")
        
        #expect(head == commitHash, "HEAD should resolve to commit hash from packed-refs")
        
        // Step 2: Verify object exists
        print("🔍 Step 2: Checking if commit exists...")
        let exists = try await locator.exists(commitHash)
        print("✅ Commit exists: \(exists)")
        
        #expect(exists, "Commit should exist in pack")
        
        // Step 3: Locate the object
        print("🔍 Step 3: Locating commit...")
        let location = try await locator.locate(commitHash)
        print("✅ Commit location: \(location != nil ? "found" : "not found")")
        
        #expect(location != nil, "Should be able to locate commit in pack")
    }
    
    @Test("Debug: Print pack index contents")
    func testDebugPackIndexContents() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let hash1 = "1234567890abcdef1234567890abcdef12345678"
        let hash2 = "abcdef1234567890abcdef1234567890abcdef12"
        let hash3 = "fedcba0987654321fedcba0987654321fedcba09"
        
        try createPackFiles(
            at: tempDir,
            packName: "debug",
            hashes: [hash1, hash2, hash3]
        )
        
        let locator = ObjectLocator(
            gitURL: tempDir,
            packIndexManager: PackIndexManager(gitURL: tempDir)
        )
        
        // Try to locate and print debug info
        for hash in [hash1, hash2, hash3] {
            print("🔍 Looking for: \(hash)")
            let location = try await locator.locate(hash)
            
            if let location = location {
                print("✅ Found: \(location)")
            } else {
                print("❌ NOT FOUND")
            }
        }
        
        #expect(true, "This test is for debugging - check the console output")
    }
}

// Helper extension for string subscripting
extension String {
    subscript(range: Range<Int>) -> String {
        let start = index(startIndex, offsetBy: range.lowerBound)
        let end = index(startIndex, offsetBy: range.upperBound)
        return String(self[start..<end])
    }
}
