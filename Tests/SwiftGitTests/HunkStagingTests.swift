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
        
        let status = try await repository.getWorkingTreeStatus()

        guard let file = status.files[testFile] else {
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
        print("Status after staging:\n\(String(describing: statusAfter))")
        
        let contains = statusAfter.files.contains(where: { $0.value.path == file.path })
        #expect(contains, "File should be staged")
        
        // Cleanup
        try gitReset(in: repoURL)
        try FileManager.default.removeItem(at: repoURL.appendingPathComponent(testFile))
    }
    
    // MARK: - Unstage Hunk Tests

    @Test func testUnstageHunk() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let testFile = "test_unstage_hunk_\(UUID().uuidString).txt"
        let repository = GitRepository(url: repoURL)
        
        // Create and commit initial file
        try createTestFile(in: repoURL, named: testFile, content: "Line 1\nLine 2\nLine 3\n")
        try gitAdd(in: repoURL, pathspec: testFile)
        try gitCommit(in: repoURL, message: "Initial commit")
        
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
        try gitReset(in: repoURL)
        try gitCheckout(in: repoURL, file: testFile)
        try? deleteTestFile(in: repoURL, named: testFile)
    }

    @Test func testTrailingNewlineDebug() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let testFile = "test_trailing.txt"
        let repository = GitRepository(url: repoURL)
        
        // Create file WITHOUT trailing newline
        let fileURL = repoURL.appendingPathComponent(testFile)
        try "Line 1\nLine 2".write(to: fileURL, atomically: true, encoding: .utf8)
        
        try gitAdd(in: repoURL, pathspec: testFile)
        try gitCommit(in: repoURL, message: "Initial")
        
        // Modify with trailing newline (what Xcode does)
        try "Line 1\nModified Line 2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        
        // Get hunks
        let status = try await repository.getWorkingTreeStatus()
        guard let file = status.files[testFile] else {
            Issue.record("File not in status")
            return
        }
        
        let hunks = try await repository.getFileDiff(for: file)
        
        print("\n=== HUNKS GENERATED ===")
        for (i, hunk) in hunks.enumerated() {
            print("Hunk \(i): \(hunk.header)")
            print("Lines: \(hunk.lines.count)")
            for line in hunk.lines {
                let text = line.segments.map { $0.text }.joined()
                print("  [\(line.type)] '\(text)'")
            }
        }
        
        // Stage first hunk
        try await repository.stageHunk(hunks[0], in: file)
        
        // After staging, check with git directly
        let gitDiff = try gitDiffOutput(in: repoURL, file: testFile)
        print("\n=== GIT DIFF (unstaged) ===")
        print(gitDiff)
        print("=== END GIT DIFF ===")

        let gitDiffCached = try gitDiffCached(in: repoURL, file: testFile)
        print("\n=== GIT DIFF --CACHED (staged) ===")
        print(gitDiffCached)
        print("=== END GIT DIFF ===")

        // Check what's left
        let statusAfter = try await repository.getWorkingTreeStatus()
        let fileAfter = statusAfter.files[testFile]
        
        print("\n=== AFTER STAGING ===")
        print("Staged: \(String(describing: fileAfter?.staged))")
        print("Unstaged: \(String(describing: fileAfter?.unstaged))")
        
        if let fileAfter = fileAfter {
            let remainingHunks = try await repository.getFileDiff(for: fileAfter)
            print("\n=== REMAINING UNSTAGED HUNKS ===")
            for (i, hunk) in remainingHunks.enumerated() {
                print("Hunk \(i): \(hunk.header)")
                for line in hunk.lines {
                    let text = line.segments.map { $0.text }.joined()
                    print("  [\(line.type)] '\(text)'")
                }
            }
        }
        
        // Cleanup
        try gitReset(in: repoURL)
        try gitCheckout(in: repoURL, file: testFile)
    }

    @Test func testUnstageMultipleHunks() async throws {
        guard let repoURL = getTestRepoURL() else { return }
        
        let testFile = "test_unstage_multi_hunk.txt"
        let repository = GitRepository(url: repoURL)
        
        // Create file with multiple sections
        let initial = """
        Section 1
        Line A
        Line B
        
        Section 2
        Line C
        Line D
        """
        
        let modified = """
        Section 1
        Modified Line A
        Line B
        
        Section 2
        Line C
        Modified Line D
        """
        
        // Setup
        try createTestFile(in: repoURL, named: testFile, content: initial)
        try gitAdd(in: repoURL, pathspec: testFile)
        try gitCommit(in: repoURL, message: "Initial commit")
        
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
        
        // Cleanup
        try gitReset(in: repoURL)
        try gitCheckout(in: repoURL, file: testFile)
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
    
    func gitAdd(in repoURL: URL, pathspec: String = ".") throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "add", pathspec]
        task.launch()
        task.waitUntilExit()
    }
    
    func gitCommit(in repoURL: URL, message: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "commit", "-m", message]
        task.launch()
        task.waitUntilExit()
    }
    
    func gitReset(in repoURL: URL, hard: Bool = false) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        var args = ["-C", repoURL.path, "reset"]
        if hard {
            args.append("--hard")
        }
        args.append("HEAD")
        task.arguments = args
        task.launch()
        task.waitUntilExit()
    }
    
    func statusLine(for file: String, in repoURL: URL) throws -> String? {
        let output = try gitStatus(in: repoURL)
        // Each line is two status columns + space + path
        return output
            .split(separator: "\n")
            .map(String.init)
            .first { $0.hasSuffix(" \(file)") || $0.hasSuffix(file) }
    }
    
    func gitCheckout(in repoURL: URL, file: String) throws {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "checkout", "HEAD", "--", file]
        task.launch()
        task.waitUntilExit()
    }
    
    func deleteTestFile(in repoURL: URL, named: String) throws {
        let fileURL = repoURL.appendingPathComponent(named)
        try FileManager.default.removeItem(at: fileURL)
    }

    func gitDiffOutput(in repoURL: URL, file: String) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "diff", file]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func gitDiffCached(in repoURL: URL, file: String) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path, "diff", "--cached", file]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

}
