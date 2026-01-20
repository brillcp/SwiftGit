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
    let looseParser: LooseObjectParserProtocol
    let packReader: PackFileReaderProtocol
    let locator: ObjectLocatorProtocol
    let patchGenerator: PatchGenerator
    let commandRunner: GitCommandable
    let refReader: RefReaderProtocol
    let cache: ObjectCacheProtocol
    let fileManager: FileManager
    let diffParser: GitDiffParser

    var gitURL: URL {
        url.appendingPathComponent(GitPath.git.rawValue)
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
        self.locator = ObjectLocator(
            repoURL: url,
            packIndexManager: PackIndexManager(repoURL: url)
        )
        self.looseParser = LooseObjectParser()
        self.packReader = PackFileReader()
        self.diffParser = GitDiffParser()
        self.refReader = RefReader(
            repoURL: url,
            cache: cache
        )
        self.commandRunner = CommandRunner(repoURL: url)
        self.workingTreeParser = WorkingTreeParser()
        let indexReader = GitIndexReader(
            commandRunner: commandRunner,
            workingTreeParser: workingTreeParser
        )
        self.workingTree = WorkingTreeReader(
            repoURL: url,
            commandRunner: commandRunner,
            cache: cache,
            indexReader: indexReader
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
                throw GitError.workflowFailed(name: workflow.name ?? "workflow")
            }
        }

        await workingTree.invalidateIndexCache()

        if let event = workflow.onComplete {
            eventSubject.send(event)
        } else if let name = workflow.name {
            eventSubject.send(.workflowCompleted(name: name))
        }
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
