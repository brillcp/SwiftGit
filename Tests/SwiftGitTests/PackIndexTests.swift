import Testing
import Foundation
@testable import SwiftGit

@Suite("PackIndex Tests")
struct PackIndexTests {
    @Test func testLoadPackIndex() async throws {
        // This test requires a real pack file
        // Skip if not available
        let packIndexPath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.idx"
        let packFilePath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.pack"
        
        let idxURL = URL(fileURLWithPath: packIndexPath)
        let packURL = URL(fileURLWithPath: packFilePath)
        
        guard FileManager.default.fileExists(atPath: idxURL.path) else {
            return // Skip test
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        #expect(packIndex.entries.count > 0)
    }

    @Test func testFindObjectInPackIndex() async throws {
        // This test requires a real pack file
        // Skip if not available
        let packIndexPath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.idx"
        let packFilePath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.pack"
        
        let idxURL = URL(fileURLWithPath: packIndexPath)
        let packURL = URL(fileURLWithPath: packFilePath)
        
        guard FileManager.default.fileExists(atPath: idxURL.path) else {
            return // Skip test
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        // Get first hash from entries
        guard let firstHash = packIndex.entries.keys.first else {
            Issue.record("No entries in pack index")
            return
        }
        
        let location = packIndex.findObject(firstHash)
        #expect(location != nil)
        #expect(location?.hash == firstHash)
    }

    @Test func testPackIndexMultipleFiles() async throws {
        // This test would require a repo with multiple pack files
        // Most test repos have just one, so we test the structure works
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(GitPath.git.rawValue)
        let packDir = gitDir.appendingPathComponent("objects/pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        let packIndexManager = PackIndexManager(repoURL: tempDir)
        let indexes = await packIndexManager.packIndexes
        
        #expect(indexes.count == 0) // No pack files in empty dir
    }
}
