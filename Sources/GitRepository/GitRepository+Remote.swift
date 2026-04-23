import Foundation

extension GitRepository {
    /// Clone a remote repository to a local destination.
    /// This is a static method because no repository instance exists yet.
    public static func clone(url: String, to destination: URL) async throws {
        let parentDir = destination.deletingLastPathComponent()
        let runner = CommandRunner(repoURL: parentDir)
        let result = try await runner.run(.clone(url: url, destination: destination.path(percentEncoded: false)))

        guard result.exitCode == 0 else {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.cloneFailed(msg.isEmpty ? "Clone failed" : msg)
        }
    }

    /// Extract the repository name from a clone URL.
    /// Supports both HTTPS (`https://github.com/user/repo.git`) and SSH (`git@github.com:user/repo.git`).
    public static func repoName(from urlString: String) -> String? {
        var raw = urlString.trimmingCharacters(in: .whitespaces)
        if raw.hasSuffix(GitPath.git.rawValue) { raw = String(raw.dropLast(4)) }
        return raw.split(separator: "/").last.map(String.init)
            ?? raw.split(separator: ":").last.map(String.init)
    }
}

extension GitRepository: RemoteWritable {
    public func fetch(remote: String? = nil, prune: Bool = true) async throws {
        let result = try await backgroundRunner.run(
            .fetch(remote: remote, prune: prune)
        )

        guard result.exitCode == 0 else {
            throw GitError.fetchFailed
        }

        await cache.remove(.refs)
        eventSubject.send(.fetched(remote: remote ?? "origin"))
    }

    public func addRemote(name: String, url: String, at repoURL: URL) async throws {
        let result = try await commandRunner.run(.addRemote(name: name, url: url))

        guard result.exitCode == 0 else {
            let msg = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.remoteAddFailed(msg.isEmpty ? "Failed to add remote" : msg)
        }

        await cache.remove(.refs)
        eventSubject.send(.remoteAdded(name: name))
    }

    public func pull(remote: String? = nil, branch: String? = nil) async throws {
        let result = try await backgroundRunner.run(
            .pull(remote: remote, branch: branch)
        )

        guard result.exitCode == 0 else {
            let output = result.stderr + result.stdout

            if output.localizedCaseInsensitiveContains("conflict") {
                throw GitError.pullConflict
            }
            throw GitError.pullFailed
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await cache.clear {
            if case .commit = $0 { return true }
            return false
        }
        await workingTree.invalidateIndexCache()
        eventSubject.send(.pulled(remote: remote ?? "origin"))
    }
}
