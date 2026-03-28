import Testing
import Foundation
@testable import SwiftGit

@Suite("Credential Store Tests")
struct CredentialTests {

    // MARK: - GitCredentialStore

    /// `git credential approve` always exits 0 — even with no helper configured
    /// it just silently succeeds. Safe to call in CI.
    @Test("storeCredential exits without error")
    func testStoreCredential() async throws {
        let store = GitCredentialStore()
        try await store.storeCredential(
            host: "test.swiftgit.invalid",
            username: "testuser",
            password: "hunter2"
        )
    }

    /// `git credential erase` always exits 0 — even if the credential doesn't exist.
    @Test("eraseCredential exits without error")
    func testEraseCredential() async throws {
        let store = GitCredentialStore()
        try await store.eraseCredential(host: "test.swiftgit.invalid")
    }

    @Test("store then erase roundtrip")
    func testStoreAndEraseRoundtrip() async throws {
        let store = GitCredentialStore()
        try await store.storeCredential(
            host: "test.swiftgit.invalid",
            username: "testuser",
            password: "hunter2"
        )
        try await store.eraseCredential(host: "test.swiftgit.invalid")
    }

    // MARK: - MockCredentialStore (shows the protocol seam for Odin tests)

    @Test("MockCredentialStore captures calls correctly")
    func testMockCredentialStore() async throws {
        let mock = MockCredentialStore()

        try await mock.storeCredential(host: "github.com", username: "user", password: "token")
        try await mock.storeCredential(host: "gitlab.com", username: "user2", password: "token2")
        try await mock.eraseCredential(host: "github.com")

        let stored = await mock.storedCredentials
        let erased = await mock.erasedHosts

        #expect(stored.count == 2)
        #expect(stored[0] == ("github.com", "user", "token"))
        #expect(stored[1] == ("gitlab.com", "user2", "token2"))
        #expect(erased == ["github.com"])
    }
}

// MARK: - MockCredentialStore

/// Test double for `CredentialWritable`. Captures all calls in memory
/// without touching the system credential helper.
///
/// Use this in Odin tests:
/// ```swift
/// let mock = MockCredentialStore()
/// let auth = GitHubAuthManager(credentialStore: mock)
/// // … exercise auth …
/// let stored = await mock.storedCredentials
/// #expect(stored.first?.host == "github.com")
/// ```
actor MockCredentialStore: CredentialWritable {
    private(set) var storedCredentials: [(host: String, username: String, password: String)] = []
    private(set) var erasedHosts: [String] = []

    func storeCredential(host: String, username: String, password: String) async throws {
        storedCredentials.append((host, username, password))
    }

    func eraseCredential(host: String) async throws {
        erasedHosts.append(host)
    }
}
