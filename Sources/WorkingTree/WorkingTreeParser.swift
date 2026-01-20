import Foundation

public protocol WorkingTreeParserProtocol: Actor {
    /// Parse git status --porcelain output into working tree status
    func parseStatusOutput(_ output: String) async -> WorkingTreeStatus
    
    /// Parse git diff-index --cached output (staged files)
    func parseStagedFiles(_ output: String) async -> [String: GitChangeType]
    
    /// Parse git diff-files output (unstaged files)
    func parseUnstagedFiles(_ output: String) async -> [String: GitChangeType]
    
    /// Parse git ls-files --others output (untracked files)
    func parseUntrackedFiles(_ output: String) async -> [String]
    
    /// Get index snapshot using Git commands
    func getIndexSnapshot() async throws -> GitIndexSnapshot
    
    /// Invalidate any working tree related caches
    func invalidateCache() async
}

public actor WorkingTreeParser: @unchecked Sendable {
    private let cache: any ObjectCacheProtocol
    private let commandRunner: GitCommandable
    private let indexReader: GitIndexReaderProtocol
    
    public init(cache: any ObjectCacheProtocol, commandRunner: GitCommandable, indexReader: GitIndexReaderProtocol) {
        self.cache = cache
        self.commandRunner = commandRunner
        self.indexReader = indexReader
    }
}

// MARK: - WorkingTreeParserProtocol
extension WorkingTreeParser: WorkingTreeParserProtocol {
    public func parseStatusOutput(_ output: String) async -> WorkingTreeStatus {
        var files: [String: WorkingTreeFile] = [:]

        let lines = output.split(separator: String.newLine)

        for line in lines {
            guard line.count >= 3 else { continue }

            let stagedChar = line.first!
            let unstagedChar = line.dropFirst().first!
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

    public func parseStagedFiles(_ output: String) async -> [String: GitChangeType] {
        return parseDiffIndexOutput(output)
    }

    public func parseUnstagedFiles(_ output: String) async -> [String: GitChangeType] {
        return parseDiffFilesOutput(output)
    }

    public func parseUntrackedFiles(_ output: String) async -> [String] {
        return output.split(separator: String.newLine)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    public func getIndexSnapshot() async throws -> GitIndexSnapshot {
        let result = try await commandRunner.run(.lsFilesStaged)
        
        guard result.exitCode == 0 else {
            // If no staged files or error, return empty snapshot
            return GitIndexSnapshot(entries: [], version: 2)
        }
        
        // Use the indexReader's parsing capability
//        return try await indexReader.parseGitLsFilesOutput(result.stdout)
        return GitIndexSnapshot(entries: [], version: 2)
    }

    public func invalidateCache() async {
        // Since we're using Git commands instead of manual index reading,
        // we don't need complex index snapshot caching.
        // This method is kept for API compatibility and future use.

        // If we add caching for Git command results in the future,
        // we would clear those caches here
    }
}

// MARK: - Private Helpers
private extension WorkingTreeParser {
    func parseChangeType(from char: Character, isStaged: Bool) -> GitChangeType? {
        switch char {
        case " ": return nil  // No change
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .modified  // Rename (simplified for now)
        case "C": return .modified  // Copy (simplified for now)
        case "U": return .conflicted
        case "?": return isStaged ? nil : .untracked
        case "!": return nil  // Ignored
        default: return nil
        }
    }
    
    func parseDiffIndexOutput(_ output: String) -> [String: GitChangeType] {
        var files: [String: GitChangeType] = [:]
        
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
                let newPath = String(parts[2])
                let oldPath = String(parts[1])
                files[newPath] = .renamed(from: oldPath)
            } else {
                let path = String(parts[1])
                let changeType = parseStatusCharacter(status)
                files[path] = changeType
            }
        }
        
        return files
    }
    
    func parseDiffFilesOutput(_ output: String) -> [String: GitChangeType] {
        var files: [String: GitChangeType] = [:]
        
        let lines = output.split(separator: String.newLine)

        for line in lines {
            // Format: :100644 100644 hash1 hash2 M\tpath
            let parts = line.split(separator: String.tab)
            guard parts.count >= 2 else { continue }
            
            let statusPart = parts[0].split(separator: String.space).last ?? ""
            let status = String(statusPart)
            let path = String(parts[1])
            
            let changeType = parseStatusCharacter(status)
            files[path] = changeType
        }
        
        return files
    }
    
    func parseStatusCharacter(_ status: String) -> GitChangeType {
        switch status {
        case "A": return .added
        case "M": return .modified
        case "D": return .deleted
        case "U": return .conflicted
        default:
            if status.hasPrefix("R") {
                return .modified  // Simplified rename handling
            }
            return .modified
        }
    }
}
