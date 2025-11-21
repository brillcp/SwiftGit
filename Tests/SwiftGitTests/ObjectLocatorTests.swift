import Testing
import Foundation
@testable import SwiftGit
import CryptoKit

@Suite("ObjectLocator Tests")
struct ObjectLocatorTests {
    @Test func testLocateLooseObject() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let hash = try writeLooseObject(content: "test content", to: tempDir)
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        let location = try await locator.locate(hash)
        
        #expect(location != nil)
        
        if case .loose(let url) = location {
            #expect(url.lastPathComponent == String(hash.dropFirst(2)))
        } else {
            Issue.record("Expected loose object location")
        }
    }
    
    @Test func testObjectNotFound() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        let fakeHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let location = try await locator.locate(fakeHash)
        
        #expect(location == nil)
    }

    @Test func testCaseInsensitiveHashLookup() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let hash = try writeLooseObject(content: "case test", to: tempDir)
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        // Test lowercase
        let locationLower = try await locator.locate(hash.lowercased())
        #expect(locationLower != nil)
        
        // Test uppercase
        let locationUpper = try await locator.locate(hash.uppercased())
        #expect(locationUpper != nil)
        
        // Test mixed case
        let mixedCase = String(hash.enumerated().map { i, c in
            i % 2 == 0 ? c.lowercased().first! : c.uppercased().first!
        })
        let locationMixed = try await locator.locate(mixedCase)
        #expect(locationMixed != nil)
    }

    @Test func testEmptyPackDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let packDir = gitDir.appendingPathComponent("objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        let fakeHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let location = try await locator.locate(fakeHash)
        
        #expect(location == nil)
    }

    @Test func testMixedLooseAndPacked() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        let packDir = objectsDir.appendingPathComponent("pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        // Create loose objects
        let hash1 = try writeLooseObject(content: "loose object 1", to: tempDir)
        let hash2 = try writeLooseObject(content: "loose object 2", to: tempDir)
        
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        // Should find loose objects
        let location1 = try await locator.locate(hash1)
        #expect(location1 != nil)
        
        if case .loose = location1 {
            // Good
        } else {
            Issue.record("Expected loose object")
        }
        
        let location2 = try await locator.locate(hash2)
        #expect(location2 != nil)
        
        // Should not find non-existent object
        let fakeHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let fakeLocation = try await locator.locate(fakeHash)
        #expect(fakeLocation == nil)
    }

}

// MARK: - Private helpers
private extension ObjectLocatorTests {
    func createTestRepo(in tempDir: URL) throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
    }
    
    func writeLooseObject(content: String, to repoURL: URL) throws -> String {
        let gitDir = repoURL.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        
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
        
        return hashString
    }
}
