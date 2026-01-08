import Testing
import Foundation
@testable import SwiftGit

@Suite("PackIndex Tests")
struct PackIndexTests {
//    @Test func testLoadPackIndex() async throws {
//        // This test requires a real pack file
//        // Skip if not available
//        let packIndexPath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.idx"
//        let packFilePath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.pack"
//        
//        let idxURL = URL(fileURLWithPath: packIndexPath)
//        let packURL = URL(fileURLWithPath: packFilePath)
//        
//        guard FileManager.default.fileExists(atPath: idxURL.path) else {
//            return // Skip test
//        }
//        
//        let packIndex = PackIndex()
//        try packIndex.load(idxURL: idxURL, packURL: packURL)
//        
//        #expect(packIndex.entries.count > 0)
//    }

//    @Test func testFindObjectInPackIndex() async throws {
//        // This test requires a real pack file
//        // Skip if not available
//        let packIndexPath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.idx"
//        let packFilePath = "/Users/vg/Documents/Dev/Odin/.git/objects/pack/pack-*.pack"
//        
//        let idxURL = URL(fileURLWithPath: packIndexPath)
//        let packURL = URL(fileURLWithPath: packFilePath)
//        
//        guard FileManager.default.fileExists(atPath: idxURL.path) else {
//            return // Skip test
//        }
//        
//        let packIndex = PackIndex()
//        try packIndex.load(idxURL: idxURL, packURL: packURL)
//        
//        // Get first hash from entries
//        guard let firstHash = packIndex.entries.keys.first else {
//            Issue.record("No entries in pack index")
//            return
//        }
//        
//        let location = packIndex.findObject(firstHash)
//        #expect(location != nil)
//        #expect(location?.hash == firstHash)
//    }

    @Test func testPackIndexMultipleFiles() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        
        let packIndexManager = PackIndexManager(repoURL: repoURL)
        let indexes = await packIndexManager.packIndexes
        
        #expect(indexes.count == 0) // No pack files in empty dir
    }
}
