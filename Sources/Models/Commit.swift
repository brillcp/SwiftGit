import SwiftUI

public struct Commit: Identifiable, Sendable {
    public let id: String
    let title: String
    let body: String
    let author: Author
    let parents: [String]
    let tree: String
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
