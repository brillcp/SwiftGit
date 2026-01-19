import Foundation

public protocol GitCommandable: Actor {
    @discardableResult
    func run(_ command: GitCommand) async throws -> CommandResult
    func streamCommits(limit: Int) -> AsyncThrowingStream<Commit, Error>
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
        let (process, stdoutPipe, stderrPipe) = try makeGitProcess(
            arguments: command.arguments,
            stdinData: command.stdinData
        )

        try process.run()
        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return CommandResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            exitCode: Int(process.terminationStatus)
        )
    }

    public func streamCommits(limit: Int) -> AsyncThrowingStream<Commit, Error> {
        AsyncThrowingStream { continuation in
            Task.detached { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                let command = GitCommand.log(limit: limit)
                let (process, stdoutPipe, _) = try await self.makeGitProcess(arguments: command.arguments, stdinData: command.stdinData)

                try process.run()
                if let pipe = process.standardInput as? Pipe {
                    try pipe.fileHandleForWriting.close()
                }

                let handle = stdoutPipe.fileHandleForReading
                var buffer = Data()

                while true {
                    if Task.isCancelled {
                        process.terminate()
                        continuation.finish()
                        return
                    }

                    let chunk = try handle.read(upToCount: 4096)
                    if let chunk = chunk, !chunk.isEmpty {
                        buffer.append(chunk)

                        while let range = buffer.range(of: Data("---END---".utf8)) {
                            let commitData = buffer.prefix(upTo: range.lowerBound)
                            buffer.removeSubrange(range.lowerBound..<range.upperBound)

                            let commit = try await parseCommitBlock(commitData)
                            continuation.yield(commit)
                        }
                    } else {
                        break
                    }
                }

                if !buffer.isEmpty, let commit = try? await parseCommitBlock(buffer) {
                    continuation.yield(commit)
                }

                process.waitUntilExit()
                continuation.finish()
            }
        }
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

    func parseCommitBlock(_ data: Data) throws -> Commit {
        let str = String(decoding: data, as: UTF8.self)
        let fields = str.split(separator: String.null, omittingEmptySubsequences: false)
        guard fields.count >= 11 else { throw GitError.nothingToCommit }

        return Commit(
            id: String(fields[0]),
            title: String(fields[9]),
            body: String(fields[10]),
            author: Author(
                name: String(fields[3]),
                email: String(fields[4]),
                timestamp: Date(timeIntervalSince1970: Double(fields[5]) ?? 0),
                timezone: ""
            ),
            committer: Author(
                name: String(fields[6]),
                email: String(fields[7]),
                timestamp: Date(timeIntervalSince1970: Double(fields[8]) ?? 0),
                timezone: ""
            ),
            parents: fields[1].split(separator: " ").map(String.init),
            tree: String(fields[2])
        )
    }

    func makeGitProcess(
        arguments: [String],
        stdinData: Data? = nil
    ) throws -> (process: Process, stdout: Pipe, stderr: Pipe) {
        let process = Process()
        process.executableURL = try findGitBinary()
        process.currentDirectoryURL = repoURL
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let stdinData {
            let pipe = Pipe()
            process.standardInput = pipe
            try pipe.fileHandleForWriting.write(contentsOf: stdinData)
            try pipe.fileHandleForWriting.close()
        }

        return (process, stdoutPipe, stderrPipe)
    }
}
