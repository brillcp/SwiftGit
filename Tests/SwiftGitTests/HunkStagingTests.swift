import Testing
import Foundation
@testable import SwiftGit

@Suite("Hunk Staging Tests")
struct HunkStagingTests {
    @Test func testHunkHeadersMatchGit() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.swift"

        // Create initial content
        let initial = """
        struct Foo {
            let text = "Hello, Swift!"
        }

        // Testing and stuff
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and 💫…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…

        struct Bar {
            let name: String
            let value: Double
        }

        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…

        struct Fiz {
            let date: Date
        }
        """

        try createTestFile(in: repoURL, named: testFile, content: initial)
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Modify content
        let modified = """
        struct Foo {
            let text = "Hello, Swift"
        }

        // Testing and stuff
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and 💫…
        // Testing and stuff…
        // Testing & stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…
        // Testing and stuff…

        struct Bar {
            let name: String
            let value: Double
        }

        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…
        // More comments…

        struct Fiz {
            let date: Date
        }
        """

        try createTestFile(in: repoURL, named: testFile, content: modified)

        // Get hunks
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let yourHunks = try await repository.getUnstagedDiff(for: file)

        #expect(yourHunks.count == 3, "Should have 3 hunks")
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

        let hunks = try await repository.getUnstagedDiff(for: file)

        #expect(!hunks.isEmpty, "Should have at least one hunk")

        let hunk = hunks[0]
        let unchangedCount = hunks[0].lines.filter { $0.type == .unchanged }.count
        let removedCount = hunks[0].lines.filter { $0.type == .removed }.count
        let addedCount = hunks[0].lines.filter { $0.type == .added }.count

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

    @Test func testStageHunk() async throws {
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

        let hunks = try await repository.getUnstagedDiff(for: file)

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
        let hunks = try await repository.getUnstagedDiff(for: file)
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

    @Test func testDiscardHunkWithTrailingNewline() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create file WITHOUT trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)

        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Add trailing newline
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        // Get hunks
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunk for trailing newline")

        // Discard the hunk
        try await repository.discardHunk(hunks[0], in: file)

