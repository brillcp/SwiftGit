import Foundation

public struct Commit: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let author: Author
    public let committer: Author
    public let parents: [String]
    public let tree: String

    public init(
        id: String,
        title: String,
        body: String,
        author: Author,
        committer: Author,
        parents: [String],
        tree: String
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.author = author
        self.committer = committer
        self.parents = parents
        self.tree = tree
    }
}

// MARK: - Equatable
extension Commit: Equatable {
    public static func == (lhs: Commit, rhs: Commit) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Git Parsing
extension Commit {
    /// Parse a commit from git log output with null-separated fields
    /// Format: %H%x00%P%x00%T%x00%an%x00%ae%x00%at%x00%cn%x00%ce%x00%ct%x00%s%x00%b
    public static func parse(from gitLine: String) throws -> Commit {
        let fields = gitLine.split(separator: String.null, omittingEmptySubsequences: false)
        
        guard fields.count >= 11 else {
            throw GitError.nothingToCommit
        }
        
        return Commit(
            id: String(fields[0]),
            title: String(fields[9]),
            body: String(fields[10]),
            author: Author(
                name: String(fields[3]),
                email: String(fields[4]),
                timestamp: Date(timeIntervalSince1970: Double(fields[5]) ?? 0),
                timezone: ""
            ),
            committer: Author(
                name: String(fields[6]),
                email: String(fields[7]),
                timestamp: Date(timeIntervalSince1970: Double(fields[8]) ?? 0),
                timezone: ""
            ),
            parents: fields[1].isEmpty ? [] : fields[1].split(separator: " ").map(String.init),
            tree: String(fields[2])
        )
    }
}
