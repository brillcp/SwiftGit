import Foundation

public struct Commit: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let author: Author
    public let parents: [String]
    public let tree: String

    public init(id: String, title: String, body: String, author: Author, parents: [String], tree: String) {
        self.id = id
        self.title = title
        self.body = body
        self.author = author
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
