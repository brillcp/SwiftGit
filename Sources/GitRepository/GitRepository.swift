import Foundation

public actor GitRepository: GitRepositoryProtocol {
    // MARK: Private properties
    private var securityScopeStarted: Bool = false
    private let locator: ObjectLocatorProtocol
    private let looseParser: LooseObjectParserProtocol
    private let packReader: PackFileReaderProtocol

    // MARK: - Internal properties
    let protectedBranches = ["main", "master", "develop", "production", "staging"]
    let diffCalculator: DiffCalculatorProtocol
    let workingTree: WorkingTreeReaderProtocol
    let diffGenerator: DiffGeneratorProtocol
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
        self.diffCalculator = DiffCalculator()
        self.diffGenerator = DiffGenerator()
        self.diffParser = GitDiffParser()
        self.refReader = RefReader(
            repoURL: url,
            cache: cache
        )
        self.workingTree = WorkingTreeReader(
            repoURL: url,
            indexReader: GitIndexReader(cache: cache),
            cache: cache
        )
        self.commandRunner = CommandRunner(repoURL: url)
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

// MARK: - Repository snapshot
public struct RepoSnapshot: Sendable {
    let head: String
    let commit: Commit
    let headTree: [String: String]
    let indexSnapshot: GitIndexSnapshot

    // Convenience accessors
    var index: [IndexEntry] {
        indexSnapshot.entries
    }

    var indexMap: [String: String] {
        indexSnapshot.entriesByPath.mapValues(\.sha1)
    }

    var conflictedPaths: [String] {
        indexSnapshot.conflictedPaths
    }
}

// MARK: - Helper functions
extension GitRepository {
    func getRepoSnapshot() async throws -> RepoSnapshot {
        guard let head = try await getHEAD(), let commit = try await getCommit(head) else {
            throw GitError.notARepository
        }

        return RepoSnapshot(
            head: head,
            commit: commit,
            headTree: try await getTreePaths(commit.tree),
            indexSnapshot: try await workingTree.indexSnapshot()
        )
    }

    /// Load an object from storage (loose or packed)
    func loadObject(hash: String) async throws -> ParsedObject? {
        guard let location = try await locator.locate(hash) else { return nil }

        switch location {
        case .loose(let fileURL):
            let data = try Data(contentsOf: fileURL)
            return try looseParser.parse(hash: hash, data: data)
        case .packed(let packLocation):
            guard let packIndex = try await locator.getPackIndex(for: packLocation.packURL) else {
                throw RepositoryError.packIndexNotFound
            }
            return try await packReader.parseObject(at: packLocation, packIndex: packIndex)
        }
    }
}