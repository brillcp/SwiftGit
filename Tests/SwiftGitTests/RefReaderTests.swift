import Testing
import Foundation
@testable import SwiftGit

@Suite("RefReader Tests")
struct RefReaderTests {
    
    // MARK: - Test Fixtures
    
    /// Create a minimal test repo structure
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
    
    func writeRef(name: String, hash: String, to repoURL: URL) throws {
        let refFile = repoURL.appendingPathComponent(".git/refs/heads/\(name)")
        try hash.write(to: refFile, atomically: true, encoding: .utf8)
    }
    
    func writePackedRefs(_ content: String, to repoURL: URL) throws {
        let packedFile = repoURL.appendingPathComponent(".git/packed-refs")
        try content.write(to: packedFile, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Loose Ref Tests
    
    @Test func testReadLooseRef() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let testHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeRef(name: "main", hash: testHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let refs = try await refReader.getRefs()
        
        #expect(refs.count == 1)
        #expect(refs.first?.name == "main")
        #expect(refs.first?.hash == testHash)
        #expect(refs.first?.type == .localBranch)
    }
    
    @Test func testReadMultipleLooseRefs() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let mainHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let devHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        try writeRef(name: "main", hash: mainHash, to: tempDir)
        try writeRef(name: "develop", hash: devHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let refs = try await refReader.getRefs()
        
        #expect(refs.count == 2)
        #expect(refs.contains { $0.name == "main" && $0.hash == mainHash })
        #expect(refs.contains { $0.name == "develop" && $0.hash == devHash })
    }
    
    // MARK: - Packed Refs Tests
    
    @Test func testReadPackedRefs() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2 refs/heads/main
        b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3 refs/heads/feature
        c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4 refs/remotes/origin/main
        """
        
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let refs = try await refReader.getRefs()
        
        #expect(refs.count == 3)
        #expect(refs.contains { $0.name == "main" && $0.type == .localBranch })
        #expect(refs.contains { $0.name == "feature" && $0.type == .localBranch })
        #expect(refs.contains { $0.name == "origin/main" && $0.type == .remoteBranch })
    }
    
    @Test func testPackedRefsWithPeeledTags() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2 refs/tags/v1.0.0
        ^b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3
        """
        
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let refs = try await refReader.getRefs()
        
        #expect(refs.count == 1)
        #expect(refs.first?.name == "v1.0.0")
        #expect(refs.first?.type == .tag)
        // Peeled hash should replace annotated tag hash
        #expect(refs.first?.hash == "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3")
    }
    
    // MARK: - HEAD Resolution Tests
    
    @Test func testResolveHEADToLooseRef() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeRef(name: "main", hash: commitHash, to: tempDir)
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let head = try await refReader.getHEAD()
        
        #expect(head == commitHash)
    }
    
    @Test func testResolveHEADToPackedRef() async throws {
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
        
        let refReader = RefReader(repoURL: tempDir)
        let head = try await refReader.getHEAD()
        
        #expect(head == commitHash)
    }
    
    @Test func testDetachedHEAD() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeHEAD(commitHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let head = try await refReader.getHEAD()
        
        #expect(head == commitHash)
    }
    
    @Test func testLooseRefOverridesPackedRef() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let packedHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let looseHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        // Packed ref with old hash
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(packedHash) refs/heads/main
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        // Loose ref with newer hash (should win)
        try writeRef(name: "main", hash: looseHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let refs = try await refReader.getRefs()
        
        // Should have both entries initially
        #expect(refs.count == 2)
        
        // But when resolving, loose should win
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        let head = try await refReader.getHEAD()
        #expect(head == looseHash)
    }
    
    // MARK: - Branch Name Tests
    
    @Test func testGetHEADBranch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        try writeHEAD("ref: refs/heads/develop", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let branch = try await refReader.getHEADBranch()
        
        #expect(branch == "develop")
    }
    
    @Test func testGetHEADBranchDetached() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        try writeHEAD("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        let branch = try await refReader.getHEADBranch()
        
        #expect(branch == nil)
    }
    
    // MARK: - Cache Tests
    
    @Test func testRefCaching() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeRef(name: "main", hash: commitHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir)
        
        // First call - should read from disk
        let refs1 = try await refReader.getRefs()
        #expect(refs1.count == 1)
        
        // Add another ref
        let newHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        try writeRef(name: "feature", hash: newHash, to: tempDir)
        
        // Second call within cache timeout - should return cached (old) data
        let refs2 = try await refReader.getRefs()
        #expect(refs2.count == 1) // Still cached
        
        // Wait for cache to expire
        try await Task.sleep(for: .seconds(1.1))
        
        // Third call - cache expired, should read new data
        let refs3 = try await refReader.getRefs()
        #expect(refs3.count == 2) // Now sees both refs
    }
}
