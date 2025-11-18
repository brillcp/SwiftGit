import SwiftUI

public struct Commit: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let author: Author
    public let parents: [String]
    public let tree: String
}

// MARK: - Equatable
extension Commit: Equatable {
    public static func == (lhs: Commit, rhs: Commit) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: -
extension String {
    public var shortHash: String {
        String(prefix(6))
    }
}
