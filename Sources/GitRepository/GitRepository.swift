import Foundation
import Combine
public actor GitRepository: GitRepositoryProtocol {
    // MARK: Private properties
    private var securityScopeStarted: Bool = false

    // MARK: - Internal properties
    let protectedBranches = ["main", "master", "develop", "production", "staging"]
    let eventSubject = PassthroughSubject<GitEvent, Never>()
    let workingTreeParser: WorkingTreeParserProtocol
    let workingTree: WorkingTreeReaderProtocol
    let patchGenerator: PatchGenerator
    let commandRunner: GitCommandable
    let backgroundRunner: GitCommandable
    let refReader: RefReaderProtocol
    let cache: ObjectCacheProtocol
    let fileManager: FileManager
    let diffParser: GitDiffParser

    var gitURL: URL {
        let dotGit = url.appendingPathComponent(GitPath.git.rawValue)

        // Check if .git is a file (worktree) or directory (normal repo)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else {
            return dotGit
        }

        // Normal repo - .git is a directory
        if isDirectory.boolValue {
            return dotGit
        }

        // Worktree - .git is a file containing "gitdir: /path/to/git/dir"
        guard let content = try? String(contentsOf: dotGit, encoding: .utf8),
              let line = content.split(whereSeparator: \.isNewline).first else {
            return dotGit
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let prefix = "gitdir:"
        guard trimmed.lowercased().hasPrefix(prefix) else {
            return dotGit
        }

        let path = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return URL(fileURLWithPath: path, relativeTo: url).standardizedFileURL
    }

    // MARK: - Public properties
    public let url: URL
    public var events: AnyPublisher<GitEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    // MARK: - Init
    public init(url: URL, cache: ObjectCacheProtocol = ObjectCache()) {
        self.url = url
        self.cache = cache
        self.diffParser = GitDiffParser()
        self.commandRunner = CommandRunner(repoURL: url)
        self.backgroundRunner = CommandRunner(repoURL: url)
        self.refReader = RefReader(
            commandRunner: commandRunner,
            cache: cache
        )
        self.workingTreeParser = WorkingTreeParser()
        self.workingTree = WorkingTreeReader(
            repoURL: url,
            commandRunner: commandRunner,
            cache: cache,
            indexReader: GitIndexReader(commandRunner: commandRunner)
        )
        self.patchGenerator = PatchGenerator()
        self.fileManager = .default
        self.securityScopeStarted = url.startAccessingSecurityScopedResource()
    }

    // MARK: - Deinit
    deinit {
        if securityScopeStarted {
            url.stopAccessingSecurityScopedResource()
        }
    }

    public func executeWorkflow(_ workflow: GitWorkflow) async throws {
        for command in workflow.commands {
            let result = try await commandRunner.run(command)

            guard result.exitCode == 0 else {
                let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw GitError.workflowFailed(name: message.isEmpty ? (workflow.name ?? "workflow") : message)
            }
        }

        await cache.remove(.head)
        await cache.remove(.refs)
        await workingTree.invalidateIndexCache()
        eventSubject.send(workflow.onComplete)
    }
}

// MARK: - Repository error
public enum RepositoryError: LocalizedError {
    case objectNotFound(String)
    case invalidObjectType
    case corruptedRepository
    case packIndexNotFound

    public var errorDescription: String? {
        switch self {
        case .objectNotFound(let hash):
            return "Object not found: \(hash)"
        case .invalidObjectType:
            return "Invalid object type"
        case .corruptedRepository:
            return "Corrupted repository"
        case .packIndexNotFound:
            return "Pack index not found"
        }
    }
}
