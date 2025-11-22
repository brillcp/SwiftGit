import Testing
import Foundation
@testable import SwiftGit

@Suite("PackFileReader Tests")
struct PackFileReaderTests {

    // MARK: - Memory Tests
    @Test func testNoFullPackMapping() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let attrs = try FileManager.default.attributesOfItem(atPath: packURL.path)
        let packSize = attrs[.size] as? UInt64 ?? 0
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        let memBefore = Int64(getMemoryUsage())
        
        // Read objects WITHOUT calling getAllHashes() - use lazy loading
        var objectsRead = 0
        let testPrefixes = ["00", "01", "ab", "cd", "ef", "ff"]
        
        for prefix in testPrefixes {
            // Trigger lazy load of this prefix range
            let fakeHash = prefix + String(repeating: "0", count: 38)
            _ = packIndex.findObject(fakeHash)
            
            // Read actual objects from loaded range
            for (_, location) in packIndex.entries.prefix(3) {
                _ = try? await reader.parseObject(at: location, packIndex: packIndex)
                objectsRead += 1
                if objectsRead >= 10 { break }
            }
            if objectsRead >= 10 { break }
        }
        
        let memAfter = Int64(getMemoryUsage())
        let memUsed = max(0, memAfter - memBefore)
        
        // Should use much less than pack size
        // Allow 50MB or 20% of pack size, whichever is larger (for decompression overhead)
        let maxAllowed = max(50_000_000, packSize / 5)
        
