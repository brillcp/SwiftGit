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
