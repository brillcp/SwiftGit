import Testing
import Foundation
@testable import SwiftGit
import CryptoKit

@Suite("ObjectLocator Tests")
struct ObjectLocatorTests {
    
    func createTestRepo(in tempDir: URL) throws {
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
    }
    
    /// Write a loose object and return its actual hash
    func writeLooseObject(content: String, to repoURL: URL) throws -> String {
        let data = Data(content.utf8)
        
        // Compute the actual Git hash
        let header = "blob \(data.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(data)
        
        // Calculate SHA-1 hash
        let hash = Insecure.SHA1.hash(data: fullContent)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        // Write the compressed object
        let prefix = String(hashString.prefix(2))
        let suffix = String(hashString.dropFirst(2))
        
        let prefixDir = repoURL.appendingPathComponent(".git/objects/\(prefix)")
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        
        // Compress with zlib
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        
        return hashString
    }
    
    @Test func testObjectNotFound() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try createTestRepo(in: tempDir)
        
        let locator = ObjectLocator(
            gitURL: tempDir,
            packIndexManager: PackIndexManager(gitURL: tempDir)
        )

        let hash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let location = try await locator.locate(hash)
        
        #expect(location == nil, "Should not find non-existent object")
    }

    @Test func testLocateLooseObjectManualSetup() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        // Create .git structure
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        
        // Create a test object with proper Git format
        let content = "test content"
        let data = Data(content.utf8)
        
        // Compute Git hash
        let header = "blob \(data.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(data)
        
        let hash = Insecure.SHA1.hash(data: fullContent)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        print("🎯 Computed hash: \(hashString)")
        
        // Write the object file
        let prefix = String(hashString.prefix(2))
        let suffix = String(hashString.dropFirst(2))
        
        let prefixDir = objectsDir.appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        
        // Compress with zlib
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        
        print("📁 Wrote object to: \(objectFile.path)")
        print("📁 File exists: \(FileManager.default.fileExists(atPath: objectFile.path))")
        
        // Manually check the directory structure
        print("\n📂 Directory structure:")
        let objectsDirContents = try FileManager.default.contentsOfDirectory(at: objectsDir, includingPropertiesForKeys: nil)
        for item in objectsDirContents {
            print("  \(item.lastPathComponent)")
            if item.lastPathComponent == prefix {
                let subContents = try FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
                for subItem in subContents {
                    print("    → \(subItem.lastPathComponent)")
                }
            }
        }
        
        // Now create ObjectLocator with correct initializer
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        // Since scanLooseObjects isn't public, we need to call locate which should trigger scanning
        print("\n🔍 Locating object: \(hashString)")
        let location = try await locator.locate(hashString)
        
        print("📍 Result: \(String(describing: location))")
        
        #expect(location != nil, "Should find the loose object")
        
        if case .loose(let url) = location {
            print("✅ Found at: \(url.path)")
            #expect(url.lastPathComponent == suffix)
        } else {
            Issue.record("Expected loose object location, got: \(String(describing: location))")
        }
    }

    @Test func testVerifyTestSetup() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        
        // Create a test object
        let content = "test content"
        let data = Data(content.utf8)
        
        let header = "blob \(data.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(data)
        
        let hash = Insecure.SHA1.hash(data: fullContent)
        let hashString = hash.map { String(format: "%02x", $0) }.joined()
        
        print(String(repeating: "=", count: 60))
        print("TEST SETUP")
        print(String(repeating: "=", count: 60))
        print("🎯 Computed hash: \(hashString)")
        print("📁 Git dir: \(gitDir.path)")
        print("📁 Objects dir: \(objectsDir.path)")
        
        let prefix = String(hashString.prefix(2))
        let suffix = String(hashString.dropFirst(2))
        
        print("📂 Prefix: \(prefix)")
        print("📄 Suffix: \(suffix)")
        
        let prefixDir = objectsDir.appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        
        print("📝 Writing to: \(objectFile.path)")
        
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        
        print("✅ File written")
        print("📁 File exists: \(FileManager.default.fileExists(atPath: objectFile.path))")
        
        // Manually verify directory structure
        print("\n" + String(repeating: "=", count: 60))
        print("DIRECTORY STRUCTURE")
        print(String(repeating: "=", count: 60))
        
        let objectsContents = try FileManager.default.contentsOfDirectory(
            at: objectsDir,
            includingPropertiesForKeys: nil
        )
        
        print("📂 Contents of \(objectsDir.lastPathComponent):")
        for item in objectsContents {
            print("  📁 \(item.lastPathComponent)")
            
            // Check if it's a directory
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            
            if isDir.boolValue {
                let subContents = try FileManager.default.contentsOfDirectory(
                    at: item,
                    includingPropertiesForKeys: nil
                )
                for subItem in subContents {
                    let fullHash = item.lastPathComponent + subItem.lastPathComponent
                    print("    📄 \(subItem.lastPathComponent) (full hash: \(fullHash))")
                }
            }
        }
        
        // Now test ObjectLocator
        print("\n" + String(repeating: "=", count: 60))
        print("OBJECT LOCATOR")
        print(String(repeating: "=", count: 60))
        
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        print("🔍 Looking for hash: \(hashString)")
        let location = try await locator.locate(hashString)
        
        print("\n" + String(repeating: "=", count: 60))
        print("RESULT")
        print(String(repeating: "=", count: 60))
        print("📍 Location: \(String(describing: location))")
        
        #expect(location != nil, "Should find the object")
    }

    @Test func testResolveHEADFromPackedRefsOnly() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let refsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        
        print(String(repeating: "=", count: 60))
        print("TEST: Resolve HEAD from packed-refs (no loose refs)")
        print(String(repeating: "=", count: 60))
        
        let mainHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        let featureHash = "b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3"
        let refactorHash = "c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4"
        
        // Scenario: After git gc, refs are packed, NO loose ref files exist
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(mainHash) refs/heads/main
        \(featureHash) refs/heads/feature
        \(refactorHash) refs/heads/refactor
        """
        
        let packedRefsFile = gitDir.appendingPathComponent("packed-refs")
        try packedRefsContent.write(to: packedRefsFile, atomically: true, encoding: .utf8)
        print("✅ Created packed-refs")
        
        // HEAD points to main
        let headFile = gitDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main".write(to: headFile, atomically: true, encoding: .utf8)
        print("✅ Created HEAD pointing to refs/heads/main")
        
        // Verify NO loose ref files exist
        let looseMainFile = refsDir.appendingPathComponent("main")
        let looseMainExists = FileManager.default.fileExists(atPath: looseMainFile.path)
        print("📁 Loose refs/heads/main exists: \(looseMainExists)")
        #expect(looseMainExists == false, "Should NOT have loose ref file after git gc")
        
        // Create RefReader
        let refReader = RefReader(repoURL: tempDir)
        
        // Test 1: Get all refs
        print("\n🔍 Test 1: Getting all refs...")
        let refs = try await refReader.getRefs()
        print("📦 Found \(refs.count) refs:")
        for ref in refs {
            print("  - \(ref.name): \(ref.hash) (\(ref.type))")
        }
        
        #expect(refs.count == 3, "Should find 3 refs in packed-refs")
        #expect(refs.contains { $0.name == "main" && $0.hash == mainHash })
        #expect(refs.contains { $0.name == "feature" && $0.hash == featureHash })
        #expect(refs.contains { $0.name == "refactor" && $0.hash == refactorHash })
        
        // Test 2: Resolve HEAD
        print("\n🔍 Test 2: Resolving HEAD...")
        let head = try await refReader.getHEAD()
        print("🎯 HEAD resolved to: \(head ?? "nil")")
        
        #expect(head == mainHash, "HEAD should resolve to main's hash from packed-refs")
        
        // Test 3: Get branch name
        print("\n🔍 Test 3: Getting branch name...")
        let branch = try await refReader.getHEADBranch()
        print("🌿 Current branch: \(branch ?? "detached")")
        
        #expect(branch == "main", "Should be on main branch")
        
        print("\n✅ All tests passed!")
    }

    @Test func testLocateObjectInPackFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        let packDir = objectsDir.appendingPathComponent("pack")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        
        print(String(repeating: "=", count: 60))
        print("TEST: Locate object in pack file")
        print(String(repeating: "=", count: 60))
        
        // For now, this test will be incomplete because creating real pack files is complex
        // But we can test that the ObjectLocator correctly handles empty pack directories
        
        let commitHash = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2"
        
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        print("🔍 Looking for hash in pack: \(commitHash)")
        let location = try await locator.locate(commitHash)
        
        print("📍 Result: \(String(describing: location))")
        
        // Since we have no pack files, this should be nil
        #expect(location == nil, "Should not find object when no pack files exist")
        
        print("✅ Test passed - correctly returns nil for non-existent object")
    }

    @Test func testFullScenarioAfterGitGC() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        let refsDir = gitDir.appendingPathComponent("refs/heads")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        
        print(String(repeating: "=", count: 60))
        print("TEST: Full scenario after git gc")
        print(String(repeating: "=", count: 60))
        
        // Scenario: You have unpushed commits on main, then run git gc
        // Result: refs are packed, objects are packed (but we'll use loose for testing)
        
        // 1. Setup packed-refs
        let commitContent = """
        tree b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3
        parent c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4
        author Test User <test@example.com> 1234567890 +0000
        committer Test User <test@example.com> 1234567890 +0000
        
        Test commit message
        """
        
        let commitData = Data(commitContent.utf8)
        let header = "commit \(commitData.count)\0"
        var fullContent = Data(header.utf8)
        fullContent.append(commitData)
        
        // Compute the actual hash
        let actualHash = Insecure.SHA1.hash(data: fullContent)
        let mainHash = actualHash.map { String(format: "%02x", $0) }.joined()
        
        print("🎯 Commit hash: \(mainHash)")
        
        let packedRefsContent = """
        # pack-refs with: peeled fully-peeled sorted
        \(mainHash) refs/heads/main
        """
        let packedRefsFile = gitDir.appendingPathComponent("packed-refs")
        try packedRefsContent.write(to: packedRefsFile, atomically: true, encoding: .utf8)
        print("✅ Created packed-refs")
        
        // 2. Setup HEAD
        let headFile = gitDir.appendingPathComponent("HEAD")
        try "ref: refs/heads/main".write(to: headFile, atomically: true, encoding: .utf8)
        print("✅ Created HEAD")
        
        // 3. Create the commit object as loose
        let prefix = String(mainHash.prefix(2))
        let suffix = String(mainHash.dropFirst(2))
        let prefixDir = objectsDir.appendingPathComponent(prefix)
        try FileManager.default.createDirectory(at: prefixDir, withIntermediateDirectories: true)
        
        let objectFile = prefixDir.appendingPathComponent(suffix)
        let compressed = try (fullContent as NSData).compressed(using: .zlib) as Data
        try compressed.write(to: objectFile)
        print("✅ Created commit object: \(mainHash)")
        
        // Now simulate the workflow
        print("\n" + String(repeating: "-", count: 60))
        print("SIMULATING WORKFLOW")
        print(String(repeating: "-", count: 60))
        
        // Create RefReader
        let refReader = RefReader(
            repoURL: tempDir,
            objectExistsCheck: { hash in
                let locator = ObjectLocator(
                    gitURL: gitDir,
                    packIndexManager: PackIndexManager(gitURL: gitDir)
                )
                return try await locator.exists(hash)
            }
        )
        
        // Step 1: Get HEAD
        print("\n1️⃣ Getting HEAD...")
        let head = try await refReader.getHEAD()
        print("   Result: \(head ?? "nil")")
        
        #expect(head == mainHash, "Should resolve HEAD to commit hash")
        
        // Step 2: Verify object exists
        print("\n2️⃣ Checking if commit object exists...")
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        let exists = try await locator.exists(mainHash)
        print("   Result: \(exists)")
        
        #expect(exists, "Commit object should exist")
        
        // Step 3: Locate the object
        print("\n3️⃣ Locating commit object...")
        let location = try await locator.locate(mainHash)
        print("   Result: \(String(describing: location))")
        
        #expect(location != nil, "Should locate the commit object")
        
        if case .loose(let url) = location {
            print("✅ Found as loose object at: \(url.path)")
        }
        
        print("\n✅ Full workflow successful!")
    }

    @Test func testObjectLocatorWithExistingRepo() async throws {
        // If you have a test repo path, you can use it here
        // For now, let's create a minimal one
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let gitDir = tempDir.appendingPathComponent(".git")
        let objectsDir = gitDir.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: objectsDir, withIntermediateDirectories: true)
        
        // Create several test objects
        var createdHashes: [String] = []
        
        for i in 1...5 {
            let content = "test content \(i)"
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
            
            createdHashes.append(hashString)
            print("✅ Created object \(i): \(hashString)")
        }
        
        // Create ObjectLocator
        let locator = ObjectLocator(
            gitURL: gitDir,
            packIndexManager: PackIndexManager(gitURL: gitDir)
        )
        
        // Try to find each object
        print("\n🔍 Testing object location:")
        for (i, hash) in createdHashes.enumerated() {
            let location = try await locator.locate(hash)
            
            if location != nil {
                print("  ✅ Object \(i+1) found: \(hash)")
            } else {
                print("  ❌ Object \(i+1) NOT FOUND: \(hash)")
            }
            
            #expect(location != nil, "Should find object \(i+1)")
        }
        
        // Also test that non-existent object returns nil
        let fakeHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
        let fakeLocation = try await locator.locate(fakeHash)
        #expect(fakeLocation == nil, "Should not find fake object")
    }
}
