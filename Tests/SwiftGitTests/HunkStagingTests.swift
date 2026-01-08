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
        
        // Verify reverse patch has swapped header
        #expect(patch.contains("@@ -1,4 +1,2 @@"), "Header should be reversed")
        #expect(patch.contains(" Line 1"), "Unchanged lines preserved")
        #expect(patch.contains("-New line A"), "Added becomes removed")
        #expect(patch.contains("-New line B"), "Added becomes removed")
        #expect(patch.contains(" Line 2"), "Unchanged lines preserved")
    }
    
    @Test func testHunkHeaderCounting() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

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
        
        try await repository.commit(message: "commit")

        let status = try await repository.getWorkingTreeStatus()

        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getFileDiff(for: file)

        #expect(!hunks.isEmpty, "Should have at least one hunk")

        let hunk = hunks[0]
        
        // Count lines by type
        let unchangedCount = hunk.lines.filter { $0.type == .unchanged }.count
        let addedCount = hunk.lines.filter { $0.type == .added }.count
        let removedCount = hunk.lines.filter { $0.type == .removed }.count
        
        // Parse header
        let pattern = #"@@ -(\d+),(\d+) \+(\d+),(\d+) @@"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)),
           match.numberOfRanges == 5 {
            
            let oldCount = Int((hunk.header as NSString).substring(with: match.range(at: 2)))!
            let newCount = Int((hunk.header as NSString).substring(with: match.range(at: 4)))!
            
            let expectedOldCount = unchangedCount + removedCount
            let expectedNewCount = unchangedCount + addedCount
            
            #expect(oldCount == expectedOldCount, "Old count should match unchanged + removed")
            #expect(newCount == expectedNewCount, "New count should match unchanged + added")
        } else {
            Issue.record("Could not parse hunk header: \(hunk.header)")
        }
        
        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testStageHunkIntegration() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_stage_hunk_\(UUID().uuidString).txt"
        
        // Create and stage initial file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "commit file")

        // Modify file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nNew line\nLine 2\n")
        
        // Get the hunk
        let status = try await repository.getWorkingTreeStatus()

        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getFileDiff(for: file)
        
        #expect(!hunks.isEmpty, "Should have hunks")
        
        let hunk = hunks[0]
        
        // Stage the hunk
        try await repository.stageHunk(hunk, in: file)

        // Verify it's staged
        let statusAfter = try await repository.getWorkingTreeStatus()
        
        let contains = statusAfter.files.contains(where: { $0.value.path == file.path })
        #expect(contains, "File should be staged")
        
        // Cleanup
        try await repository.discardFile(at: testFile)
    }
    
    // MARK: - Unstage Hunk Tests

    @Test func testUnstageHunk() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_unstage_hunk_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)
        
        // Create and commit initial file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")
        
        // Modify file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nModified Line 2\nLine 3\n")
        
        // Get file status
        let status = try await repository.getWorkingTreeStatus()

        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        // Get hunks
        let hunks = try await repository.getFileDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunks")
        
        // Stage the hunk
        try await repository.stageHunk(hunks[0], in: file)
        
        // Verify it's staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be staged")
        }
        
        // Get updated status and hunks
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        #expect(!stagedHunks.isEmpty, "Should have staged hunks")
        
        // Unstage the hunk
        try await repository.unstageHunk(stagedHunks[0], in: fileAfter)
        
        // Verify it's unstaged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix(" M "), "File should be unstaged")
        }
        
        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testTrailingNewlineDebug() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_trailing.txt"
        let repository = GitRepository(url: repoURL)
        
        // Create file WITHOUT trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)
        
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")
        
        // Modify with trailing newline (what Xcode does)
        try "Line 1\nModified Line 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        
        // Get hunks
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not in status")
            return
        }
        
        let hunks = try await repository.getFileDiff(for: file)
        
        // Stage first hunk
        try await repository.stageHunk(hunks[0], in: file)
    }

    @Test func testUnstageMultipleHunks() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let testFile = "test_unstage_multi_hunk.txt"
        let repository = GitRepository(url: repoURL)
        
        // Create file with multiple sections SEPARATED by enough context
        let initial = """
        Section 1
        Line A
        Line B
        
        Context line 1
        Context line 2
        Context line 3
        Context line 4
        Context line 5
        
        Section 2
        Line C
        Line D
        """
        
        let modified = """
        Section 1
        Modified Line A
        Line B
        
        Context line 1
        Context line 2
        Context line 3
        Context line 4
        Context line 5
        
        Section 2
        Line C
        Modified Line D
        """
        
        // Setup
        try createTestFile(in: repoURL, named: testFile, content: initial)
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")
        
        // Modify
        try createTestFile(in: repoURL, named: testFile, content: modified)
        
        // Get hunks
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not in status")
            return
        }
        
        let hunks = try await repository.getFileDiff(for: file)
        #expect(hunks.count >= 2, "Should have at least 2 hunks")
        
        // Stage all hunks
        for hunk in hunks {
            try await repository.stageHunk(hunk, in: file)
        }

        // Verify all staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be fully staged")
        }
        
        // Get staged hunks
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        
        // Unstage first hunk
        try await repository.unstageHunk(stagedHunks[0], in: fileAfter)
        
        // Verify partially unstaged
        let statusPartial = try await repository.getWorkingTreeStatus()
        let filePartial = statusPartial.files[testFile]
        #expect(filePartial?.staged != nil, "Should still have staged changes")
        #expect(filePartial?.unstaged != nil, "Should have unstaged changes")
    }
    
    @Test func testGeneratePatchForMultipleHunks() async throws {
        let generator = PatchGenerator()
        
        // Create two hunks (changes in different parts of file)
        let hunk1 = DiffHunk(
            id: 0,
            header: "@@ -1,3 +1,3 @@",
            lines: [
                DiffLine(
                    id: 0,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 1", isHighlighted: false)]
                ),
                DiffLine(
                    id: 1,
                    type: .removed,
                    segments: [Segment(id: 0, text: "Old Line 2", isHighlighted: false)]
                ),
                DiffLine(
                    id: 2,
                    type: .added,
                    segments: [Segment(id: 0, text: "New Line 2", isHighlighted: false)]
                ),
                DiffLine(
                    id: 3,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 3", isHighlighted: false)]
                )
            ]
        )
        
        let hunk2 = DiffHunk(
            id: 1,
            header: "@@ -8,3 +8,3 @@",
            lines: [
                DiffLine(
                    id: 0,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 8", isHighlighted: false)]
                ),
                DiffLine(
                    id: 1,
                    type: .removed,
                    segments: [Segment(id: 0, text: "Old Line 9", isHighlighted: false)]
                ),
                DiffLine(
                    id: 2,
                    type: .added,
                    segments: [Segment(id: 0, text: "New Line 9", isHighlighted: false)]
                ),
                DiffLine(
                    id: 3,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 10", isHighlighted: false)]
                )
            ]
        )
        
        let file = WorkingTreeFile(
            path: "Test.swift",
            staged: nil,
            unstaged: .modified
        )
        
        let patch = generator.generatePatch(hunks: [hunk1, hunk2], file: file)
        
        // Verify patch has header
        #expect(patch.contains("diff --git a/Test.swift b/Test.swift"))
        
        // Verify both hunks are included
        #expect(patch.contains("@@ -1,3 +1,3 @@"), "First hunk header")
        #expect(patch.contains("@@ -8,3 +8,3 @@"), "Second hunk header")
        
        // Verify first hunk content
        #expect(patch.contains("-Old Line 2"))
        #expect(patch.contains("+New Line 2"))
        
        // Verify second hunk content
        #expect(patch.contains("-Old Line 9"))
        #expect(patch.contains("+New Line 9"))
    }
    
    @Test func testPatchWithNoNewlineAtEnd() async throws {
        let generator = PatchGenerator()
        
        // Create hunk with no newline at end (flag set)
        let hunk = DiffHunk(
            id: 0,
            header: "@@ -1,2 +1,2 @@",
            lines: [
                DiffLine(
                    id: 0,
                    type: .unchanged,
                    segments: [Segment(id: 0, text: "Line 1", isHighlighted: false)]
                ),
                DiffLine(
                    id: 1,
                    type: .removed,
                    segments: [Segment(id: 0, text: "Old Line 2", isHighlighted: false)]
                ),
                DiffLine(
                    id: 2,
                    type: .added,
                    segments: [Segment(id: 0, text: "New Line 2", isHighlighted: false)]
                )
            ],
            hasNoNewlineAtEnd: true  // ← Flag set
        )
        
        let file = WorkingTreeFile(
            path: "NoNewline.txt",
            staged: nil,
            unstaged: .modified
        )
        
        let patch = generator.generatePatch(hunk: hunk, file: file)
        
        // Verify patch contains the marker
        #expect(patch.contains("\\ No newline at end of file"), "Should have no newline marker")
        
        // Verify last line doesn't have extra newline
        let lines = patch.split(separator: "\n", omittingEmptySubsequences: false)
        
        // Find the last added line
        let addedLineIndex = lines.lastIndex(where: { $0.hasPrefix("+New Line 2") })
        #expect(addedLineIndex != nil, "Should find added line")
        
        // The marker should come after
        if let index = addedLineIndex {
            let nextLine = lines[index + 1]
            #expect(nextLine.hasPrefix("\\"), "Next line should be the marker")
        }
    }
}

// MARK: - Test Helpers
private extension HunkStagingTests {
    func createTestFile(in repoURL: URL, named: String, content: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    func statusLine(for file: String, in repoURL: URL) throws -> String? {
        let output = try gitStatus(in: repoURL)
        // Each line is two status columns + space + path
        return output
            .split(separator: "\n")
            .map(String.init)
            .first { $0.hasSuffix(" \(file)") || $0.hasSuffix(file) }
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
}
