import Testing
import Foundation
@testable import SwiftGit

@Suite("Hunk Staging Tests")
struct HunkStagingTests {
    @Test func testGeneratePatchForAddedLines() async throws {
        let generator = PatchGenerator()
        
        // Create a hunk with added lines
        let hunk = DiffHunk(
            id: 0,
            header: "@@ -1,2 +1,4 @@",
            lines: [
                DiffLine(
                    id: 0,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 1", isHighlighted: false)]
                ),
                DiffLine(
                    id: 1,
                    type: .added,
                    segments: [Segment(id: 0, text: "New line A", isHighlighted: false)]
                ),
                DiffLine(
                    id: 2,
                    type: .added,
                    segments: [Segment(id: 0, text: "New line B", isHighlighted: false)]
                ),
                DiffLine(
                    id: 3,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 2", isHighlighted: false)]
                )
            ]
        )
        
        let file = WorkingTreeFile(
            path: "Hello.swift",
            staged: nil,
            unstaged: .modified
        )
        
        let patch = generator.generatePatch(hunk: hunk, file: file)
        
        print("\n=== GENERATED PATCH ===")
        print(patch)
        print("=== END PATCH ===")
        
        // Verify patch structure
        #expect(patch.contains("diff --git a/Hello.swift b/Hello.swift"))
        #expect(patch.contains("--- a/Hello.swift"))
        #expect(patch.contains("+++ b/Hello.swift"))
        #expect(patch.contains("@@ -1,2 +1,4 @@"))
        #expect(patch.contains(" Line 1"))
        #expect(patch.contains("+New line A"))
        #expect(patch.contains("+New line B"))
        #expect(patch.contains(" Line 2"))
    }
    
    @Test func testGenerateReversePatch() async throws {
        let generator = PatchGenerator()
        
        let hunk = DiffHunk(
            id: 0,
            header: "@@ -1,2 +1,4 @@",
            lines: [
                DiffLine(
                    id: 0,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 1", isHighlighted: false)]
                ),
                DiffLine(
                    id: 1,
                    type: .added,
                    segments: [Segment(id: 0, text: "New line A", isHighlighted: false)]
                ),
                DiffLine(
                    id: 2,
                    type: .added,
                    segments: [Segment(id: 0, text: "New line B", isHighlighted: false)]
                ),
                DiffLine(
                    id: 3,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 2", isHighlighted: false)]
                )
            ]
        )
        
        let file = WorkingTreeFile(
            path: "Hello.swift",
            staged: nil,
            unstaged: .modified
        )
        
        let patch = generator.generateReversePatch(hunk: hunk, file: file)
        
        print("\n=== REVERSE PATCH ===")
        print(patch)
        print("=== END PATCH ===")
        
        // Verify reverse patch has swapped header
        #expect(patch.contains("@@ -1,4 +1,2 @@"), "Header should be reversed")
        #expect(patch.contains(" Line 1"), "Unchanged lines preserved")
        #expect(patch.contains("-New line A"), "Added becomes removed")
        #expect(patch.contains("-New line B"), "Added becomes removed")
        #expect(patch.contains(" Line 2"), "Unchanged lines preserved")
    }
    
    @Test func testHunkHeaderCounting() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        let testFile = "test_hunk_header_\(UUID().uuidString).txt"
        
        // Create file with content
        let initialContent = """
        Line 1
        Line 2
        Line 3
        """
        try createTestFile(in: repoURL, named: testFile, content: initialContent)
        
        // Stage initial version
        try await repository.stageFile(at: testFile)
        
        // Modify file (add lines)
        let modifiedContent = """
        Line 1
        New line A
        New line B
        Line 2
        Line 3
        """
        try createTestFile(in: repoURL, named: testFile, content: modifiedContent)
        
        guard let status = try await repository.getWorkingTreeStatus(),
              let file = status.files[testFile]
        else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getFileDiff(for: file)

        #expect(!hunks.isEmpty, "Should have at least one hunk")

        let hunk = hunks[0]
        print("\n=== HUNK INFO ===")
        print("Header: \(hunk.header)")
        print("Lines: \(hunk.lines.count)")
        for (i, line) in hunk.lines.enumerated() {
            let text = line.segments.map { $0.text }.joined()
            print("  \(i): [\(line.type)] '\(text)'")
        }
        
        // Count lines by type
        let unchangedCount = hunk.lines.filter { $0.type == .unchanged }.count
        let addedCount = hunk.lines.filter { $0.type == .added }.count
        let removedCount = hunk.lines.filter { $0.type == .removed }.count
        
        print("Unchanged: \(unchangedCount), Added: \(addedCount), Removed: \(removedCount)")
        
        // Parse header
        let pattern = #"@@ -(\d+),(\d+) \+(\d+),(\d+) @@"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)),
           match.numberOfRanges == 5 {
            
            let oldCount = Int((hunk.header as NSString).substring(with: match.range(at: 2)))!
            let newCount = Int((hunk.header as NSString).substring(with: match.range(at: 4)))!
            
            print("Header oldCount: \(oldCount), newCount: \(newCount)")
            
            let expectedOldCount = unchangedCount + removedCount
            let expectedNewCount = unchangedCount + addedCount
            
            print("Expected oldCount: \(expectedOldCount), newCount: \(expectedNewCount)")
            
            #expect(oldCount == expectedOldCount, "Old count should match unchanged + removed")
            #expect(newCount == expectedNewCount, "New count should match unchanged + added")
        } else {
            Issue.record("Could not parse hunk header: \(hunk.header)")
        }
        
        // Cleanup
        try gitReset(in: repoURL)
        try FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
    }

    @Test func testStageHunkIntegration() async throws {
        guard let repoURL = getTestRepoURL() else {
            return
        }
        
        let repository = GitRepository(url: repoURL)
        let testFile = "test_stage_hunk_\(UUID().uuidString).txt"
        
        // Create and stage initial file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\n")
        _ = try await repository.stageFile(at: testFile)
        
        // Modify file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nNew line\nLine 2\n")
        
        // Get the hunk
        guard let status = try await repository.getWorkingTreeStatus(),
              let file = status.files[testFile]
        else {
            Issue.record("File not in status")
            return
        }
        
        let hunks = try await repository.getFileDiff(for: file)
        
        #expect(!hunks.isEmpty, "Should have hunks")
        
        let hunk = hunks[0]
        
        // Stage the hunk
        try await repository.stageHunk(hunk, in: file)

        // Verify it's staged
        let statusAfter = try await repository.getWorkingTreeStatus()
        print("Status after staging:\n\(String(describing: statusAfter))")
        
        let contains = statusAfter?.files.contains(where: { $0.value.path == file.path }) ?? false
        #expect(contains, "File should be staged")
        
        // Cleanup
        try gitReset(in: repoURL)
        try FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
    }
}

// MARK: - Test Helpers
private extension HunkStagingTests {
    func getTestRepoURL() -> URL? {
        let testRepoPath = "/Users/vg/Documents/Dev/TestRepo"
        let url = URL(fileURLWithPath: testRepoPath)
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        return url
    }
    
    func createTestFile(in repoURL: URL, named: String, content: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func gitStatus(in repoURL: URL) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "status", "--porcelain"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func gitReset(in repoURL: URL) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "reset", "HEAD"]
        task.launch()
        task.waitUntilExit()
    }
}

