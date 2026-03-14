import Foundation

extension GitRepository: CredentialWritable {
    public func storeCredential(host: String, username: String, password: String) async throws {
        let result = try await commandRunner.run(.credentialApprove(host: host, username: username, password: password))

        guard result.exitCode == 0 else {
            throw GitError.credentialStoreFailed(host: host)
        }
    }

    public func eraseCredential(host: String) async throws {
        let result = try await commandRunner.run(.credentialErase(host: host))

        guard result.exitCode == 0 else {
            throw GitError.credentialEraseFailed(host: host)
        }
    }
}
