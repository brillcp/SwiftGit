import Testing
import Foundation
@testable import SwiftGit

@Suite("Working Tree Status Tests")
struct WorkingTreeStatusTests {
    @Test func nestedRepoIsListedOnlyWhenItsCommitMoves() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftGit-Nested-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        try makeRepo(at: nested)
        try "inner\n".write(to: nested.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        try git(nested, "add", "inner.txt")
        try git(nested, "commit", "-m", "inner")

        try makeRepo(at: root)
        try git(root, "add", "nested")
        try git(root, "commit", "-m", "add nested repo")

        let repository = GitRepository(url: root)

        try "dirty\n".write(to: nested.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
        try "untracked\n".write(to: nested.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let dirtyStatus = try await repository.getWorkingTreeStatus()
        #expect(dirtyStatus.files["nested"] == nil)

        try git(nested, "add", "-A")
        try git(nested, "commit", "-m", "inner moved")
        let movedStatus = try await repository.getWorkingTreeStatus()
        #expect(movedStatus.files["nested"]?.unstaged == .modified)
    }
}

private func makeRepo(at url: URL) throws {
    try git(url, "init", "-b", "main")
    try git(url, "config", "user.name", "Test User")
    try git(url, "config", "user.email", "test@example.com")
}

private func git(_ url: URL, _ arguments: String...) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", url.path] + arguments
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ")])
    }
}
