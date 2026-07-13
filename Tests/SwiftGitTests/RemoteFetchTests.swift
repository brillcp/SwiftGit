import Foundation
import Testing
@testable import SwiftGit

@Suite("Remote Fetch Tests")
struct RemoteFetchTests {
    @Test func testFetchPreservesLocalOnlyTag() async throws {
        let remoteURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: remoteURL) }

        let remoteRepository = GitRepository(url: remoteURL)
        try createTestFile(in: remoteURL, named: "release.txt", content: "v1")
        try await remoteRepository.stageFile(at: "release.txt")
        try await remoteRepository.commit(message: "Initial release")

        let localURL = try await clone(remoteURL, named: "local-tag")
        defer { try? FileManager.default.removeItem(at: localURL) }

        try git(in: localURL, "tag", "local-only")

        let localRepository = GitRepository(url: localURL)
        try await localRepository.fetch(remote: "origin", prune: true)

        let tags = try gitOutput(in: localURL, "tag", "--list", "local-only")
        #expect(tags == "local-only")
    }

    @Test func testFetchUpdatesRewrittenRemoteTag() async throws {
        let remoteURL = try createIsolatedTestRepo()
        defer { try? FileManager.default.removeItem(at: remoteURL) }

        let remoteRepository = GitRepository(url: remoteURL)
        try createTestFile(in: remoteURL, named: "release.txt", content: "v1")
        try await remoteRepository.stageFile(at: "release.txt")
        try await remoteRepository.commit(message: "Initial release")
        try git(in: remoteURL, "tag", "v1.0.0")

        let localURL = try await clone(remoteURL, named: "local")
        defer { try? FileManager.default.removeItem(at: localURL) }

        try createTestFile(in: remoteURL, named: "release.txt", content: "v2")
        try await remoteRepository.stageFile(at: "release.txt")
        try await remoteRepository.commit(message: "Retagged release")
        try git(in: remoteURL, "tag", "-f", "v1.0.0")

        let expectedTagTarget = try gitOutput(in: remoteURL, "rev-parse", "v1.0.0")
        let localRepository = GitRepository(url: localURL)

        try await localRepository.fetch(remote: "origin", prune: true)

        let actualTagTarget = try gitOutput(in: localURL, "rev-parse", "v1.0.0")
        #expect(actualTagTarget == expectedTagTarget)
    }
}

private extension RemoteFetchTests {
    func clone(_ repoURL: URL, named name: String) async throws -> URL {
        let cloneURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fetch-\(name)-\(UUID().uuidString)")
        try await GitRepository.clone(url: repoURL.path, to: cloneURL)
        return cloneURL
    }

    func git(in repoURL: URL, _ arguments: String...) throws {
        let result = try runGit(in: repoURL, arguments)
        guard result.exitCode == 0 else {
            throw TestGitError.commandFailed(result.stderr)
        }
    }

    func gitOutput(in repoURL: URL, _ arguments: String...) throws -> String {
        let result = try runGit(in: repoURL, arguments)
        guard result.exitCode == 0 else {
            throw TestGitError.commandFailed(result.stderr)
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func runGit(in repoURL: URL, _ arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        let task = Process()
        task.launchPath = "/usr/bin/git"
        task.arguments = ["-C", repoURL.path] + arguments

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        try task.run()
        task.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return (
            String(data: stdoutData, encoding: .utf8) ?? "",
            String(data: stderrData, encoding: .utf8) ?? "",
            task.terminationStatus
        )
    }
}

private enum TestGitError: Error {
    case commandFailed(String)
}
