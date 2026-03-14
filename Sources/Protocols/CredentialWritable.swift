import Foundation

/// Protocol for registering and removing git credentials
public protocol CredentialWritable: Actor {
    /// Registers credentials for a host with git's credential system.
    /// On macOS this writes to osxkeychain so subsequent git processes pick them up automatically.
    func storeCredential(host: String, username: String, password: String) async throws
    /// Removes stored credentials for a host from git's credential system.
    func eraseCredential(host: String) async throws
}
