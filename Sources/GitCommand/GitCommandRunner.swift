import Foundation

public protocol GitCommandable: Actor {
    @discardableResult
    func run(_ command: GitCommand, in repo: URL) async throws -> CommandResult
}

// MARK: -
public actor CommandRunner {
    public init() {}
}

// MARK: - GitCommandable
extension CommandRunner: GitCommandable {
    public func run(_ command: GitCommand, in repo: URL) async throws -> CommandResult {
        #if os(macOS)
        let process = Process()
        process.executableURL = try findGitBinary()
        process.currentDirectoryURL = repo
        process.arguments = command.arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: outputData, encoding: .utf8) ?? ""
        let stderr = String(data: errorData, encoding: .utf8) ?? ""
        let exitCode = Int(process.terminationStatus)

        let result = CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode)

        if exitCode != 0 {
            throw GitError.commandFailed(command: command, result: result)
        }
        return result
        #else
        throw NSError(domain: "macOS only", code: 1337)
        #endif
    }
}

// MARK: - Private functions
private extension CommandRunner {
    func findGitBinary() throws -> URL {
        #if os(macOS)
        // Try common paths
        let paths = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        // Try xcrun (finds Xcode's git)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["-f", "git"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        
        throw GitError.gitNotFound
        #else
        throw NSError(domain: "macOS only", code: 1337)
        #endif
    }
}
