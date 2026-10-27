import Foundation
import Testing
@testable import SwiftGit

@Suite("History Tests")
struct HistoryTests {
    @Test func mergeBaseFindsTheForkPoint() async throws {
        let repoURL = try makeForkedRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)

        let fork = try runGit(repoURL, "rev-parse", "fork")
        #expect(try await repository.mergeBase("main", "feature") == fork)
    }

    @Test func fileHistoryListsOnlyCommitsTouchingThePath() async throws {
        let repoURL = try makeForkedRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)

        let commits = try await repository.fileHistory(path: "a.txt", range: "fork..feature", limit: 10)
        #expect(commits.map(\.title) == ["Feature edits a", "Feature adds a line"])
        #expect(commits.last?.body.contains("with body") == true)
    }

    @Test func searchFindsFixedStringsInARefAndTheWorkingTree() async throws {
        let repoURL = try makeForkedRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)

        let inFeature = try await repository.search("feature line", in: "feature", limit: 10)
        #expect(inFeature == [GrepMatch(path: "a.txt", line: 2, text: "feature line (x)")])

        // main is checked out and never had it.
        #expect(try await repository.search("feature line", in: nil, limit: 10).isEmpty)
        // A regex metacharacter is matched literally.
        #expect(try await repository.search("(x)", in: "feature", limit: 10).count == 1)
    }

    @Test func rangeDiffPairsRebasedCommits() async throws {
        let repoURL = try makeForkedRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)

        let before = try runGit(repoURL, "rev-parse", "feature")
        try runGit(repoURL, "checkout", "-q", "feature")
        try runGit(repoURL, "rebase", "-q", "main")

        let entries = try await repository.rangeDiff(base: "main", oldTip: before, newTip: "feature", creationFactor: nil, includePatches: false)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.change == .unchanged })
        #expect(entries.map(\.subject) == ["Feature adds a line", "Feature edits a"])
    }

    @Test func rangeDiffAllowsAnEmptyNewRange() async throws {
        let repoURL = try makeForkedRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)

        // Every feature commit dropped: nothing left in main..main.
        let entries = try await repository.rangeDiff(base: "main", oldTip: "feature", newTip: "main", creationFactor: nil, includePatches: false)
        #expect(entries.map(\.change) == [.removed, .removed])
    }

    @Test func aHigherCreationFactorPairsAReworkedCommit() async throws {
        let repoURL = try makeForkedRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)

        // Rewrite feature's last commit completely, as a conflict resolution can.
        let before = try runGit(repoURL, "rev-parse", "feature")
        try runGit(repoURL, "checkout", "-q", "feature")
        try createTestFile(in: repoURL, named: "a.txt", content: "something else entirely\n")
        try runGit(repoURL, "commit", "-q", "--amend", "-am", "Feature edits a")

        let paired = try await repository.rangeDiff(base: "fork", oldTip: before, newTip: "feature", creationFactor: 100, includePatches: true)
        #expect(paired.map(\.change) == [.unchanged, .modified])
        #expect(paired.last?.patch.contains("something else entirely") == true)
    }

    @Test func rangeDiffParsesEveryKindOfRow() {
        let output = """
        1:  1111111 = 1:  aaaaaaa Same
        2:  2222222 ! 2:  bbbbbbb Changed
            @@ a.txt
            -old
            +new
        3:  3333333 < -:  ------- Dropped
        -:  ------- > 3:  ccccccc Added
        """
        let entries = RangeDiffEntry.parse(output)
        #expect(entries.map(\.change) == [.unchanged, .modified, .removed, .added])
        #expect(entries[1].patch.contains("+new"))
        #expect(entries[0].patch.isEmpty)
        #expect(entries[2].newCommit == nil)
        #expect(entries[3].oldCommit == nil)
        #expect(entries[3].newCommit == "ccccccc")
    }
}

/// main and feature fork at the tag `fork`; feature changes a.txt twice, main
/// adds b.txt so a rebase has something to move onto.
private func makeForkedRepo() throws -> URL {
    let repoURL = try createIsolatedTestRepo()
    try createTestFile(in: repoURL, named: "a.txt", content: "one\n")
    try runGit(repoURL, "add", ".")
    try runGit(repoURL, "commit", "-q", "-m", "Initial")
    try runGit(repoURL, "tag", "fork")

    try runGit(repoURL, "checkout", "-q", "-b", "feature")
    try createTestFile(in: repoURL, named: "a.txt", content: "one\nfeature line (x)\n")
    try runGit(repoURL, "commit", "-q", "-am", "Feature adds a line\n\nwith body")
    try createTestFile(in: repoURL, named: "a.txt", content: "ONE\nfeature line (x)\n")
    try runGit(repoURL, "commit", "-q", "-am", "Feature edits a")

    try runGit(repoURL, "checkout", "-q", "main")
    try createTestFile(in: repoURL, named: "b.txt", content: "b\n")
    try runGit(repoURL, "add", ".")
    try runGit(repoURL, "commit", "-q", "-m", "Main adds b")
    return repoURL
}

@discardableResult
private func runGit(_ url: URL, _ arguments: String...) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", url.path] + arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ")])
    }
    return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
