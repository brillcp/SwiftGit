import Foundation

public protocol GitCommandable: Actor {
    @discardableResult
    func run(_ command: GitCommand) async throws -> CommandResult
}

// MARK: -
public actor CommandRunner {
    private let fileManager: FileManager
    private let repoURL: URL

    public init(repoURL: URL, fileManager: FileManager = .default) {
        self.repoURL = repoURL
        self.fileManager = fileManager
    }
}

// MARK: - GitCommandable
extension CommandRunner: GitCommandable {
    public func run(_ command: GitCommand) async throws -> CommandResult {
        let process = Process()
        process.executableURL = try findGitBinary()
        process.currentDirectoryURL = repoURL
        process.arguments = command.arguments

        var env = ProcessInfo.processInfo.environment
        env["GIT_PAGER"] = "cat"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_ASKPASS"] = ""
        env["GIT_EDITOR"] = ":"
        env["EDITOR"] = ":"
        env["VISUAL"] = ":"
        env["NO_COLOR"] = "1"
        env["CLICOLOR"] = "0"
        env["CLICOLOR_FORCE"] = "0"
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        try process.run()

        if let data = command.stdinData {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try stdinPipe.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self),
            exitCode: Int(process.terminationStatus)
        )
    }
}

// MARK: - Private functions
private extension CommandRunner {
    func findGitBinary() throws -> URL {
        // Try common paths
        let paths = [
            "/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]

        for path in paths {
            if fileManager.fileExists(atPath: path) {
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
    }
}
