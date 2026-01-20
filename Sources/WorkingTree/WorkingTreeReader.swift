import Foundation
import CommonCrypto

public protocol WorkingTreeReaderProtocol: Actor {
    func indexSnapshot() async throws -> GitIndexSnapshot

    /// Compute the current working tree status
    func workingTreeStatus() async throws -> WorkingTreeStatus

    /// Invalidate index cache
    func invalidateIndexCache() async
}

// MARK: -
public actor WorkingTreeReader {
    private let repoURL: URL
    private let fileManager: FileManager
    private let indexReader: GitIndexReaderProtocol
    private let cache: ObjectCacheProtocol
    private let commandRunner: GitCommandable
    private let workingTreeParser: WorkingTreeParserProtocol

    public init(
        repoURL: URL,
        commandRunner: GitCommandable,
        workingTreeParser: WorkingTreeParserProtocol = WorkingTreeParser(),
        cache: ObjectCacheProtocol,
        indexReader: GitIndexReaderProtocol,
        fileManager: FileManager = .default,
    ) {
        self.repoURL = repoURL
        self.fileManager = fileManager
        self.indexReader = indexReader
        self.commandRunner = commandRunner
        self.workingTreeParser = workingTreeParser
        self.cache = cache
    }
}

// MARK: - WorkingTreeReaderProtocol
extension WorkingTreeReader: WorkingTreeReaderProtocol {
    public func indexSnapshot() async throws -> GitIndexSnapshot {
        try await indexReader.readIndex(at: indexURL)
    }

    public func workingTreeStatus() async throws -> WorkingTreeStatus {
        let result = try await commandRunner.run(.status(porcelain: true))
        
        guard result.exitCode == 0 else {
            throw GitError.workingTreeStatusFailed
        }
        
        return await workingTreeParser.parseStatusOutput(result.stdout)
    }

    public func invalidateIndexCache() async {
        let url = indexURL
        await cache.remove(.indexSnapshot(url: url))
    }
}

// MARK: - Private
private extension WorkingTreeReader {
    var gitURL: URL {
        repoURL.appendingPathComponent(GitPath.git.rawValue)
    }

    var indexURL: URL {
        gitURL.appendingPathComponent(GitPath.index.rawValue)
    }
}
