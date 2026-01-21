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

        async let stdoutData = Task {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        async let stderrData = Task {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }.value

        process.waitUntilExit()

        let stdout = await stdoutData
        let stderr = await stderrData

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

                do {
                    let result = try await self.run(.log(limit: limit))

                    guard result.exitCode == 0 else {
                        throw GitError.logFailed(reason: result.stderr)
                    }

                    let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                    let commitLines = output.components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    // Parse commits and build parent lookup map in single pass
                    var commits: [Commit] = []
                    commits.reserveCapacity(commitLines.count)
                    var parentInfo: [String: [String]] = [:] // id -> parents array

                    for line in commitLines {
                        do {
                            let commit = try Commit.parse(from: line)
                            commits.append(commit)
                            parentInfo[commit.id] = commit.parents
                        } catch {
                            continue
                        }
                    }

                    // Build set of stash internal commit IDs
                    // Stash WIP: 2-3 parents [base, index, untracked?]
                    // Index: 1 parent [base] - same as WIP's first
                    // Untracked: 0 parents (orphan)
                    var stashInternalCommits = Set<String>()
                    for commit in commits where commit.parents.count >= 2 {
                        let baseParent = commit.parents[0]

                        // Check 2nd parent (index): 1 parent == base
                        let secondParentId = commit.parents[1]
                        if let secondParents = parentInfo[secondParentId],
                           secondParents.count == 1,
                           secondParents[0] == baseParent {
                            stashInternalCommits.insert(secondParentId)
                        }

                        // Check 3rd parent (untracked): 0 parents
                        if commit.parents.count >= 3 {
                            let thirdParentId = commit.parents[2]
                            if let thirdParents = parentInfo[thirdParentId],
                               thirdParents.isEmpty {
                                stashInternalCommits.insert(thirdParentId)
                            }
                        }
                    }

                    // Yield non-internal commits
                    for commit in commits where !stashInternalCommits.contains(commit.id) {
                        continuation.yield(commit)
                    }
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

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

    func makeGitProcess(
        arguments: [String],
        stdinData: Data? = nil
    ) throws -> (process: Process, stdout: Pipe, stderr: Pipe) {
        let process = Process()
        process.executableURL = try findGitBinary()
        process.currentDirectoryURL = repoURL
        process.arguments = arguments

        // Disable git pager to prevent interactive prompts
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["GIT_PAGER"] = ""

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
