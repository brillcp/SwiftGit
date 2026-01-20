import Foundation

public protocol WorkingTreeParserProtocol: Actor {
    /// Parse git status --porcelain output into working tree status
    func parseStatusOutput(_ output: String) async -> WorkingTreeStatus

    /// Parse git diff-index --cached output (staged files)
    func parseFilesOutput(_ output: String) async -> [String: CommittedFile]

    func parseIndexFromLsFilesStage(_ output: String) async -> [IndexEntry]
}

public actor WorkingTreeParser: @unchecked Sendable {
    public init() {
    }
}

// MARK: - WorkingTreeParserProtocol
extension WorkingTreeParser: WorkingTreeParserProtocol {
    public func parseStatusOutput(_ output: String) async -> WorkingTreeStatus {
        var files: [String: WorkingTreeFile] = [:]

        let lines = output.split(separator: String.newLine)

        for line in lines {
            guard line.count >= 3,
                  let stagedChar = line.first,
                  let unstagedChar = line.dropFirst().first
            else { continue }

            let path = String(line.dropFirst(3))

            let staged = parseChangeType(from: stagedChar, isStaged: true)
            let unstaged = parseChangeType(from: unstagedChar, isStaged: false)

            files[path] = WorkingTreeFile(
                path: path,
                staged: staged,
                unstaged: unstaged
            )
        }

        return WorkingTreeStatus(files: files)
    }

    public func parseFilesOutput(_ output: String) async -> [String: CommittedFile] {
        var files: [String: CommittedFile] = [:]

        let lines = output.split(separator: String.newLine)

        for line in lines {
            // Format: :100644 100644 hash1 hash2 M\tpath
            // or for renames: :100644 100644 hash1 hash2 R100\told\tnew
            let parts = line.split(separator: String.tab)
            guard parts.count >= 2 else { continue }

            let statusPart = parts[0].split(separator: String.space).last ?? ""
            let status = String(statusPart)

            if status.hasPrefix("R") {
                // Rename: old path and new path
                guard parts.count >= 3 else { continue }
                let oldPath = String(parts[1])
                let newPath = String(parts[2])

                files[newPath] = CommittedFile(
                    path: newPath,
                    changeType: .renamed(from: oldPath)
                )
            } else {
                let path = String(parts[1])
                let changeType = parseStatusCharacter(status)
                files[path] = CommittedFile(path: path, changeType: changeType)
            }
        }

        return files
    }

    public func parseIndexFromLsFilesStage(_ output: String) async -> [IndexEntry] {
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

// MARK: - Private Helpers
private extension WorkingTreeParser {
    func parseChangeType(from char: Character, isStaged: Bool) -> GitChangeType? {
        let s = String(char)
        if s == "?" { return isStaged ? nil : .untracked }
        return mapSimpleStatusCode(s)
    }

    func parseStatusCharacter(_ status: String) -> GitChangeType {
        if status.hasPrefix("R") {
            return .modified
        }
        if let mapped = mapSimpleStatusCode(status) {
            return mapped
        }
        return .modified
    }

    func mapSimpleStatusCode(_ code: String) -> GitChangeType? {
        switch code {
        case " ": return nil
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "U": return .conflicted
        case "!": return nil
        default: return nil
        }
    }
}
