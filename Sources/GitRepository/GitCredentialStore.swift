import Foundation

/// A credential store that delegates to the system's configured git credential helper.
///
/// Runs `git credential approve` / `git credential erase` without a repository context —
/// these commands operate at the user level and are not repository-specific.
public actor GitCredentialStore: CredentialWritable {
    private let runner: CommandRunner

    public init() {
        // The working directory is irrelevant for credential commands.
        runner = CommandRunner(repoURL: FileManager.default.temporaryDirectory)
    }

    public func storeCredential(host: String, username: String, password: String) async throws {
        let result = try await runner.run(.credentialApprove(host: host, username: username, password: password))
        guard result.exitCode == 0 else { throw GitError.credentialStoreFailed(host: host) }
    }

    public func eraseCredential(host: String) async throws {
        let result = try await runner.run(.credentialErase(host: host))
        guard result.exitCode == 0 else { throw GitError.credentialEraseFailed(host: host) }
    }
}
