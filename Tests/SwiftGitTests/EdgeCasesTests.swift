import Testing
import Foundation
@testable import SwiftGit

@Suite("Edge Cases Tests")
struct EdgeCasesTests {
    @Test func testEmptyRepository() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        
        let refs = try await refReader.getRefs()
        #expect(refs.count == 0)
        
        let head = try await refReader.getHEAD()
        #expect(head == nil)
        
        let locator = ObjectLocator(
            repoURL: tempDir,
            packIndexManager: PackIndexManager(repoURL: tempDir)
        )
        
        let fakeHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let location = try await locator.locate(fakeHash)
        #expect(location == nil)
    }

    @Test func testRepositoryWithOnlyPackedData() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(commitHash) refs/heads/main
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        
        let refs = try await refReader.getRefs().flatMap(\.value)
        #expect(refs.count == 1)
        #expect(refs.first?.name == "main")
        #expect(refs.first?.hash == commitHash)
        
        // HEAD resolution without objectExistsCheck
        let refReaderNoCheck = RefReader(
            repoURL: tempDir,
            objectExistsCheck: nil,
            cache: ObjectCache()
        )
        
        let head = try await refReaderNoCheck.getHEAD()
        #expect(head == commitHash)
    }

    @Test func testInvalidPackedRefsFormat() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        // Malformed packed-refs
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        invalid line without hash
        notahash refs/heads/main
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())

        // Should not crash, should skip invalid lines
        let refs = try await refReader.getRefs()
        #expect(refs.count == 0) // All lines were invalid
    }

    @Test func testInvalidHEADContent() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        // Invalid HEAD content
        try writeHEAD("this is not a valid ref or hash", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        
        let head = try await refReader.getHEAD()
        #expect(head == nil) // Should handle gracefully
    }
}

// MARK: - Private helpers
private extension EdgeCasesTests {
    func createTestRepo(in tempDir: URL) throws {
        let gitDir = tempDir.appendingPathComponent(GitPath.git.rawValue)
        let objectsDir = gitDir.appendingPathComponent(GitPath.objects.rawValue)
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
    }
    
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
