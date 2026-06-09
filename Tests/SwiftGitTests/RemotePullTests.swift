import Foundation
import Testing
@testable import SwiftGit

@Suite("Remote Pull Tests")
struct RemotePullTests {
    @Test func testPullRejectedForNonFastForwardRemote() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "README.md", content: "initial")
        try await repository.stageFile(at: "README.md")
        try await repository.commit(message: "Initial commit")

        let localURL = try await clone(repoURL, named: "local")
        defer { try? FileManager.default.removeItem(at: localURL) }

        try createTestFile(in: repoURL, named: "remote.txt", content: "remote change")
        try await repository.stageFile(at: "remote.txt")
        try await repository.commit(message: "Remote change")

        let localRepository = GitRepository(url: localURL)
        try createTestFile(in: localURL, named: "local.txt", content: "local change")
        try await localRepository.stageFile(at: "local.txt")
        try await localRepository.commit(message: "Local change")
        try setPullConfig(in: localURL, key: "ff", value: "only")

        do {
            try await localRepository.pull()
            Issue.record("Expected pull to be rejected for diverged non-fast-forward history")
        } catch let error as GitError {
            switch error {
            case .pullRejected(let reason):
                #expect(!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            default:
                Issue.record("Expected pullRejected, got \(error)")
            }
        }

        #expect(try await localRepository.getConflictedFiles().isEmpty)
    }

    @Test func testPullConflictWhenMergeStartsAndConflicts() async throws {
        let repoURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: repoURL) }

        let repository = GitRepository(url: repoURL)
        try createTestFile(in: repoURL, named: "README.md", content: "initial")
        try await repository.stageFile(at: "README.md")
        try await repository.commit(message: "Initial commit")

        let localURL = try await clone(repoURL, named: "local")
        defer { try? FileManager.default.removeItem(at: localURL) }

        try createTestFile(in: repoURL, named: "README.md", content: "remote change")
        try await repository.stageFile(at: "README.md")
        try await repository.commit(message: "Remote change")

        let localRepository = GitRepository(url: localURL)
        try createTestFile(in: localURL, named: "README.md", content: "local change")
        try await localRepository.stageFile(at: "README.md")
        try await localRepository.commit(message: "Local change")
        try setPullConfig(in: localURL, key: "rebase", value: "false")

        do {
            try await localRepository.pull()
            Issue.record("Expected pull to report a merge conflict")
        } catch let error as GitError {
            switch error {
            case .pullConflict:
                break
            default:
                Issue.record("Expected pullConflict, got \(error)")
            }
        }

        #expect(try await localRepository.getConflictedFiles() == ["README.md"])
    }
}

private extension RemotePullTests {
    func clone(_ repoURL: URL, named name: String) async throws -> URL {
        let cloneURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pull-\(name)-\(UUID().uuidString)")
        try await GitRepository.clone(url: repoURL.path, to: cloneURL)
        return cloneURL
    }

    func setPullConfig(in repoURL: URL, key: String, value: String) throws {
        let configURL = repoURL
            .appendingPathComponent(GitPath.git.rawValue)
            .appendingPathComponent("config")
        var config = try String(contentsOf: configURL, encoding: .utf8)
        config += """

        [pull]
            \(key) = \(value)
        """
        try config.write(to: configURL, atomically: true, encoding: .utf8)
    }
}
