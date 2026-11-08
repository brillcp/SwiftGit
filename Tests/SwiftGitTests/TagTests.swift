import Foundation
import Synchronization
import Testing
@testable import SwiftGit

@Suite("Tag Tests")
struct TagTests {
    @Test func testMoveLightweightTag() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let first = try await commit(in: repository, at: repoURL, content: "v1")
        try await repository.createTag(name: "release", ref: first, message: nil)
        let second = try await commit(in: repository, at: repoURL, content: "v2")

        try await repository.moveTag(name: "release", to: second)

        #expect(try git(in: repoURL, "rev-parse", "release") == second)
        #expect(try git(in: repoURL, "cat-file", "-t", "release") == "commit")
    }

    @Test func testMoveAnnotatedTagKeepsMessage() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let first = try await commit(in: repository, at: repoURL, content: "v1")
        try await repository.createTag(name: "v1.0", ref: first, message: "Munin 1.0\n\nFirst release")
        let second = try await commit(in: repository, at: repoURL, content: "v2")

        try await repository.moveTag(name: "v1.0", to: second)

        #expect(try git(in: repoURL, "rev-parse", "v1.0^{}") == second)
        #expect(try git(in: repoURL, "cat-file", "-t", "v1.0") == "tag")
        #expect(try git(in: repoURL, "tag", "-l", "--format=%(contents)", "v1.0") == "Munin 1.0\n\nFirst release")
    }

    @Test func testMoveTagEmitsEvent() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let first = try await commit(in: repository, at: repoURL, content: "v1")
        try await repository.createTag(name: "release", ref: first, message: nil)
        let second = try await commit(in: repository, at: repoURL, content: "v2")

        let recorded = Mutex<[GitEvent]>([])
        let observation = repository.eventPublisher.observe { event in
            recorded.withLock { $0.append(event) }
        }
        try await repository.moveTag(name: "release", to: second)
        observation.cancel()
        let events = recorded.withLock { $0 }

        #expect(events.count == 1)
        guard case .tagMoved(name: "release", ref: second) = events.first else {
            Issue.record("Moving a tag should emit only .tagMoved")
            return
        }
    }

    @Test func testMoveMissingTagFails() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        let head = try await commit(in: repository, at: repoURL, content: "v1")

        await #expect(throws: GitError.self) {
            try await repository.moveTag(name: "missing", to: head)
        }
    }

    @Test func testForcePushReplacesMovedRemoteTag() async throws {
        let remoteURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: remoteURL) }

        let remoteRepository = GitRepository(url: remoteURL)
        _ = try await commit(in: remoteRepository, at: remoteURL, content: "v1")

        let localURL = FileManager.default.temporaryDirectory.appendingPathComponent("tag-\(UUID().uuidString)")
        for try await _ in GitRepository.clone(url: remoteURL.path, to: localURL) {}
        defer { try? FileManager.default.removeItem(at: localURL) }

        let localRepository = GitRepository(url: localURL)
        let first = try git(in: localURL, "rev-parse", "HEAD")
        try await localRepository.createTag(name: "v1.0", ref: first, message: "Release")
        try await localRepository.pushTag(name: "v1.0", remote: "origin")

        let second = try await commit(in: localRepository, at: localURL, content: "v2")
        try await localRepository.moveTag(name: "v1.0", to: second)

        await #expect(throws: GitError.self) {
            try await localRepository.pushTag(name: "v1.0", remote: "origin")
        }
        try await localRepository.pushTag(name: "v1.0", remote: "origin", force: true)

        #expect(try git(in: remoteURL, "rev-parse", "v1.0^{}") == second)
    }
}

private extension TagTests {
    /// Commits a change to a file and returns the new commit hash.
    func commit(in repository: GitRepository, at repoURL: URL, content: String) async throws -> String {
        try createTestFile(in: repoURL, named: "file.txt", content: content)
        try await repository.stageFile(at: "file.txt")
        try await repository.commit(message: content)
        return try git(in: repoURL, "rev-parse", "HEAD")
    }

    /// Runs git in a repository and returns its trimmed output.
    func git(in repoURL: URL, _ arguments: String...) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", repoURL.path] + arguments
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
