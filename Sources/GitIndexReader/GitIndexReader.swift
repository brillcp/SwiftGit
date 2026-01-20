import Foundation

public protocol GitIndexReaderProtocol: Actor {
    /// Read the Git index file
    func readIndex(at url: URL) async throws -> GitIndexSnapshot
}

// MARK: -
public actor GitIndexReader {
    private let commandRunner: GitCommandable
    private let workingTreeParser: WorkingTreeParserProtocol

    public init(
        commandRunner: GitCommandable,
        workingTreeParser: WorkingTreeParserProtocol
    ) {
        self.commandRunner = commandRunner
        self.workingTreeParser = workingTreeParser
    }
}

// MARK: -  GitIndexReaderProtocol
extension GitIndexReader: GitIndexReaderProtocol {
    public func readIndex(at url: URL) async throws -> GitIndexSnapshot {
        let result = try await commandRunner.run(.lsFilesStaged)

        guard result.exitCode == 0 else {
            return GitIndexSnapshot(entries: [])
        }

        let entries = await parseIndexFromLsFilesStage(result.stdout)
        return GitIndexSnapshot(entries: entries)
    }
}

// MARK: - Private functions
private extension GitIndexReader {
    func parseIndexFromLsFilesStage(_ output: String) async -> [IndexEntry] {
        var entries: [IndexEntry] = []

        let lines = output.split(separator: String.newLine)

        for line in lines {
            if line.isEmpty {
                continue
            }
            // Format: <mode> <sha> <stage>\t<path>
            let parts = line.split(separator: String.tab)
            guard parts.count == 2 else { continue }
            let header = parts[0]
            let path = String(parts[1])

            let headerParts = header.split(separator: String.space)
            guard headerParts.count == 3 else { continue }
            let modeStr = String(headerParts[0])
            let sha = String(headerParts[1])
            // stage is headerParts[2] but ignored for now

            let modeValue = UInt32(modeStr, radix: 8) ?? 0
            let fileMode = FileMode(rawValue: modeValue) ?? .regular

            let zeroDate = Date(timeIntervalSince1970: 0)

            let entry = IndexEntry(
                path: path,
                sha1: sha,
                size: 0,
                mtime: zeroDate,
                mtimeNSec: 0,
                ctime: zeroDate,
                ctimeNSec: 0,
                dev: 0,
                ino: 0,
                uid: 0,
                gid: 0,
                fileMode: fileMode
            )

            entries.append(entry)
        }

        return entries
    }

}
