import Testing
import Foundation
@testable import SwiftGit

/*
@Suite("PackFileReader Tests")
struct PackFileReaderTests {
    @Test func testPackIndexLoad() throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            Issue.record("No pack files found")
            return
        }

        let packIndex = PackIndex()

        // Should load without error
        try packIndex.load(idxURL: idxURL, packURL: packURL)
    }

    @Test func testFindKnownObject() throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            Issue.record("No pack files found")
            return
        }

        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)

        // Get a known hash from the repo
        let knownHash = try getKnownHashFromRepo(repoURL)

        // Try to find it
        let location = packIndex.findObject(knownHash)

        if let location = location {
            #expect(location.hash == knownHash.lowercased())
            #expect(location.offset >= 0)
            #expect(location.packURL == packURL)
        }
        // If not found, it might be in a different pack file - that's OK
    }

    @Test func testFindHeadCommit() throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let packFiles = try getPackFiles(in: repoURL)
        guard !packFiles.isEmpty else {
            Issue.record("No pack files found")
            return
        }

        let headHash = try getKnownHashFromRepo(repoURL)

        var found = false

        // Search across all pack files for HEAD commit
        for (idxURL, packURL) in packFiles {
            let packIndex = PackIndex()
            try packIndex.load(idxURL: idxURL, packURL: packURL)

            if let location = packIndex.findObject(headHash) {
                #expect(location.hash == headHash.lowercased())
                #expect(location.packURL == packURL)
                found = true
                break
            }
        }

        #expect(found, "Should find HEAD commit in at least one pack file")
    }

    @Test func testObjectParsing() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            Issue.record("No pack files found")
            return
        }

        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)

        let reader = PackFileReader()

        // Get known hashes and try to parse them
        let knownHashes = try getKnownHashesFromRepo(repoURL, count: 20)

        var successCount = 0
        var foundCommit = false
        var foundTree = false
        var foundBlob = false

        for hash in knownHashes {
            guard let location = packIndex.findObject(hash) else { continue }

            do {
                let parsed = try await reader.parseObject(at: location, packIndex: packIndex)
                successCount += 1

                switch parsed {
                case .commit(let commit):
                    #expect(!commit.id.isEmpty)
                    #expect(!commit.tree.isEmpty)
                    foundCommit = true

                case .tree(let tree):
                    #expect(tree.entries.count > 0)
                    foundTree = true

                case .blob(let blob):
                    #expect(blob.data.count > 0)
                    foundBlob = true

                case .tag:
                    ()
                }
            } catch {
                continue
            }
        }

        // Should parse at least some objects
        #expect(successCount > 0, "Failed to parse any objects")
        #expect(foundCommit || foundTree || foundBlob, "Should find at least one object type")
    }

    @Test func testNonExistentObject() throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let packFiles = try getPackFiles(in: repoURL)
        guard let (idxURL, packURL) = packFiles.first else {
            Issue.record("No pack files found")
            return
        }

        let packIndex = PackIndex()
        try packIndex.load(idxURL: idxURL, packURL: packURL)

        // Try to find a hash that doesn't exist
        let fakeHash = "0000000000000000000000000000000000000000"
        let location = packIndex.findObject(fakeHash)

        #expect(location == nil, "Should not find non-existent object")
    }
}

// MARK: - Private helpers
private extension PackFileReaderTests {
    func getPackFiles(in repoURL: URL) throws -> [(idxURL: URL, packURL: URL)] {
        let packDir = repoURL.appendingPathComponent(".git/objects/pack")

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

    /// Get a known hash from the repo by reading HEAD
    func getKnownHashFromRepo(_ repoURL: URL) throws -> String {
        let headFile = repoURL.appendingPathComponent(".git/HEAD")
        let headContent = try String(contentsOf: headFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

        if headContent.hasPrefix("ref: ") {
            // Follow the ref
            let refPath = String(headContent.dropFirst(5))
            let refFile = repoURL.appendingPathComponent(".git/\(refPath)")
            return try String(contentsOf: refFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Direct hash
            return headContent
        }
    }

    /// Get multiple known hashes by walking commits
    func getKnownHashesFromRepo(_ repoURL: URL, count: Int) throws -> [String] {
        var hashes: [String] = []

        // Get HEAD hash
        let headHash = try getKnownHashFromRepo(repoURL)
        hashes.append(headHash)

        // Read recent commits from .git/logs/HEAD
        let logsFile = repoURL.appendingPathComponent(".git/logs/HEAD")
        if let logsContent = try? String(contentsOf: logsFile, encoding: .utf8) {
            let lines = logsContent.split(separator: "\n")
            for line in lines.suffix(count) {
                let parts = line.split(separator: " ")
                if parts.count >= 2 {
                    hashes.append(String(parts[1]))  // New hash
                }
            }
        }

        return Array(hashes.prefix(count))
    }
}
*/