import Testing
import Foundation
@testable import SwiftGit

@Suite("RefReader Tests")
struct RefReaderTests {
    @Test func testReadLooseRefs() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let mainHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let devHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        try writeRef(name: "main", hash: mainHash, to: tempDir)
        try writeRef(name: "develop", hash: devHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let refs = try await refReader.getRefs().flatMap(\.value)
        
        // Normalize names in case RefReader yields full ref paths like "refs/heads/main"
        func normalizedName(_ name: String) -> String {
            if name.hasPrefix("refs/heads/") {
                return String(name.dropFirst("refs/heads/".count))
            }
            return name
        }
        
        #expect(refs.contains { normalizedName($0.name) == "main" && $0.hash == mainHash && $0.type == .localBranch })
        #expect(refs.contains { normalizedName($0.name) == "develop" && $0.hash == devHash && $0.type == .localBranch })
    }

    @Test func testReadPackedRefs() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let mainHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let featureHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(mainHash) refs/heads/main
        \(featureHash) refs/heads/feature
        """
        
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let refs = try await refReader.getRefs().flatMap(\.value)
        
        #expect(refs.count == 2)
        #expect(refs.contains { $0.name == "main" && $0.hash == mainHash && $0.type == .localBranch })
        #expect(refs.contains { $0.name == "feature" && $0.hash == featureHash && $0.type == .localBranch })
    }

    @Test func testReadPackedRefsWithPeeledTags() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let annotatedHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let peeledHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(annotatedHash) refs/tags/v1.0.0
        ^\(peeledHash)
        """
        
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let refs = try await refReader.getRefs().flatMap(\.value)

        #expect(refs.count == 1)
        #expect(refs.first?.name == "v1.0.0")
        #expect(refs.first?.type == .tag)
        #expect(refs.first?.hash == peeledHash)
    }

    @Test func testLooseRefOverridesPackedRef() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let packedHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let looseHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(packedHash) refs/heads/main
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        try writeRef(name: "main", hash: looseHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        
        let head = try await refReader.getHEAD()
        
        #expect(head == looseHash)
    }

    @Test func testResolveHEADToLooseRef() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeRef(name: "main", hash: commitHash, to: tempDir)
        try writeHEAD("ref: refs/heads/main", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
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
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let head = try await refReader.getHEAD()
        
        #expect(head == commitHash)
    }

    @Test func testResolveHEADDetached() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeHEAD(commitHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let head = try await refReader.getHEAD()
        
        #expect(head == commitHash)
    }

    @Test func testResolveHEADToRemoteRef() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(commitHash) refs/remotes/origin/main
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        try writeHEAD("ref: refs/remotes/origin/main", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let head = try await refReader.getHEAD()
        
        #expect(head == commitHash)
    }

    @Test func testGetHEADBranchLocal() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        try writeHEAD("ref: refs/heads/develop", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let branch = try await refReader.getHEADBranch()
        
        #expect(branch == "develop")
    }

    @Test func testGetHEADBranchDetached() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        try writeHEAD(commitHash, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let branch = try await refReader.getHEADBranch()
        
        #expect(branch == nil)
    }

    @Test func testGetHEADBranchRemote() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        try writeHEAD("ref: refs/remotes/origin/main", to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let branch = try await refReader.getHEADBranch()
        
        #expect(branch == nil)
    }

    @Test func testNestedRefPaths() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let featureHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let refactorHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(featureHash) refs/heads/feature/ios-234
        \(refactorHash) refs/heads/refactor/big-changes
        """
        try writePackedRefs(packedRefsContent, to: tempDir)
        
        let refReader = RefReader(repoURL: tempDir, cache: ObjectCache())
        let refs = try await refReader.getRefs().flatMap(\.value)

        #expect(refs.count == 2)
        #expect(refs.contains { $0.name == "feature/ios-234" && $0.hash == featureHash })
        #expect(refs.contains { $0.name == "refactor/big-changes" && $0.hash == refactorHash })
    }
}

// MARK: - Private helpers
private extension RefReaderTests {
    func createTestRepo(in tempDir: URL) throws {
        let gitDir = tempDir.appendingPathComponent(GitPath.git.rawValue)
        let refsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
    }
    
    func writeRef(name: String, hash: String, to repoURL: URL) throws {
        let refFile = repoURL.appendingPathComponent(".git/refs/heads/\(name)")
        try hash.write(to: refFile, atomically: true, encoding: .utf8)
    }
    
    func writePackedRefs(_ content: String, to repoURL: URL) throws {
        let packedFile = repoURL.appendingPathComponent(".git/packed-refs")
        try content.write(to: packedFile, atomically: true, encoding: .utf8)
    }
    
    func writeHEAD(_ content: String, to repoURL: URL) throws {
        let headFile = repoURL.appendingPathComponent(".git/HEAD")
        try content.write(to: headFile, atomically: true, encoding: .utf8)
    }
}

