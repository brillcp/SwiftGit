import Foundation

public protocol GitCommandable: Actor {
    func run(_ command: GitCommand, in repo: URL) async throws -> CommandResult
}

// MARK: -
public actor CommandRunner {
    public init() {}
}

// MARK: - GitCommandable
extension CommandRunner: GitCommandable {
    public func run(_ command: GitCommand, in repo: URL) async throws -> CommandResult {
        .init(stdout: "", stderr: "", exitCode: 0)
    }
}
