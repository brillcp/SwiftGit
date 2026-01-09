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

        // Modify to match your screenshot
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

        // Get YOUR hunks
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("No file")
            return
        }

        let yourHunks = try await repository.getFileDiff(for: file)

        // Get GIT's hunks
        let gitDiff = try gitDiffOutput(in: repoURL, file: testFile)

        print("\n=== YOUR HUNKS ===")
        for (i, hunk) in yourHunks.enumerated() {
            print("\nHunk \(i + 1):")
            print(hunk.header)
            print("Lines: \(hunk.lines.count)")
        }

        print("\n=== GIT'S HUNKS ===")
        print(gitDiff)
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
