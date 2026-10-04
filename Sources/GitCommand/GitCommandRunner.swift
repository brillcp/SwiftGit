import Foundation

public protocol GitCommandable: Actor {
    @discardableResult
    func run(_ command: GitCommand) async throws -> CommandResult
    func streamCommits(limit: Int, additionalRefs: [String]) -> AsyncThrowingStream<Commit, Error>
}

// MARK: -
public actor CommandRunner {
    private let fileManager: FileManager
    private let repoURL: URL
    private var cachedGitURL: URL?

    public init(repoURL: URL, fileManager: FileManager = .default) {
        self.repoURL = repoURL
        self.fileManager = fileManager
    }
}

// MARK: - GitCommandable
extension CommandRunner: GitCommandable {
    public func run(_ command: GitCommand) async throws -> CommandResult {
        try await run(command, onProgress: nil)
    }

    /// Runs a command, optionally reporting each line of stderr as it arrives (before the
    /// process exits). Used for long-running commands like `clone` where output should be
    /// surfaced incrementally rather than only once the process finishes.
    public func run(
        _ command: GitCommand,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> CommandResult {
        let (process, stdoutPipe, stderrPipe) = try makeGitProcess(
            arguments: command.arguments,
            stdinData: command.stdinData
        )

        try process.run()

        // Read stdout and stderr concurrently on background threads
        async let stdoutData = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        async let stderrData = Task.detached {
            Self.readStderr(stderrPipe.fileHandleForReading, onProgress: onProgress)
        }.value

        // Suspend the actor (freeing the thread) until the process exits
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }

        let stdout = await stdoutData
        let stderr = await stderrData

        return CommandResult(
            stdout: String(decoding: stdout, as: UTF8.self),
            stderr: String(decoding: stderr, as: UTF8.self),
            exitCode: Int(process.terminationStatus)
        )
    }

    public func streamCommits(limit: Int, additionalRefs: [String] = []) -> AsyncThrowingStream<Commit, Error> {
        AsyncThrowingStream { continuation in
            Task.detached { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                do {
                    let result = try await self.run(.log(limit: limit, additionalRefs: additionalRefs))

                    guard result.exitCode == 0 else {
                        throw GitError.logFailed(reason: result.stderr)
                    }

                    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let commitLines = output.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    for line in commitLines {
                        do {
                            let commit = try Commit.parse(from: line)
                            continuation.yield(commit)
                        } catch {
                            continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Private functions
private extension CommandRunner {
    /// Reads stderr incrementally, reporting each line to `onProgress` as soon as it's
    /// available. Git reports clone/fetch progress using `\r` to redraw the current line
    /// rather than `\n`, so both are treated as line terminators.
    static func readStderr(_ handle: FileHandle, onProgress: (@Sendable (String) -> Void)?) -> Data {
        guard let onProgress else {
            return handle.readDataToEndOfFile()
        }

        var collected = Data()
        var lineBuffer = Data()
        let lineTerminators: Set<UInt8> = [0x0A, 0x0D] // \n, \r

        while true {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)

            for byte in chunk {
                if lineTerminators.contains(byte) {
                    if !lineBuffer.isEmpty {
                        onProgress(String(decoding: lineBuffer, as: UTF8.self))
                        lineBuffer.removeAll(keepingCapacity: true)
                    }
                } else {
                    lineBuffer.append(byte)
                }
            }
        }

        if !lineBuffer.isEmpty {
            onProgress(String(decoding: lineBuffer, as: UTF8.self))
        }

        return collected
    }

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

    func makeGitProcess(
        arguments: [String],
        stdinData: Data? = nil
    ) throws -> (process: Process, stdout: Pipe, stderr: Pipe) {
        let process = Process()
        if cachedGitURL == nil { cachedGitURL = try findGitBinary() }
        process.executableURL = cachedGitURL
        process.currentDirectoryURL = repoURL
        process.arguments = arguments

        // Disable git pager and editor to prevent interactive prompts
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["GIT_PAGER"] = ""
        process.environment?["GIT_EDITOR"] = "true"

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