        // Verify newline is gone
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!content.hasSuffix("\n"), "Trailing newline should be removed")

        // Verify no more changes
        let statusAfter = try await repository.getWorkingTreeStatus()
        #expect(statusAfter.files[testFile] == nil, "File should be clean")
    }

    @Test func testDiscardHunkRemovingTrailingNewline() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create file WITH trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Remove trailing newline
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunk for trailing newline removal")

        try await repository.discardHunk(hunks[0], in: file)

        // Verify newline is restored
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(content.hasSuffix("\n"), "Trailing newline should be restored")

        let statusAfter = try await repository.getWorkingTreeStatus()
        #expect(statusAfter.files[testFile] == nil, "File should be clean")
    }

    @Test func testStageHunkAddingTrailingNewline() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create file WITHOUT trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)

        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Add trailing newline
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunk for trailing newline addition")

        try await repository.stageHunk(hunks[0], in: file)

        // Verify staged diff has the change
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("No file after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        #expect(!stagedHunks.isEmpty, "Should have staged hunk")

        // Unstaged should be clean
        let unstagedHunks = try await repository.getUnstagedDiff(for: fileAfter)
        #expect(unstagedHunks.isEmpty, "No unstaged changes should remain")
    }

    @Test func testStageHunkRemovingTrailingNewline() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create file WITH trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Remove trailing newline
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunk for trailing newline removal")

        try await repository.stageHunk(hunks[0], in: file)

        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("No file after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        #expect(!stagedHunks.isEmpty, "Should have staged hunk")

        let unstagedHunks = try await repository.getUnstagedDiff(for: fileAfter)
        #expect(unstagedHunks.isEmpty, "No unstaged changes should remain")
    }

    @Test func testUnstageHunkAddingTrailingNewline() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create file WITHOUT trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)

        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Add trailing newline and stage it
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try await repository.stageFile(at: testFile)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let stagedHunks = try await repository.getStagedDiff(for: file)
        #expect(!stagedHunks.isEmpty, "Should have staged hunk")

        try await repository.unstageHunk(stagedHunks[0], in: file)

        // Staged should be clean
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("No file after unstaging")
            return
        }
        let stagedAfter = try await repository.getStagedDiff(for: fileAfter)
        #expect(stagedAfter.isEmpty, "No staged changes should remain")

        // Unstaged should have the change back
        let unstagedAfter = try await repository.getUnstagedDiff(for: fileAfter)
        #expect(!unstagedAfter.isEmpty, "Unstaged diff should be restored")
    }

    @Test func testUnstageHunkRemovingTrailingNewline() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test.txt"

        // Create file WITH trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2\n".write(to: fileURL, atomically: true, encoding: .utf8)

        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial")

        // Remove trailing newline and stage it
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)
        try await repository.stageFile(at: testFile)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let stagedHunks = try await repository.getStagedDiff(for: file)
        #expect(!stagedHunks.isEmpty, "Should have staged hunk")

        try await repository.unstageHunk(stagedHunks[0], in: file)

        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("No file after unstaging")
            return
        }
        let stagedAfter = try await repository.getStagedDiff(for: fileAfter)
        #expect(stagedAfter.isEmpty, "No staged changes should remain")

        let unstagedAfter = try await repository.getUnstagedDiff(for: fileAfter)
        #expect(!unstagedAfter.isEmpty, "Unstaged diff should be restored")
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

        let hunks = try await repository.getUnstagedDiff(for: file)
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

    @Test func testStageAddedLine() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_stage_line_added_\(UUID().uuidString).txt"

        // Create and commit initial file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")

        // Add two lines in different places so we can stage only one
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nAdded A\nLine 2\nAdded B\nLine 3\n")

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunks")

        // Find the first added line and its line numbers
        let hunk = hunks[0]
        guard let lineIndex = hunk.lines.firstIndex(where: { $0.type == .added }) else {
            Issue.record("No added line found")
            return
        }

        // Calculate line numbers for the target line
        var oldLineNum: Int? = nil
        var newLineNum: Int? = nil
        let headerPattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        if let regex = try? NSRegularExpression(pattern: headerPattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)) {
            let oldStart = Int((hunk.header as NSString).substring(with: match.range(at: 1))) ?? 1
            let newStart = Int((hunk.header as NSString).substring(with: match.range(at: 2))) ?? 1
            var oldCount = 0
            var newCount = 0
            for line in hunk.lines.prefix(lineIndex) {
                if line.type == .unchanged || line.type == .removed { oldCount += 1 }
                if line.type == .unchanged || line.type == .added { newCount += 1 }
            }
            oldLineNum = oldStart + oldCount
            newLineNum = newStart + newCount
        }

        // Stage just this one added line
        try await repository.stageLine(at: lineIndex, oldNum: oldLineNum, newNum: newLineNum, in: hunk, file: file)

        // Verify file is now partially staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("MM"), "File should have both staged and unstaged changes")
        }

        // Verify the staged diff contains only one added line
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        let totalStagedAdded = stagedHunks.flatMap(\.lines).filter { $0.type == .added }.count
        #expect(totalStagedAdded == 1, "Should have exactly 1 staged added line")

        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testStageRemovedLine() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_stage_line_removed_\(UUID().uuidString).txt"

        // Create file with multiple lines and commit
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nRemove me\nLine 2\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")

        // Remove one line
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\nLine 3\n")

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunks")

        let hunk = hunks[0]
        guard let lineIndex = hunk.lines.firstIndex(where: { $0.type == .removed }) else {
            Issue.record("No removed line found")
            return
        }

        // Calculate line numbers
        var oldLineNum: Int? = nil
        var newLineNum: Int? = nil
        let headerPattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        if let regex = try? NSRegularExpression(pattern: headerPattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)) {
            let oldStart = Int((hunk.header as NSString).substring(with: match.range(at: 1))) ?? 1
            let newStart = Int((hunk.header as NSString).substring(with: match.range(at: 2))) ?? 1
            var oldCount = 0
            var newCount = 0
            for line in hunk.lines.prefix(lineIndex) {
                if line.type == .unchanged || line.type == .removed { oldCount += 1 }
                if line.type == .unchanged || line.type == .added { newCount += 1 }
            }
            oldLineNum = oldStart + oldCount
            newLineNum = newStart + newCount
        }

        // Stage just the removed line
        try await repository.stageLine(at: lineIndex, oldNum: oldLineNum, newNum: newLineNum, in: hunk, file: file)

        // Verify it's staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be fully staged (single removal)")
        }

        // Verify staged diff has the removal
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        let totalStagedRemoved = stagedHunks.flatMap(\.lines).filter { $0.type == .removed }.count
        #expect(totalStagedRemoved == 1, "Should have exactly 1 staged removed line")

        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testUnstageAddedLine() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_unstage_line_added_\(UUID().uuidString).txt"

        // Commit initial file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")

        // Add two lines and stage the whole file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nAdded A\nLine 2\nAdded B\nLine 3\n")
        try await repository.stageFile(at: testFile)

        // Verify fully staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be fully staged before unstaging a line")
        }

        // Get the staged diff
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let stagedHunks = try await repository.getStagedDiff(for: file)
        #expect(!stagedHunks.isEmpty, "Should have staged hunks")

        let hunk = stagedHunks[0]
        guard let lineIndex = hunk.lines.firstIndex(where: { $0.type == .added }) else {
            Issue.record("No added line in staged diff")
            return
        }

        // Calculate line numbers
        var oldLineNum: Int? = nil
        var newLineNum: Int? = nil
        let headerPattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        if let regex = try? NSRegularExpression(pattern: headerPattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)) {
            let oldStart = Int((hunk.header as NSString).substring(with: match.range(at: 1))) ?? 1
            let newStart = Int((hunk.header as NSString).substring(with: match.range(at: 2))) ?? 1
            var oldCount = 0
            var newCount = 0
            for line in hunk.lines.prefix(lineIndex) {
                if line.type == .unchanged || line.type == .removed { oldCount += 1 }
                if line.type == .unchanged || line.type == .added { newCount += 1 }
            }
            oldLineNum = oldStart + oldCount
            newLineNum = newStart + newCount
        }

        // Unstage one added line
        try await repository.unstageLine(at: lineIndex, oldNum: oldLineNum, newNum: newLineNum, in: hunk, file: file)

        // File should now be partially staged (MM) since we staged 2 additions but unstaged 1
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("MM") || line.hasPrefix("M  "), "File should have staged changes remaining")
        }

        // Cleanup
        try await repository.discardFile(at: testFile)
    }

    @Test func testUnstageRemovedLine() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_unstage_line_removed_\(UUID().uuidString).txt"

        // Commit initial file with a line we'll remove
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nRemove me\nLine 2\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")

        // Remove the line and stage the change
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\n")
        try await repository.stageFile(at: testFile)

        // Verify fully staged
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("M  "), "File should be fully staged")
        }

        // Get staged diff
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let stagedHunks = try await repository.getStagedDiff(for: file)
        #expect(!stagedHunks.isEmpty, "Should have staged hunks")

        let hunk = stagedHunks[0]
        guard let lineIndex = hunk.lines.firstIndex(where: { $0.type == .removed }) else {
            Issue.record("No removed line in staged diff")
            return
        }

        // Calculate line numbers
        var oldLineNum: Int? = nil
        var newLineNum: Int? = nil
        let headerPattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        if let regex = try? NSRegularExpression(pattern: headerPattern),
           let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header)) {
            let oldStart = Int((hunk.header as NSString).substring(with: match.range(at: 1))) ?? 1
            let newStart = Int((hunk.header as NSString).substring(with: match.range(at: 2))) ?? 1
            var oldCount = 0
            var newCount = 0
            for line in hunk.lines.prefix(lineIndex) {
                if line.type == .unchanged || line.type == .removed { oldCount += 1 }
                if line.type == .unchanged || line.type == .added { newCount += 1 }
            }
            oldLineNum = oldStart + oldCount
            newLineNum = newStart + newCount
        }

        // Unstage the removed line
        try await repository.unstageLine(at: lineIndex, oldNum: oldLineNum, newNum: newLineNum, in: hunk, file: file)

        // After unstaging the removal, file should be clean (original line restored to index)
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix(" M "), "File should be fully unstaged after restoring removed line")
        }

        // Cleanup
        try await repository.discardFile(at: testFile)
    }
    @Test func testStageOnlyOneSideOfSubstitution() async throws {
        // A "substitution" (a removed line immediately followed by its
        // replacement) used to be auto-paired: clicking either side staged
        // BOTH lines. That magic surprised users for hunks like
        // `[7 deletions, 3 additions]` where clicking a removal stealthily
        // staged an unrelated addition. The new contract is "one click =
        // one line"; pair-staging is reachable by clicking each side.
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "test_stage_substitution_\(UUID().uuidString).txt"

        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nOld line\nLine 3\n")
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Initial commit")

        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nNew line\nLine 3\n")

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Should have hunks")
        let hunk = hunks[0]

        guard let addedIndex = hunk.lines.firstIndex(where: { $0.type == .added }) else {
            Issue.record("No added line found")
            return
        }
        #expect(addedIndex > 0 && hunk.lines[addedIndex - 1].type == .removed,
                "Should be a paired remove+add substitution")

        let (oldLineNum, newLineNum) = lineNumbers(in: hunk, at: addedIndex)
        try await repository.stageLine(at: addedIndex, oldNum: oldLineNum, newNum: newLineNum, in: hunk, file: file)

        // File should be PARTIALLY staged — only the added side landed in
        // the index. The removal still needs a separate click.
        if let line = try statusLine(for: testFile, in: repoURL) {
            #expect(line.hasPrefix("MM"), "Only the added side should be staged; deletion still pending")
        }

        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        let stagedRemoved = stagedHunks.flatMap(\.lines).filter { $0.type == .removed }.count
        let stagedAdded   = stagedHunks.flatMap(\.lines).filter { $0.type == .added }.count
        #expect(stagedRemoved == 0, "No removal should be staged from the single added-line click")
        #expect(stagedAdded == 1, "Exactly one addition should be staged")

        // Removal still in the unstaged diff for the user to opt into.
        let unstagedHunks = try await repository.getUnstagedDiff(for: fileAfter)
        let unstagedRemoved = unstagedHunks.flatMap(\.lines).filter { $0.type == .removed }.count
        #expect(unstagedRemoved == 1, "Removal should remain unstaged until clicked separately")

        try await repository.discardFile(at: testFile)
    }

    // MARK: - Duplicate adjacent lines
    //
    // Regression coverage for a bug where staging a single line from a hunk
    // containing many identical adjacent lines could "stage" the change at
    // multiple positions, leaving the index with phantom duplicates. Caused
    // by `git apply --ignore-whitespace --unidiff-zero` matching the
    // line-text loosely; fixed by passing `strict: true` for line-level
    // patches and emitting canonical `+(N-1),0` headers for deletions.

    @Test func testStageOneRemovedLineWhenManyIdenticalLinesExist() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "duplicate_remove_\(UUID().uuidString).swift"

        // 7 identical lines surrounded by anchors. Anchors stop git's diff
        // from collapsing the deletion block into a "context shift".
        let initial = """
        let header = "top"
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        let footer = "bottom"
        """
        try createTestFile(in: repoURL, named: testFile, content: initial)
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Seven duplicates")

        // Keep one of the seven, remove the other six.
        let modified = """
        let header = "top"
        var dupe = 0
        let footer = "bottom"
        """
        try createTestFile(in: repoURL, named: testFile, content: modified)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Expected unstaged hunks")
        let hunk = hunks[0]

        // Pick the first removed line in the hunk.
        guard let lineIndex = hunk.lines.firstIndex(where: { $0.type == .removed }) else {
            Issue.record("No removed line found")
            return
        }

        let removedCount = hunk.lines.filter { $0.type == .removed }.count
        #expect(removedCount == 6, "Expected 6 removed lines in the unstaged hunk; got \(removedCount)")

        // Compute (oldNum, newNum) for the picked line.
        let (oldLineNum, newLineNum) = lineNumbers(in: hunk, at: lineIndex)

        try await repository.stageLine(
            at: lineIndex,
            oldNum: oldLineNum,
            newNum: newLineNum,
            in: hunk,
            file: file
        )

        // Index must have lost exactly one duplicate. Staged diff: 1 deletion, 0 additions.
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        let stagedRemoved = stagedHunks.flatMap(\.lines).filter { $0.type == .removed }.count
        let stagedAdded   = stagedHunks.flatMap(\.lines).filter { $0.type == .added }.count
        #expect(stagedRemoved == 1, "Exactly one removal should be staged; got \(stagedRemoved)")
        #expect(stagedAdded == 0, "No additions should be staged; got \(stagedAdded)")

        // Unstaged side keeps the remaining 5 deletions.
        let unstagedAfter = try await repository.getUnstagedDiff(for: fileAfter)
        let unstagedRemoved = unstagedAfter.flatMap(\.lines).filter { $0.type == .removed }.count
        #expect(unstagedRemoved == 5, "Five removals should remain unstaged; got \(unstagedRemoved)")

        try await repository.discardFile(at: testFile)
    }

    @Test func testStageOneAddedLineNextToManyIdenticalRemovedLines() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "duplicate_add_\(UUID().uuidString).swift"

        // HEAD has 7 identical lines.
        let initial = """
        let header = "top"
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        var dupe = 0
        let footer = "bottom"
        """
        try createTestFile(in: repoURL, named: testFile, content: initial)
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Seven duplicates")

        // Working tree has 3 new top lines, removes all 7 duplicates.
        let modified = """
        let header = "top"
        // doc-1
        // doc-2
        var newProperty = 0
        let footer = "bottom"
        """
        try createTestFile(in: repoURL, named: testFile, content: modified)

        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not found in status")
            return
        }

        let hunks = try await repository.getUnstagedDiff(for: file)
        #expect(!hunks.isEmpty, "Expected unstaged hunks")
        let hunk = hunks[0]

        // Find the FIRST added line (one of the doc lines or the new var).
        guard let lineIndex = hunk.lines.firstIndex(where: { $0.type == .added }) else {
            Issue.record("No added line found")
            return
        }

        let (oldLineNum, newLineNum) = lineNumbers(in: hunk, at: lineIndex)

        try await repository.stageLine(
            at: lineIndex,
            oldNum: oldLineNum,
            newNum: newLineNum,
            in: hunk,
            file: file
        )

        // Staged side: exactly 1 addition. The presence of 7 identical text
        // lines elsewhere in the file must not bleed into the staged diff.
        let statusAfter = try await repository.getWorkingTreeStatus()
        guard let fileAfter = statusAfter.files[testFile] else {
            Issue.record("File not in status after staging")
            return
        }
        let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
        let stagedAdded   = stagedHunks.flatMap(\.lines).filter { $0.type == .added }.count
        let stagedRemoved = stagedHunks.flatMap(\.lines).filter { $0.type == .removed }.count
        #expect(stagedAdded == 1, "Exactly one addition should be staged; got \(stagedAdded)")
        #expect(stagedRemoved == 0, "No removals should be staged yet; got \(stagedRemoved)")

        try await repository.discardFile(at: testFile)
    }

    @Test func testStageEachRemovedLineSequentiallyAmongDuplicates() async throws {
        // Stage every removed line one-by-one and confirm the index
        // converges to "one duplicate left" — not "all gone immediately"
        // and not "still seven" after the loop. Catches both over- and
        // under-application of the line patch.
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let testFile = "duplicate_sequential_\(UUID().uuidString).swift"

        let initial = """
        let header = "top"
        var dupe = 0
        var dupe = 0
        var dupe = 0
        let footer = "bottom"
        """
        try createTestFile(in: repoURL, named: testFile, content: initial)
        try await repository.stageFile(at: testFile)
        try await repository.commit(message: "Three duplicates")

        let modified = """
        let header = "top"
        var dupe = 0
        let footer = "bottom"
        """
        try createTestFile(in: repoURL, named: testFile, content: modified)

        // Stage one removal, refresh, stage the next, refresh, stage the
        // last. After each step the staged-removed count should grow by
        // exactly one.
        for expectedStaged in 1...2 {
            let status = try await repository.getWorkingTreeStatus()
            guard let file = status.files[testFile] else {
                Issue.record("File not found in status (iter \(expectedStaged))")
                return
            }
            let hunks = try await repository.getUnstagedDiff(for: file)
            guard let hunk = hunks.first,
                  let lineIndex = hunk.lines.firstIndex(where: { $0.type == .removed })
            else {
                Issue.record("No removed line at iter \(expectedStaged)")
                return
            }
            let (oldLineNum, newLineNum) = lineNumbers(in: hunk, at: lineIndex)
            try await repository.stageLine(
                at: lineIndex,
                oldNum: oldLineNum,
                newNum: newLineNum,
                in: hunk,
                file: file
            )

            let statusAfter = try await repository.getWorkingTreeStatus()
            guard let fileAfter = statusAfter.files[testFile] else {
                Issue.record("File not in status after iter \(expectedStaged)")
                return
            }
            let stagedHunks = try await repository.getStagedDiff(for: fileAfter)
            let stagedRemoved = stagedHunks.flatMap(\.lines).filter { $0.type == .removed }.count
            #expect(
                stagedRemoved == expectedStaged,
                "After staging iter \(expectedStaged): expected \(expectedStaged) staged removals, got \(stagedRemoved)"
            )
        }

        try await repository.discardFile(at: testFile)
    }

    // MARK: - Helpers

    /// Compute (oldLineNum, newLineNum) for the line at `lineIndex` in
    /// `hunk` by walking from the parsed hunk header. Mirrors what the
    /// production callers (e.g. DiffViewModel) do before calling
    /// `stageLine`.
    private func lineNumbers(in hunk: DiffHunk, at lineIndex: Int) -> (Int?, Int?) {
        let headerPattern = #"@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: headerPattern),
              let match = regex.firstMatch(in: hunk.header, range: NSRange(hunk.header.startIndex..., in: hunk.header))
        else { return (nil, nil) }

        let oldStart = Int((hunk.header as NSString).substring(with: match.range(at: 1))) ?? 1
        let newStart = Int((hunk.header as NSString).substring(with: match.range(at: 2))) ?? 1

        var oldCount = 0
        var newCount = 0
        for line in hunk.lines.prefix(lineIndex) {
            if line.type == .unchanged || line.type == .removed { oldCount += 1 }
            if line.type == .unchanged || line.type == .added   { newCount += 1 }
        }

        let target = hunk.lines[lineIndex]
        let oldLineNum: Int? = (target.type == .added) ? nil : oldStart + oldCount
        let newLineNum: Int? = (target.type == .removed) ? nil : newStart + newCount
        return (oldLineNum, newLineNum)
    }
}

func gitDiffOutput(in repoURL: URL, file: String) throws -> String {
    let process = Process ()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", repoURL.path, "diff", file]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.launch()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8) ?? ""
}
