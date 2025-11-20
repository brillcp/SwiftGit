import Testing
import Foundation
@testable import SwiftGit
import CryptoKit

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
    
    @Test func testPackIndexManagerLoadsRealPackFiles() async throws {
        // This test requires a real Git repo with pack files
        // For now, we'll test that the pack index manager handles empty pack directories
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let packDir = gitDir.appendingPathComponent("objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        print("📁 Created empty pack directory: \(packDir.path)")
        
        let packIndexManager = PackIndexManager(gitURL: gitDir)
        
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: packIndexManager
        )
        
        let fakeHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let location = try await locator.locate(fakeHash)
        
        #expect(location == nil, "Should not find object when no packs exist")
        
        print("✅ Correctly handles empty pack directory")
    }

    @Test func testObjectLocatorWithMixedLooseAndPacked() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        let packDir = objectsDir.appendingPathComponent("pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        // Create a loose object
        let content = "test content"
        let data = Data(content.utf8)
        
        let header = "blob \(data.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(data)
        
        let hash = Insecure.SHA1.hash(data: fullContent)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        let prefix = String(hashString.prefix(2))
        let suffix = String(hashString.dropFirst(2))
        
        let prefixDir = objectsDir.appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        
        print("✅ Created loose object: \(hashString)")
        
        // Create locator
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        // Should find the loose object
        let location = try await locator.locate(hashString)
        #expect(location != nil, "Should find loose object")
        
        if case .loose(let url) = location {
            print("✅ Found loose object at: \(url.path)")
        } else {
            Issue.record("Expected loose object, got: \(String(describing: location))")
        }
        
        // Should not find non-existent object (even with empty pack dir)
        let fakeHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let fakeLocation = try await locator.locate(fakeHash)
        #expect(fakeLocation == nil, "Should not find non-existent object")
    }

    @Test("Full workflow: getHEAD → getCommit after git gc")
    func testFullWorkflowAfterGitGC() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        let refsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        
        print(String(repeating: "=", count: 60))
        print("TEST: getHEAD workflow after git gc")
        print(String(repeating: "=", count: 60))
        
        // Create a commit object
        let commitContent = """
        tree b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3
        author Test <test@test.com> 1234567890 +0000
        committer Test <test@test.com> 1234567890 +0000
        
        Initial commit
        """
        
        let commitData = Data(commitContent.utf8)
        let header = "commit \(commitData.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(commitData)
        
        let hash = Insecure.SHA1.hash(data: fullContent)
        let commitHash = hash.map { String(format: "%02x", $0) }.joined()
        
        print("🎯 Commit hash: \(commitHash)")
        
        // Setup: packed refs (no loose refs)
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(commitHash) refs/heads/main
        """
        
        let packedRefsFile = gitDir.appendingPathComponent("packed-refs")
        try packedRefsContent.write(to: packedRefsFile, atomically: true, encoding: .utf8)
        print("✅ Created packed-refs")
        
        let headFile = gitDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main".write(to: headFile, atomically: true, encoding: .utf8)
        print("✅ Created HEAD")
        
        // Create the commit as loose object
        let prefix = String(commitHash.prefix(2))
        let suffix = String(commitHash.dropFirst(2))
        let prefixDir = objectsDir.appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        print("✅ Created commit object")
        
        // Create locator and ref reader
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        let refReader = RefReader(
            repoURL: tempDir,
            objectExistsCheck: { hash in
                try await locator.exists(hash)
            }
        )
        
        // Step 1: Get HEAD (this was the original problem!)
        print("\n🔍 Step 1: Getting HEAD...")
        let head = try await refReader.getHEAD()
        print("✅ HEAD resolved to: \(head ?? "nil")")
        
        #expect(head == commitHash, "HEAD should resolve to commit hash from packed-refs")
        
        // Step 2: Verify object exists
        print("\n🔍 Step 2: Checking if commit exists...")
        let exists = try await locator.exists(commitHash)
        print("✅ Commit exists: \(exists)")
        
        #expect(exists, "Commit should exist")
        
        // Step 3: Locate the object
        print("\n🔍 Step 3: Locating commit...")
        let location = try await locator.locate(commitHash)
        print("✅ Commit location: \(String(describing: location))")
        
        #expect(location != nil, "Should be able to locate commit")
        
        print("\n✅ Full workflow successful!")
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
