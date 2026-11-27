import Foundation
import Testing
@testable import SwiftGit

@Suite("Load State Tests")
struct LoadStateTests {
    // MARK: - Branch sync state parsing

    @Test func `Sync state parses upstreams and track counts`() {
        let output = [
            "refs/heads/main\0origin\0refs/remotes/origin/main\0",
            "refs/heads/feature/a\0origin\0refs/remotes/origin/feature/a\0[ahead 2]",
            "refs/heads/b\0team/fork\0refs/remotes/team/fork/b\0[behind 3]",
            "refs/heads/c\0origin\0refs/remotes/origin/c\0[ahead 1, behind 4]",
            "refs/heads/gone\0origin\0refs/remotes/origin/gone\0[gone]",
            "refs/heads/local-only\0\0\0",
            "refs/heads/tracks-local\0.\0refs/heads/main\0"
        ].joined(separator: "\n") + "\n"

        let states = BranchSyncState.parse(output)

        #expect(states.count == 4)
        #expect(states["main"] == BranchSyncState(
            upstream: Upstream(remote: "origin", branch: "main"),
            aheadBehind: AheadBehind(ahead: 0, behind: 0)
        ))
        #expect(states["feature/a"]?.upstream == Upstream(remote: "origin", branch: "feature/a"))
        #expect(states["feature/a"]?.aheadBehind == AheadBehind(ahead: 2, behind: 0))
        #expect(states["b"]?.upstream == Upstream(remote: "team/fork", branch: "b"))
        #expect(states["b"]?.aheadBehind == AheadBehind(ahead: 0, behind: 3))
        #expect(states["c"]?.aheadBehind == AheadBehind(ahead: 1, behind: 4))
        #expect(states["gone"] == nil)
        #expect(states["local-only"] == nil)
        #expect(states["tracks-local"] == nil)
    }

    @Test func `Sync state matches per-branch upstream and rev-list`() async throws {
        let remoteURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: remoteURL) }
        let remote = GitRepository(url: remoteURL)
        try createTestFile(in: remoteURL, named: "a.txt", content: "1")
        try await remote.stageAllFiles()
        try await remote.commit(message: "Initial")
        try git(remoteURL, "branch", "feature/x")

        let localURL = try clone(remoteURL)
        defer { try? FileManager.default.removeItem(at: localURL) }
        try git(localURL, "branch", "--track", "feature/x", "origin/feature/x")
        try git(localURL, "branch", "untracked")

        // Local main gets 2 commits, remote main 1, so main is ahead 2, behind 1.
        try createTestFile(in: remoteURL, named: "a.txt", content: "remote")
        try await remote.stageAllFiles()
        try await remote.commit(message: "Remote")
        let local = GitRepository(url: localURL)
        for content in ["l1", "l2"] {
            try createTestFile(in: localURL, named: "b.txt", content: content)
            try await local.stageAllFiles()
            try await local.commit(message: content)
        }
        try git(localURL, "fetch", "origin")

        let states = try await local.getBranchSyncState()

        #expect(Set(states.keys) == ["main", "feature/x"])
        for (name, state) in states {
            let upstream = try await local.getUpstream(for: name)
            #expect(state.upstream == upstream)
            let counts = try await local.getAheadBehind(local: name, upstream: state.upstream.refName)
            #expect(state.aheadBehind == counts)
        }
        #expect(states["main"]?.aheadBehind == AheadBehind(ahead: 2, behind: 1))
    }

    // MARK: - Branches

    @Test func `Branches name the current branch, or none when detached`() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "a.txt", content: "1")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Initial")
        try git(repoURL, "branch", "other")

        let attached = try await repository.getBranches()
        #expect(attached.current == "main")
        #expect(Set(attached.local.map(\.name)) == ["main", "other"])

        try git(repoURL, "checkout", "--detach")
        await repository.cache.clear()
        #expect(try await repository.getBranches().current == nil)
    }

    @Test func `A failed workflow leaves no stale HEAD in the cache`() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "a.txt", content: "1")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Initial")
        try git(repoURL, "checkout", "-q", "-b", "other")
        try createTestFile(in: repoURL, named: "a.txt", content: "2")
        try git(repoURL, "commit", "-q", "-am", "Other")
        try git(repoURL, "checkout", "-q", "main")

        let mainHash = try await repository.getHEAD()
        #expect(mainHash == (try gitOutput(repoURL, "rev-parse", "main")))
        let workflow = GitWorkflow(
            commands: [.checkout(branch: "other"), .merge(branch: "missing", noFastForward: true)],
            onComplete: .operationCompleted(operation: .merge, ref: "missing")
        )
        await #expect(throws: GitError.self) {
            try await repository.executeWorkflow(workflow)
        }

        let head = try await repository.getHEAD()
        #expect(head != mainHash)
        #expect(head == (try gitOutput(repoURL, "rev-parse", "other")))
    }

    // MARK: - Stashes

    @Test func `Stash list parses selector, hash, date and message`() {
        let hash0 = String(repeating: "a", count: 40)
        let hash1 = String(repeating: "b", count: 40)
        let output = [
            "stash@{0}\0\(hash0)\01700000000\0WIP on main: abc1234 fix: a: b",
            "stash@{1}\0\(hash1)\01600000000\0On feature/x: my message",
            "garbage"
        ].joined(separator: "\n")

        let stashes = RefReader.parseStashes(output)

        #expect(stashes == [
            Stash(hash: hash0, index: 0, message: "abc1234 fix: a: b", date: Date(timeIntervalSince1970: 1_700_000_000)),
            Stash(hash: hash1, index: 1, message: "my message", date: Date(timeIntervalSince1970: 1_600_000_000))
        ])
    }

    @Test func `Stashes list in order with their own hashes`() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "a.txt", content: "1")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Initial")

        for content in ["2", "3"] {
            try createTestFile(in: repoURL, named: "a.txt", content: content)
            try await repository.stashPush(message: "stash \(content)")
        }

        let stashes = try await repository.getStashes()

        #expect(stashes.map(\.index) == [0, 1])
        #expect(stashes.map(\.message) == ["stash 3", "stash 2"])
        #expect(stashes[0].hash == (try gitOutput(repoURL, "rev-parse", "stash@{0}")))
        #expect(stashes[1].hash == (try gitOutput(repoURL, "rev-parse", "stash@{1}")))
    }

    // MARK: - Refs

    @Test func `Refs reflect a new commit`() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }
        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "a.txt", content: "1")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Initial")

        async let first = repository.getRefs()
        async let second = repository.getRefs()
        let (a, b) = try await (first, second)
        #expect(a == b)

        try createTestFile(in: repoURL, named: "a.txt", content: "2")
        try await repository.stageAllFiles()
        try await repository.commit(message: "Second")

        let head = try gitOutput(repoURL, "rev-parse", "HEAD")
        #expect(try await repository.getRefs()[head] != nil)
    }
}

// MARK: - Helpers

private func clone(_ remoteURL: URL) throws -> URL {
    let localURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftGitLoadState-\(UUID().uuidString)")
    try git(remoteURL, "clone", remoteURL.path, localURL.path)
    try git(localURL, "config", "user.name", "Test")
    try git(localURL, "config", "user.email", "test@example.com")
    return localURL
}

private func git(_ url: URL, _ arguments: String...) throws {
    _ = try runGit(url, arguments)
}

private func gitOutput(_ url: URL, _ arguments: String...) throws -> String {
    try runGit(url, arguments)
}

private func runGit(_ url: URL, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = arguments
    process.currentDirectoryURL = url
    let stdout = Pipe()
    process.standardOutput = stdout
    process.standardError = Pipe()
    try process.run()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw GitError.cloneFailed("git " + arguments.joined(separator: " "))
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}
