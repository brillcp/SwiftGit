import Testing
import Foundation
@testable import SwiftGit
import CryptoKit

@Suite("Integration Tests")
struct IntegrationTests {
    @Test func testFullWorkflowAfterGitGC() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let commitContent = """
        tree b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3
        author Test <test@test.com> 1234567890 +0000
        committer Test <test@test.com> 1234567890 +0000
        
        Test commit
        """
        
        let commitHash = try writeLooseObject(commitContent: commitContent, to: repoURL)
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(commitHash) refs/heads/main
        """
        try writePackedRefs(packedRefsContent, to: repoURL)
        try writeHEAD("ref: refs/heads/main", to: repoURL)
        
        let locator = ObjectLocator(
            repoURL: repoURL,
            packIndexManager: PackIndexManager(repoURL: repoURL)
        )
        
        let refReader = RefReader(
            repoURL: repoURL,
            objectExistsCheck: { hash in
                try await locator.exists(hash)
            },
            cache: ObjectCache()
        )
        
        // Step 1: Get HEAD
        let head = try await refReader.getHEAD()
        #expect(head == commitHash)
        
        // Step 2: Verify object exists
        let exists = try await locator.exists(commitHash)
        #expect(exists)
        
        // Step 3: Locate the object
        let location = try await locator.locate(commitHash)
        #expect(location != nil)
        
        if case .loose = location {
            // Good - found as loose object
        } else {
            Issue.record("Expected loose object")
        }
    }

    @Test func testRealRepositoryIntegration() async throws {
        // Point to your actual repo - update this path
        let repoPath = "/Users/vg/Documents/Dev/Odin"
        let repoURL = URL(fileURLWithPath: repoPath)
        
        guard FileManager.default.fileExists(atPath: repoURL.path) else {
            return // Skip if repo not found
        }
        
        let locator = ObjectLocator(
            repoURL: repoURL,
            packIndexManager: PackIndexManager(repoURL: repoURL)
        )
        
        let refReader = RefReader(
            repoURL: repoURL,
            objectExistsCheck: { hash in
                try await locator.exists(hash)
            },
            cache: ObjectCache()
        )
        
        // Get HEAD
        let head = try await refReader.getHEAD()
        #expect(head != nil)
        
        guard let head = head else { return }
        
        // Verify object exists
        let exists = try await locator.exists(head)
        #expect(exists)
        
        // Locate the object
        let location = try await locator.locate(head)
        #expect(location != nil)
        
        // Get all refs
        let refs = try await refReader.getRefs()
        #expect(refs.count > 0)
    }
}

// MARK: - Private helpers
private extension IntegrationTests {
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
    
    func writeLooseObject(commitContent: String, to repoURL: URL) throws -> String {
        let gitDir = repoURL.appendingPathComponent(GitPath.git.rawValue)
        let objectsDir = gitDir.appendingPathComponent(GitPath.objects.rawValue)
        
        let commitData = Data(commitContent.utf8)
        let header = "commit \(commitData.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(commitData)
        
        let hashString = fullContent.sha1()

        let prefix = String(hashString.prefix(2))
        let suffix = String(hashString.dropFirst(2))
        
        let prefixDir = objectsDir.appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        
        return hashString
    }
}