        #expect(
            UInt64(memUsed) < maxAllowed,
            "Using \(memUsed) bytes vs pack size \(packSize) bytes (max allowed: \(maxAllowed))"
        )
        
        await reader.unmap()
    }

    @Test func testMultiplePackFilesNoMemoryLeak() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard packFiles.count >= 2 else {
            return // Need multiple pack files
        }
        
        let reader = PackFileReader()
        let memBefore = Int64(getMemoryUsage())

        // Read objects from multiple pack files
        for (idxURL, packURL) in packFiles.prefix(3) {
            let packIndex = PackIndex()
            try packIndex.load(idxURL: idxURL, packURL: packURL)
            
            let hashes = Array(packIndex.getAllHashes().prefix(5))
            
            for hash in hashes {
                guard let location = packIndex.findObject(hash) else { continue }
                _ = try await reader.parseObject(at: location, packIndex: packIndex)
            }
        }
        
        let memAfter = Int64(getMemoryUsage())
        let memUsed = max(0, memAfter - memBefore)

        // Should use less than 20MB even with multiple pack files
        #expect(memUsed < 20_000_000, "Memory usage: \(memUsed) bytes")
        
        await reader.unmap()
    }
    
    @Test func testUnmapClosesHandles() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        
        // Read some objects (opens file handles)
        let hashes = Array(packIndex.getAllHashes().prefix(5))
        for hash in hashes {
            guard let location = packIndex.findObject(hash) else { continue }
            _ = try await reader.parseObject(at: location, packIndex: packIndex)
        }
        
        #expect(await reader.isMapped == true)
        
        // Unmap should close handles
        await reader.unmap()
        
        #expect(await reader.isMapped == false)
    }
    
    // MARK: - Correctness Tests
    
    @Test func testObjectParsing() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        
        // Parse various object types
        let hashes = Array(packIndex.getAllHashes().prefix(50))
        
        var foundCommit = false
        var foundTree = false
        var foundBlob = false
        var successCount = 0
        
        for hash in hashes {
            guard let location = packIndex.findObject(hash) else { continue }
            
            do {
                let parsed = try await reader.parseObject(at: location, packIndex: packIndex)
                successCount += 1
                
                switch parsed {
                case .commit(let commit):
                    #expect(!commit.id.isEmpty)
                    #expect(!commit.tree.isEmpty)
                    #expect(commit.tree.count == 40)
                    foundCommit = true
                    
                case .tree(let tree):
                    #expect(tree.entries.count > 0)
                    let firstEntry = tree.entries[0]
                    #expect(!firstEntry.name.isEmpty)
                    #expect(!firstEntry.hash.isEmpty)
                    #expect(firstEntry.hash.count == 40)
                    foundTree = true
                    
                case .blob(let blob):
                    #expect(blob.data.count > 0)
                    #expect(!blob.id.isEmpty)
                    foundBlob = true
                case .tag:
                    ()
                }
                
            } catch {
                continue
            }
        }
        
        await reader.unmap()
        
        // Should successfully parse at least some objects
        #expect(successCount > 0, "Failed to parse any objects")
        
        // Should find at least one type
        #expect(foundCommit || foundTree || foundBlob, "No valid objects found")
    }

    @Test func testTreeObjectParsing() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        
        let hashes = packIndex.getAllHashes()
        
        for hash in hashes.prefix(50) {
            guard let location = packIndex.findObject(hash) else { continue }
            
            let parsed = try await reader.parseObject(at: location, packIndex: packIndex)
            
            if case .tree(let tree) = parsed {
                // Verify tree has entries
                #expect(tree.entries.count > 0)
                
                // Verify first entry has valid fields
                let firstEntry = tree.entries[0]
                #expect(!firstEntry.name.isEmpty)
                #expect(!firstEntry.hash.isEmpty)
                #expect(firstEntry.hash.count == 40)
                
                await reader.unmap()
                return // Test passed
            }
        }
        
        Issue.record("No tree objects found in pack file")
    }
    
    @Test func testBlobObjectParsing() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        
        let hashes = packIndex.getAllHashes()
        
        for hash in hashes.prefix(50) {
            guard let location = packIndex.findObject(hash) else { continue }
            
            let parsed = try await reader.parseObject(at: location, packIndex: packIndex)
            
            if case .blob(let blob) = parsed {
                // Verify blob has data
                #expect(blob.data.count > 0)
                #expect(!blob.id.isEmpty)
                
                await reader.unmap()
                return // Test passed
            }
        }
        
        Issue.record("No blob objects found in pack file")
    }
    
    @Test func testDeltaObjectResolution() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        
        // Try to read all objects (including deltas)
        let hashes = Array(packIndex.getAllHashes().prefix(100))
        var successCount = 0
        
        for hash in hashes {
            guard let location = packIndex.findObject(hash) else { continue }
            
            do {
                _ = try await reader.parseObject(at: location, packIndex: packIndex)
                successCount += 1
            } catch {
                // Some failures are OK (unsupported types, etc)
                continue
            }
        }
        
        // Should successfully parse most objects
        #expect(successCount > hashes.count / 2)
        
        await reader.unmap()
    }
    
    // MARK: - Performance Tests
    
    @Test func testReadPerformance() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            return
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        
        let hashes = Array(packIndex.getAllHashes().prefix(100))
        
        let startTime = Date()
        
        for hash in hashes {
            guard let location = packIndex.findObject(hash) else { continue }
            _ = try? await reader.parseObject(at: location, packIndex: packIndex)
        }
        
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should read 100 objects in less than 1 second
        #expect(elapsed < 1.0, "Took \(elapsed) seconds")
        
        await reader.unmap()
    }
    
    @Test func testLargePackFile() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let packFiles = try getPackFiles(in: repoURL)
        
        // Find largest pack file
        var largestPack: (idxURL: URL, packURL: URL, size: UInt64)?
        
        for packFile in packFiles {
            let attrs = try FileManager.default.attributesOfItem(atPath: packFile.packURL.path)
            let size = attrs[.size] as? UInt64 ?? 0
            
            if largestPack == nil || size > largestPack!.size {
                largestPack = (packFile.idxURL, packFile.packURL, size)
            }
        }
        
        guard let (idxURL, packURL, size) = largestPack, size > 10_000_000 else {
            return // Skip if no large pack files
        }
        
        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)
        
        let reader = PackFileReader()
        let memBefore = getMemoryUsage()
        
        // Read from large pack file
        let hashes = Array(packIndex.getAllHashes().prefix(50))
        
        for hash in hashes {
            guard let location = packIndex.findObject(hash) else { continue }
            _ = try? await reader.parseObject(at: location, packIndex: packIndex)
        }
        
        let memAfter = getMemoryUsage()
        let memUsed = memAfter - memBefore
        
        // Even with large pack file, should use minimal memory
        // Should NOT map entire file into memory
        let maxExpectedMemory = min(size / 10, 50_000_000) // Max 50MB or 10% of file
        
        #expect(memUsed < maxExpectedMemory, "Used \(memUsed) bytes for \(size) byte pack file")
        
        await reader.unmap()
    }
}

// MARK: - Private helpers
private extension PackFileReaderTests {
    func getTestRepoURL() -> URL? {
        // Point to a real test repo with pack files
        let testRepoPath = "/Users/vg/Documents/Dev/quartr-ios"
        let url = URL(fileURLWithPath: testRepoPath)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        return url
    }
    
    func getPackFiles(in repoURL: URL) throws -> [(idxURL: URL, packURL: URL)] {
        let packDir = repoURL
            .appendingPathComponent(".git/objects/pack")
        
        let files = try FileManager.default.contentsOfDirectory(
            at: packDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        
        let idxFiles = files.filter { $0.pathExtension == "idx" }
        
        return idxFiles.compactMap { idxURL in
            let packURL = idxURL
                .deletingPathExtension()
                .appendingPathExtension("pack")
            
            guard FileManager.default.fileExists(atPath: packURL.path) else {
                return nil
            }
            
            return (idxURL, packURL)
        }
    }
    
    func getMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? info.resident_size : 0
    }
}
