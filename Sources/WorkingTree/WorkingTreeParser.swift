import Foundation

public protocol WorkingTreeParserProtocol: Actor {
    /// Parse git status --porcelain output into working tree status
    func parseStatusOutput(_ output: String) async -> WorkingTreeStatus

    /// Parse git diff-index --cached output (staged files)
    func parseFilesNullDelimited(_ output: String) async -> [String: CommittedFile]
    func parseFilesNewlineDelimited(_ output: String) async -> [String: CommittedFile]
}

public actor WorkingTreeParser: @unchecked Sendable {
    public init() {
    }
}

// MARK: - WorkingTreeParserProtocol
extension WorkingTreeParser: WorkingTreeParserProtocol {
    public func parseStatusOutput(_ output: String) async -> WorkingTreeStatus {
        var files: [String: WorkingTreeFile] = [:]

        let lines = output.split(separator: String.null)

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

    public func parseFilesNullDelimited(_ output: String) async -> [String: CommittedFile] {
        var files: [String: CommittedFile] = [:]

        let parts = output.split(separator: String.null)

        var i = 0
        while i < parts.count {
            let status = String(parts[i])
            i += 1

            if status.hasPrefix("R") || status.hasPrefix("C") {
                guard i + 1 < parts.count else { break }
                let oldPath = String(parts[i])
                let newPath = String(parts[i + 1])
                i += 2

                files[newPath] = CommittedFile(
                    path: newPath,
                    changeType: .renamed(from: oldPath)
                )
            } else {
                guard i < parts.count else { break }
                let path = String(parts[i])
                i += 1

                files[path] = CommittedFile(
                    path: path,
                    changeType: parseStatusCharacter(status)
                )
            }
        }

        return files
    }

    public func parseFilesNewlineDelimited(_ output: String) async -> [String: CommittedFile] {
        var files: [String: CommittedFile] = [:]

        let lines = output.split(separator: String.newLine)

        for line in lines {
            let parts = line.split(separator: String.tab, maxSplits: 1)
            guard parts.count == 2 else { continue }

            let status = String(parts[0])
            let path = String(parts[1])

            files[path] = CommittedFile(
                path: path,
                changeType: parseStatusCharacter(status)
            )
        }

        return files
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
