import Foundation

public protocol GitIndexReaderProtocol: Actor {
    /// Read the Git index file
    func readIndex(at url: URL) async throws -> GitIndexSnapshot
}

// MARK: -
public actor GitIndexReader {
    private let cache: ObjectCacheProtocol
    private let commandRunner: GitCommandable
    private let workingTreeParser: WorkingTreeParserProtocol
    private let fileManager: FileManager

    public init(
        cache: ObjectCacheProtocol,
        commandRunner: GitCommandable,
        workingTreeParser: WorkingTreeParserProtocol,
        fileManager: FileManager = .default
    ) {
        self.cache = cache
        self.commandRunner = commandRunner
        self.workingTreeParser = workingTreeParser
        self.fileManager = fileManager
    }
}

// MARK: -  GitIndexReaderProtocol
extension GitIndexReader: GitIndexReaderProtocol {
    public func readIndex(at url: URL) async throws -> GitIndexSnapshot {
        let result = try await commandRunner.run(.lsFilesStaged)

        guard result.exitCode == 0 else {
            return GitIndexSnapshot(entries: [])
        }

        let entries = await workingTreeParser.parseIndexFromLsFilesStage(result.stdout)
        return GitIndexSnapshot(entries: entries)
    }
}
