import Foundation
import Collections

public protocol WorkingTreeParserProtocol: Actor {
    /// Parse git status --porcelain output into working tree status
    func parseStatusOutput(_ output: String) async -> WorkingTreeStatus

    /// Parse git diff-index --cached output (staged files)
    func parseFilesNullDelimited(_ output: String) async -> OrderedDictionary<String, CommittedFile>
    func parseFilesNewlineDelimited(_ output: String) async -> OrderedDictionary<String, CommittedFile>
}

public actor WorkingTreeParser: @unchecked Sendable {
    public init() {
    }
}

// MARK: - WorkingTreeParserProtocol
extension WorkingTreeParser: WorkingTreeParserProtocol {
    public func parseStatusOutput(_ output: String) async -> WorkingTreeStatus {
        var files: OrderedDictionary<String, WorkingTreeFile> = [:]

        let lines = output.split(separator: String.null)

        var i = 0
        while i < lines.count {
            let line = lines[i]

            guard line.count >= 3,
                  let stagedChar = line.first,
                  let unstagedChar = line.dropFirst().first
            else {
                i += 1
                continue
            }

            let path = String(line.dropFirst(3))

            // Handle renames: R  new_path\0old_path OR  R new_path\0old_path
            if stagedChar == "R" || stagedChar == "C" || unstagedChar == "R" || unstagedChar == "C" {
                i += 1 // Move to next entry which contains the old path

                if i < lines.count {
                    let oldPath = String(lines[i])

                    let staged: GitChangeType? = (stagedChar == "R" || stagedChar == "C") ?
                        .renamed(from: oldPath) : parseChangeType(from: stagedChar, isStaged: true)
                    let unstaged: GitChangeType? = (unstagedChar == "R" || unstagedChar == "C") ?
                        .renamed(from: oldPath) : parseChangeType(from: unstagedChar, isStaged: false)

                    files[path] = WorkingTreeFile(
                        path: path,
                        staged: staged,
                        unstaged: unstaged
                    )
                } else {
                    // Malformed rename entry, treat as modified
                    files[path] = WorkingTreeFile(
                        path: path,
                        staged: parseChangeType(from: stagedChar, isStaged: true),
                        unstaged: parseChangeType(from: unstagedChar, isStaged: false)
                    )
                }
            } else {
                let staged = parseChangeType(from: stagedChar, isStaged: true)
                let unstaged = parseChangeType(from: unstagedChar, isStaged: false)

                files[path] = WorkingTreeFile(
                    path: path,
                    staged: staged,
                    unstaged: unstaged
                )
            }

            i += 1
        }

        return WorkingTreeStatus(files: files)
    }

    public func parseFilesNullDelimited(_ output: String) async -> OrderedDictionary<String, CommittedFile> {
        var files: OrderedDictionary<String, CommittedFile> = [:]

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

    public func parseFilesNewlineDelimited(_ output: String) async -> OrderedDictionary<String, CommittedFile> {
        var files: OrderedDictionary<String, CommittedFile> = [:]

        let lines = output.split(separator: String.newLine)

        for line in lines {
            let parts = line.split(separator: String.tab)
            guard parts.count >= 2 else { continue }

            let status = String(parts[0])

            // Handle renames: R100    oldPath    newPath
            if status.hasPrefix("R") || status.hasPrefix("C") {
                guard parts.count == 3 else { continue }
                let oldPath = String(parts[1])
                let newPath = String(parts[2])

                files[newPath] = CommittedFile(
                    path: newPath,
                    changeType: .renamed(from: oldPath)
                )
            } else {
                let path = String(parts[1])

                files[path] = CommittedFile(
                    path: path,
                    changeType: parseStatusCharacter(status)
                )
            }
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
        if let mapped = mapSimpleStatusCode(status) {
            return mapped
        }
        return .modified
    }

    func mapSimpleStatusCode(_ code: String) -> GitChangeType? {
        switch code {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R", "C": return .renamed(from: "")
        case "U": return .conflicted
        default: return nil
        }
    }
}
